import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'traveller_dashboard.dart';
import 'wishlist_page.dart';
import 'messages_page.dart';
import 'profile_page.dart';

// ──────────────────────────────────────────────────────────────
//  CHANGE THIS URL:
//    Emulator  →  http://10.0.2.2:8000
//    Physical device on same WiFi → http://<YOUR_PC_IP>:8000
//    Cloud deployment → https://your-deployed-url.com
// ──────────────────────────────────────────────────────────────
const String _kApiBase = "http://10.0.2.2:8000";

class AiChatbotPage extends StatefulWidget {
  const AiChatbotPage({super.key});

  @override
  State<AiChatbotPage> createState() => _AiChatbotPageState();
}

class _AiChatbotPageState extends State<AiChatbotPage> {
  int _selectedIndex = 2;

  static const Color primary   = Color(0xFF0F4C5C);
  static const Color accent    = Color(0xFF26C6DA);
  static const Color bg        = Color(0xFFF7F9FB);
  static const Color textLight = Color(0xFF64748B);

  final TextEditingController _ctrl     = TextEditingController();
  final ScrollController       _scroll  = ScrollController();

  // Each message: { "sender": "user"/"bot"/"typing", "text": "..." }
  final List<Map<String, String>> _messages = [];
  String _sessionId = "";
  bool   _isLoading = false;
  bool   _apiOnline = true;

  @override
  void initState() {
    super.initState();
    _addBotMessage(
      "Assalam-o-Alaikum! 👋 Welcome to SurfNStay AI Assistant 🇵🇰\n\n"
      "I recommend the best tourist places in Pakistan based on ratings, "
      "your preferences and real user activity.\n\n"
      "✦ Try asking:\n"
      "• suggest parks in Islamabad for family\n"
      "• best malls in Lahore for friends\n"
      "• cheap hiking in Swat\n"
      "• romantic places in Murree\n\n"
      "Type  'more'  to see more results for your last search! 😊",
    );
  }

  void _addBotMessage(String text) {
    setState(() => _messages.add({"sender": "bot", "text": text}));
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _isLoading) return;

    _ctrl.clear();
    setState(() {
      _messages.add({"sender": "user", "text": text});
      _messages.add({"sender": "typing", "text": "..."});
      _isLoading = true;
    });
    _scrollDown();

    try {
      final response = await http.post(
        Uri.parse("$_kApiBase/chat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message":    text,
          "session_id": _sessionId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _sessionId = data["session_id"] ?? _sessionId;
        final reply = data["reply"] as String;

        setState(() {
          _messages.removeWhere((m) => m["sender"] == "typing");
          _messages.add({"sender": "bot", "text": reply});
          _isLoading = false;
          _apiOnline = true;
        });
      } else {
        _handleError("Server error ${response.statusCode}. Please try again.");
      }
    } catch (e) {
      _handleError(
        "⚠️ Cannot reach the AI server.\n\n"
        "Make sure chatbot_api.py is running:\n"
        "  uvicorn chatbot_api:app --host 0.0.0.0 --port 8000\n\n"
        "Error: $e",
      );
      setState(() => _apiOnline = false);
    }
  }

  void _handleError(String msg) {
    setState(() {
      _messages.removeWhere((m) => m["sender"] == "typing");
      _messages.add({"sender": "bot", "text": msg});
      _isLoading = false;
    });
    _scrollDown();
  }

  void _onNavTap(int index) {
    if (_selectedIndex == index) return;
    Widget page;
    switch (index) {
      case 0: page = const TravellerDashboard(); break;
      case 1: page = const WishlistPage();       break;
      case 2: page = const AiChatbotPage();      break;
      case 3: page = const MessagesPage();       break;
      case 4: page = const ProfilePage();        break;
      default: return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("SurfNStay AI", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text("Tourist Recommender",   style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _apiOnline ? Colors.green.shade700 : Colors.red.shade700,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(_apiOnline ? Icons.circle : Icons.circle_outlined,
                    size: 8, color: Colors.white),
                const SizedBox(width: 4),
                Text(_apiOnline ? "Online" : "Offline",
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Suggestion chips
          if (_messages.length == 1)
            _suggestionChips(),

          // Chat list
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _buildBubble(_messages[i]),
            ),
          ),

          // Input row
          _inputBar(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.white,
        unselectedItemColor: textLight,
        showUnselectedLabels: true,
        items: [
          _navItem(Icons.home,              "Home",     0),
          _navItem(Icons.favorite,          "Wishlist", 1),
          _navItem(Icons.smart_toy_outlined,"Chatbot",  2),
          _navItem(Icons.message_outlined,  "Messages", 3),
          _navItem(Icons.person_outline,    "Profile",  4),
        ],
        onTap: _onNavTap,
      ),
    );
  }

  // ── Suggestion Chips ──────────────────────────────────────────
  Widget _suggestionChips() {
    final chips = [
      "Parks in Islamabad",
      "Malls in Lahore",
      "Hiking in Swat",
      "Romantic Murree",
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: chips.map((c) => GestureDetector(
          onTap: () {
            _ctrl.text = c;
            _sendMessage();
          },
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F4C5C), Color(0xFF26C6DA)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(c, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        )).toList(),
      ),
    );
  }

  // ── Chat Bubble ────────────────────────────────────────────────
  Widget _buildBubble(Map<String, String> msg) {
    final isUser   = msg["sender"] == "user";
    final isTyping = msg["sender"] == "typing";

    if (isTyping) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8, left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18).copyWith(bottomLeft: Radius.zero),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) => _dot(i)),
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: accent,
              child: const Icon(Icons.smart_toy, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? primary : Colors.white,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: isUser   ? Radius.zero : const Radius.circular(18),
                bottomLeft:  !isUser  ? Radius.zero : const Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: (isUser ? primary : Colors.black).withOpacity(0.10),
                  blurRadius: 6, offset: const Offset(0, 3),
                ),
              ],
            ),
            child: SelectableText(
              msg["text"] ?? "",
              style: TextStyle(
                color: isUser ? Colors.white : const Color(0xFF1E293B),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ── Typing dots animation ──────────────────────────────────────
  Widget _dot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 500 + index * 150),
      builder: (_, v, __) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 7, height: 7,
        decoration: BoxDecoration(
          color: accent.withOpacity(0.4 + 0.6 * v),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  // ── Input Bar ─────────────────────────────────────────────────
  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: "Ask about places in Pakistan...",
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F4C5C), Color(0xFF26C6DA)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
                ],
              ),
              child: IconButton(
                icon: _isLoading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.white),
                onPressed: _isLoading ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom Nav Item ─────────────────────────────────────────────
  BottomNavigationBarItem _navItem(IconData icon, String label, int index) {
    return BottomNavigationBarItem(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: _selectedIndex == index
            ? BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F4C5C), Color(0xFF26C6DA)],
                ),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Icon(icon, color: _selectedIndex == index ? Colors.white : textLight),
      ),
      label: label,
    );
  }
}
