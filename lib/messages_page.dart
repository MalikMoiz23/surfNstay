import 'app_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'ChatScreen.dart';
import 'traveller_dashboard.dart';
import 'my_trips_page.dart';
import 'ai_chatbot_page.dart';
import 'profile_page.dart';
import 'host_dashboard.dart';
import 'host_profile_page.dart';
import 'page_transition.dart';

class MessagesPage extends StatefulWidget {
  final bool isHost;
  const MessagesPage({super.key, this.isHost = false});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final supabase = Supabase.instance.client;
  int _selectedIndex = 3;

  static const Color primary = Color(0xFF0F4C5C);
  static const Color bg = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF1E293B);
  static const Color textLight = Color(0xFF64748B);
  static const Color unreadBg = Color(0xFFE0F7FA);

  String userName = "Loading...";
  String? currentUserId;
  String? profileImageUrl;

  /// Fetch profile image for current user
  Future<void> _fetchProfileImage() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      // Try traveller profile picture
      var tRes = await supabase
          .from('travellers')
          .select('profile_pic')
          .eq('id', user.id)
          .maybeSingle();
      if (tRes != null && tRes['profile_pic'] != null) {
        setState(() {
          profileImageUrl = tRes['profile_pic'];
        });
        return;
      }
      // Try host profile picture
      var hRes = await supabase
          .from('hosts')
          .select('profile_pic')
          .eq('id', user.id)
          .maybeSingle();
      if (hRes != null && hRes['profile_pic'] != null) {
        setState(() {
          profileImageUrl = hRes['profile_pic'];
        });
      }
    } catch (e) {
      print('Profile image fetch error: $e');
    }
  }

  /// Upload profile imageUrl;

  // Cache of partner names so we don't re-fetch every rebuild
  final Map<String, String> _partnerNameCache = {};

  late final Stream<List<Map<String, dynamic>>> _chatsStream;

  @override
  void initState() {
    super.initState();
    final user = supabase.auth.currentUser;
    currentUserId = user?.id;
    if (currentUserId != null) {
      // Two server-filtered subscriptions, merged locally.
      //
      // This previously subscribed to the whole `chats` table and filtered in
      // Dart, which meant every device received every user's conversation
      // rows. Realtime filters only support a single `eq`, so the OR is
      // expressed as two streams. RLS (sql/surfnstay_setup.sql) is the real
      // boundary; this keeps the client from asking for rows it cannot use.
      _chatsStream = _mergeChatStreams(currentUserId!);
    } else {
      _chatsStream = const Stream.empty();
    }
    _fetchUserName();
    _fetchProfileImage();
  }

  /// Merges the "I am user1" and "I am user2" subscriptions into one ordered
  /// list, de-duplicated by chat id.
  Stream<List<Map<String, dynamic>>> _mergeChatStreams(String uid) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    final asUser1 = <String, Map<String, dynamic>>{};
    final asUser2 = <String, Map<String, dynamic>>{};

    void emit() {
      if (controller.isClosed) return;
      final merged = <String, Map<String, dynamic>>{...asUser1, ...asUser2};
      final rows = merged.values.toList()
        ..sort((a, b) {
          final at = DateTime.tryParse(a['updated_at']?.toString() ?? '');
          final bt = DateTime.tryParse(b['updated_at']?.toString() ?? '');
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at); // newest first
        });
      controller.add(rows);
    }

    final sub1 = supabase
        .from('chats')
        .stream(primaryKey: ['id'])
        .eq('user1_id', uid)
        .listen((rows) {
      asUser1
        ..clear()
        ..addEntries(rows.map((r) => MapEntry(r['id'].toString(), r)));
      emit();
    }, onError: controller.addError);

    final sub2 = supabase
        .from('chats')
        .stream(primaryKey: ['id'])
        .eq('user2_id', uid)
        .listen((rows) {
      asUser2
        ..clear()
        ..addEntries(rows.map((r) => MapEntry(r['id'].toString(), r)));
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await sub1.cancel();
      await sub2.cancel();
    };

    return controller.stream;
  }

  Future<void> _fetchUserName() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      var tRes = await supabase
          .from('travellers')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();
      if (tRes != null) {
        setState(() => userName = tRes['name'] ?? "Traveller");
      } else {
        var hRes = await supabase
            .from('hosts')
            .select('fullName')
            .eq('id', user.id)
            .maybeSingle();
        if (hRes != null) {
          setState(() => userName = hRes['fullName'] ?? "Host");
        }
      }
    } catch (e) {
      print("fetchUserName error: $e");
    }
  }

  Future<String> _getPartnerName(String partnerId) async {
    if (_partnerNameCache.containsKey(partnerId)) {
      return _partnerNameCache[partnerId]!;
    }
    try {
      var hRes = await supabase
          .from('hosts')
          .select('fullName')
          .eq('id', partnerId)
          .maybeSingle();
      if (hRes != null) {
        final name = hRes['fullName'] ?? "Host";
        _partnerNameCache[partnerId] = name;
        return name;
      }
      var tRes = await supabase
          .from('travellers')
          .select('name')
          .eq('id', partnerId)
          .maybeSingle();
      if (tRes != null) {
        final name = tRes['name'] ?? "Traveller";
        _partnerNameCache[partnerId] = name;
        return name;
      }
    } catch (e) {
      print("getPartnerName error: $e");
    }
    return "Unknown User";
  }

  void _onNavTap(int index) {
    if (widget.isHost) {
      if (index == 1) return;
      if (index == 0) {
        Navigator.pushReplacement(
            context, CustomPageRoute(child: const HostDashboard()));
      } else if (index == 2) {
        Navigator.pushReplacement(
            context, CustomPageRoute(child: const HostProfilePage()));
      }
      return;
    }
    if (_selectedIndex == index) return;
    Widget page;
    switch (index) {
      case 0:
        page = const TravellerDashboard();
        break;
      case 1:
        page = const MyTripsPage();
        break;
      case 2:
        page = const AiChatbotPage();
        break;
      case 3:
        page = const MessagesPage();
        break;
      case 4:
        page = const ProfilePage();
        break;
      default:
        return;
    }
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: primary.withOpacity(0.1),
                  backgroundImage: profileImageUrl != null
                      ? NetworkImage(profileImageUrl!)
                      : const AssetImage("assets/pro.jpg") as ImageProvider,
                ),
              const SizedBox(height: 12),
              Text(
                "Welcome, $userName",
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: textDark),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF0F4C5C), Color(0xFF26C6DA)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    "Messages",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _chatsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF0F4C5C)));
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text("Error: ${snapshot.error}"));
                    }
                    final chats = snapshot.data ?? [];
                    if (chats.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 60, color: Colors.grey),
                            SizedBox(height: 16),
                            Text("No conversations yet.",
                                style:
                                    TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        final partnerId = chat['user1_id'] == currentUserId
                            ? chat['user2_id']
                            : chat['user1_id'];
                        return FutureBuilder<String>(
                          future: _getPartnerName(partnerId),
                          builder: (context, nameSnapshot) {
                            final partnerName =
                                nameSnapshot.data ?? "Loading...";
                            final lastMsg =
                                chat['last_message'] ?? "No messages yet";
                            final updatedAt = chat['updated_at'] != null
                                ? DateFormat('MMM d - h:mm a').format(
                                    DateTime.parse(chat['updated_at'])
                                        .toLocal())
                                : "";

                            return _messageTile(
                              chatId: chat['id'],
                              partnerId: partnerId,
                              name: partnerName,
                              message: lastMsg,
                              time: updatedAt,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: widget.isHost ? 1 : _selectedIndex,
        backgroundColor: Colors.white,
        selectedItemColor:
            widget.isHost ? const Color(0xFF28AFC1) : Colors.white,
        unselectedItemColor: textLight,
        showUnselectedLabels: true,
        items: widget.isHost
            ? const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.home), label: "Home"),
                BottomNavigationBarItem(
                    icon: Icon(Icons.message), label: "Messages"),
                BottomNavigationBarItem(
                    icon: Icon(Icons.person), label: "Profile"),
              ]
            : [
                _bottomNavItem(Icons.home, "Home", 0),
                _bottomNavItem(Icons.luggage_rounded, "Trips", 1),
                _bottomNavItem(Icons.smart_toy_outlined, "Chatbot", 2),
                _bottomNavItem(Icons.message_outlined, "Messages", 3),
                _bottomNavItem(Icons.person_outline, "Profile", 4),
              ],
        onTap: _onNavTap,
      ),
    );
  }

  Widget _messageTile({
    required String chatId,
    required String partnerId,
    required String name,
    required String message,
    required String time,
  }) {
    // Real-time unread count for this chat
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('chat_id', chatId)
          .map((rows) => rows
              .where((r) =>
                  r['receiver_id'] == currentUserId &&
                  r['is_read'] == false)
              .toList()),
      builder: (context, unreadSnapshot) {
        final hasUnread =
            unreadSnapshot.hasData && unreadSnapshot.data!.isNotEmpty;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  chatId: chatId,
                  receiverId: partnerId,
                  receiverName: name,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasUnread ? unreadBg : Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: primary.withOpacity(0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF26C6DA),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : "?",
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: hasUnread
                              ? FontWeight.bold
                              : FontWeight.w600,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasUnread ? textDark : textLight,
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      time,
                      style:
                          const TextStyle(fontSize: 11, color: textLight),
                    ),
                    if (hasUnread)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF26C6DA),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  BottomNavigationBarItem _bottomNavItem(
      IconData icon, String label, int index) {
    return BottomNavigationBarItem(
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: _selectedIndex == index
              ? const LinearGradient(colors: AppColors.primaryGradient)
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedScale(
          scale: _selectedIndex == index ? 1.12 : 1,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: Icon(
          icon,
          color: _selectedIndex == index ? Colors.white : textLight,
        ),
        ),
      ),
      label: label,
    );
  }
}
