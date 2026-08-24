import 'package:flutter/material.dart';
import 'auth_gate.dart';
import 'traveller_dashboard.dart';
import 'wishlist_page.dart';
import 'my_trips_page.dart';
import 'messages_page.dart';
import 'ai_chatbot_page.dart';
import 'host_dashboard.dart';
import 'page_transition.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  int _selectedIndex = 4;

  String travellerName = "Traveller";
  String? profileImage;

  bool loadingProfile = true;

  static const Color primary = Color(0xFF0F4C5C);
  static const Color bg = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF1E293B);
  static const Color textLight = Color(0xFF64748B);
  static const Color danger = Color(0xFFFF6B6B);

  @override
  void initState() {
    super.initState();
    fetchProfile();
  }

  /// Fetch traveller profile
  Future<void> fetchProfile() async {
    try {
      final user = supabase.auth.currentUser;

      final data = await supabase
          .from('travellers')
          .select('name, profile_pic')
          .eq('id', user!.id)
          .single();

      setState(() {
        travellerName = data['name'] ?? "Traveller";
        profileImage = data['profile_pic'];
        loadingProfile = false;
      });
    } catch (e) {
      print("Profile fetch error: $e");
      setState(() {
        loadingProfile = false;
      });
    }
  }

  /// Upload profile image
  Future<void> uploadProfileImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);
    final user = supabase.auth.currentUser;

    // Delete old image if exists
    if (profileImage != null && profileImage!.contains('profile_')) {
      try {
        final segments = profileImage!.split('/');
        final fileName = segments.last.split('?').first; // get file name
        await supabase.storage.from('profile_pictures').remove([fileName]);
      } catch (e) {
        print("Old image deletion failed: $e");
      }
    }

    final fileName =
        "profile_${user!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg";

    // Upload new image
    await supabase.storage.from('profile_pictures').upload(fileName, file);

    // Get public URL
    final imageUrl =
    supabase.storage.from('profile_pictures').getPublicUrl(fileName);

    // Update profile in DB
    await supabase
        .from('travellers')
        .update({'profile_pic': imageUrl})
        .eq('id', user.id);

    setState(() {
      profileImage = imageUrl;
    });
  }

  void _onNavTap(int index) {
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
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: loadingProfile
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              /// Profile heading
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F4C5C), Color(0xFF26C6DA)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    "Profile",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              /// Profile card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withOpacity(0.15),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    /// Profile Image
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: primary.withOpacity(0.1),
                          backgroundImage: profileImage != null
                              ? NetworkImage(profileImage!)
                              : const AssetImage("assets/pro.jpg")
                          as ImageProvider,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: uploadProfileImage,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    /// Traveller Name
                    Text(
                      "Welcome, $travellerName",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),

              _actionTile(
                icon: Icons.storefront_outlined,
                title: "Switch to Host Mode",
                isPrimary: true,
                onTap: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    CustomPageRoute(child: const HostDashboard()),
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: 16),
              // Wishlist moved here when the Trips tab took its place in the nav bar.
              _actionTile(
                icon: Icons.favorite_border,
                title: "My Wishlist",
                onTap: () {
                  Navigator.push(
                    context,
                    CustomPageRoute(child: const WishlistPage()),
                  );
                },
              ),
              _actionTile(
                icon: Icons.settings_outlined,
                title: "Account Settings",
                onTap: () {},
              ),
              _actionTile(
                icon: Icons.help_outline,
                title: "Get Help",
                onTap: () {},
              ),
              _actionTile(
                icon: Icons.person_outline,
                title: "View Profile",
                onTap: () {},
              ),
              _actionTile(
                icon: Icons.privacy_tip_outlined,
                title: "Privacy",
                onTap: () {},
              ),
              const SizedBox(height: 10),

              /// Logout
              _actionTile(
                icon: Icons.logout,
                title: "Logout",
                textColor: danger,
                iconColor: danger,
                onTap: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (!context.mounted) return;
                  // Reset to AuthGate rather than pushing LoginScreen directly,
                  // so session state and the visible screen cannot disagree.
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthGate()),
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.white,
        unselectedItemColor: textLight,
        showUnselectedLabels: true,
        items: [
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

  Widget _actionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isPrimary = false,
    Color? textColor,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: isPrimary
            ? const LinearGradient(
          colors: [Color(0xFF0F4C5C), Color(0xFF26C6DA)],
        )
            : null,
        color: isPrimary ? null : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: iconColor ?? (isPrimary ? Colors.white : primary),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: textColor ?? (isPrimary ? Colors.white : textDark),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: isPrimary ? Colors.white : textLight,
        ),
        onTap: onTap,
      ),
    );
  }

  BottomNavigationBarItem _bottomNavItem(IconData icon, String label, int index) {
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
        child: Icon(
          icon,
          color: _selectedIndex == index ? Colors.white : textLight,
        ),
      ),
      label: label,
    );
  }
}