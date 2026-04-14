import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'wishlist_page.dart';
import 'profile_page.dart';
import 'messages_page.dart';
import 'ai_chatbot_page.dart';
import 'RoomDetailPage.dart';
import 'NotificationScreen.dart';
import 'package:badges/badges.dart' as badges;
import 'wishlist_service.dart';
import 'app_theme.dart';
import 'page_transition.dart';

class TravellerDashboard extends StatefulWidget {
  const TravellerDashboard({super.key});

  @override
  State<TravellerDashboard> createState() => _TravellerDashboardState();
}

class _TravellerDashboardState extends State<TravellerDashboard> {
  final supabase = Supabase.instance.client;
  int _selectedIndex = 0;
  bool loading = true;
  List<Map<String, dynamic>> rooms = [];

  static const Color primary = Color(0xFF0F4C5C);
  static const Color bg = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF64748B);

  String _searchQuery = "";
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  late final Stream<List<Map<String, dynamic>>> _notificationsStream;
  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  @override
  void initState() {
    super.initState();
    final user = supabase.auth.currentUser;
    if (user != null) {
      _notificationsStream = supabase.from('notifications').stream(primaryKey: ['id']).eq('user_id', user.id).map((events) => events.where((e) => e['is_read'] == false).toList());
      _messagesStream = supabase.from('messages').stream(primaryKey: ['id']).eq('receiver_id', user.id).map((events) => events.where((e) => e['is_read'] == false).toList());
    } else {
      _notificationsStream = const Stream.empty();
      _messagesStream = const Stream.empty();
    }
    fetchRooms();
  }

  Future<void> fetchRooms() async {
    setState(() => loading = true);

    try {
      final response = await supabase
          .from('properties')
          .select()
          .order('created_at', ascending: false);

      rooms = response.map<Map<String, dynamic>>((p) {
        List<String> imgs = [];

        if (p['image1_url'] != null && p['image1_url'] != "") {
          imgs.add(p['image1_url']);
        }
        if (p['image2_url'] != null && p['image2_url'] != "") {
          imgs.add(p['image2_url']);
        }
        if (p['image3_url'] != null && p['image3_url'] != "") {
          imgs.add(p['image3_url']);
        }

        return {
          "property_id": p['id'],          // ✅ added
          "host_id": p['host_id'],         // ✅ added
          "images": imgs,
          "price_per_night": p['price_per_night'] ?? "N/A",
          "location": p['location'] ?? "",
          "roomName": p['room_name'] ?? "Room",
        };
      }).toList();

      setState(() => loading = false);
    } catch (e) {
      print("Error fetching rooms: $e");
      setState(() => loading = false);
    }
  }

  Map<String, List<Map<String, dynamic>>> groupRooms() {
    // Filter rooms by search query first
    final query = _searchQuery.toLowerCase().trim();
    final filtered = query.isEmpty
        ? rooms
        : rooms.where((r) {
            final loc  = r["location"].toString().toLowerCase();
            final name = r["roomName"].toString().toLowerCase();
            return loc.contains(query) || name.contains(query);
          }).toList();

    Map<String, List<Map<String, dynamic>>> grouped = {
      "Islamabad": [],
      "Karachi": [],
      "Lahore": [],
      "Taxila": [],
      "Wah": [],
      "Other Cities": []
    };

    for (var room in filtered) {
      String loc = room["location"].toString().toLowerCase();
      if (loc.contains("islamabad")) {
        grouped["Islamabad"]!.add(room);
      } else if (loc.contains("karachi")) {
        grouped["Karachi"]!.add(room);
      } else if (loc.contains("lahore")) {
        grouped["Lahore"]!.add(room);
      } else if (loc.contains("taxila")) {
        grouped["Taxila"]!.add(room);
      } else if (loc.contains("wah")) {
        grouped["Wah"]!.add(room);
      } else {
        grouped["Other Cities"]!.add(room);
      }
    }
    return grouped;
  }

  void _onNavTap(int index) {
    if (_selectedIndex == index) return;

    Widget page;

    switch (index) {
      case 0:
        page = const TravellerDashboard();
        break;
      case 1:
        page = const WishlistPage();
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
      context,
      CustomPageRoute(child: page),
    );
  }

  BottomNavigationBarItem _bottomNavItem(
      IconData icon, String label, int index) {
    return BottomNavigationBarItem(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: _selectedIndex == index
            ? BoxDecoration(
          gradient: const LinearGradient(
            colors: AppColors.primaryGradient,
          ),
          borderRadius: BorderRadius.circular(12),
        )
            : null,
        child: Icon(
          icon,
          color: _selectedIndex == index ? Colors.white : textLight,
        ),
      ),
      label: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupRooms();
    List<String> cityOrder = [
      "Islamabad",
      "Karachi",
      "Lahore",
      "Taxila",
      "Wah",
      "Other Cities"
    ];

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.white,
        unselectedItemColor: textLight,
        showUnselectedLabels: true,
        backgroundColor: Colors.white,
        items: [
          _bottomNavItem(Icons.home, "Home", 0),
          _bottomNavItem(Icons.favorite, "Wishlist", 1),
          _bottomNavItem(Icons.smart_toy_outlined, "Chatbot", 2),
          _bottomNavItem(Icons.message_outlined, "Messages", 3),
          _bottomNavItem(Icons.person_outline, "Profile", 4),
        ],
        onTap: _onNavTap,
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _notificationsStream,
                      builder: (context, notifSnapshot) {
                        bool hasNotif = notifSnapshot.hasData && notifSnapshot.data!.isNotEmpty;
                        
                        return StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _messagesStream,
                          builder: (context, msgSnapshot) {
                            bool hasMsg = msgSnapshot.hasData && msgSnapshot.data!.isNotEmpty;
                            bool hasUnread = hasNotif || hasMsg;
                            
                            return badges.Badge(
                              showBadge: hasUnread,
                              position: badges.BadgePosition.topEnd(top: 8, end: 10),
                              child: IconButton(
                                icon: const Icon(Icons.notifications, size: 28, color: Color(0xFF0F4C5C)),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const NotificationScreen()),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Column(
                    children: [
                      Image.asset("assets/logo.png", height: 100),
                      const SizedBox(height: 2),
                      const Text(
                        "SurfNStay",
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: CustomInputDecoration.getDecoration(
                  "Search city, room name...",
                  prefixIcon: Icons.search,
                ).copyWith(
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = "");
                          },
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: () {
                final hasAnyRooms = cityOrder.any((c) => grouped[c]!.isNotEmpty);
                if (!hasAnyRooms && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'No results for "$_searchQuery"',
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = "");
                          },
                          child: const Text("Clear search"),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cityOrder.length,
                  itemBuilder: (context, cityIndex) {
                    final city = cityOrder[cityIndex];
                    final cityRooms = grouped[city]!;
                    if (cityRooms.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            city,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: cityRooms.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.63,
                          ),
                          itemBuilder: (context, index) =>
                              _roomCard(cityRooms[index]),
                        ),
                      ],
                    );
                  },
                );
              }(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roomCard(Map<String, dynamic> room) {
    List images = room["images"];
    String price = room["price_per_night"].toString();
    String location = room["location"];
    String roomName = room["roomName"] ?? "Room";

    String propertyId = room["property_id"].toString(); // ✅ added
    String hostId = room["host_id"].toString(); // ✅ added

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                CustomPageRoute(
                  child: RoomDetailPage(
                    roomName: roomName,
                    location: location,
                    images: List<String>.from(images),
                    price: double.tryParse(price) ?? 0,
                    propertyId: propertyId, // ✅ send
                    hostId: hostId, // ✅ send
                  ),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
                  child: images.isEmpty
                      ? Container(
                    height: 120,
                    color: Colors.grey[300],
                    child: const Center(
                        child:
                        Icon(Icons.broken_image, size: 40)),
                  )
                      : Image.network(
                    images[0],
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "PKR $price / night",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location,
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: StatefulBuilder(
              builder: (context, setCardState) {
                final inWishlist = WishlistService.instance.contains(propertyId);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    onTap: () {
                      if (inWishlist) {
                        WishlistService.instance.remove(propertyId);
                        setCardState(() {});
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                          const SnackBar(
                            content: Text("Removed from Wishlist"),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      } else {
                        WishlistService.instance.add({
                          'property_id': propertyId,
                          'host_id':     hostId,
                          'roomName':    roomName,
                          'location':    location,
                          'price':       double.tryParse(price) ?? 0,
                          'images':      List<String>.from(images),
                        });
                        setCardState(() {});
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                          SnackBar(
                            content: Text('"$roomName" added to Wishlist! ❤️'),
                            backgroundColor: AppColors.darkTeal,
                            duration: const Duration(seconds: 1),
                            action: SnackBarAction(
                              label: "View",
                              textColor: Colors.white,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  CustomPageRoute(child: const WishlistPage()),
                                );
                              },
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: inWishlist 
                          ? const LinearGradient(colors: [AppColors.darkTeal, AppColors.darkTeal]) // "gets dark"
                          : const LinearGradient(colors: AppColors.primaryGradient),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.darkTeal.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            inWishlist ? Icons.favorite : Icons.favorite_border,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            inWishlist ? "In Wishlist" : "Add to Wishlist",
                            style: const TextStyle(
                              color: Colors.white, 
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}