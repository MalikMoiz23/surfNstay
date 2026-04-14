import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:surfNstay/login_screen.dart';
import 'host_dashboard.dart';
import 'messages_page.dart';
import 'traveller_dashboard.dart';
import 'NotificationScreen.dart';
import 'app_theme.dart';
import 'page_transition.dart';

class HostProfilePage extends StatefulWidget {
  const HostProfilePage({super.key});

  @override
  State<HostProfilePage> createState() => _HostProfilePageState();
}

class _HostProfilePageState extends State<HostProfilePage> {
  final supabase = Supabase.instance.client;

  int _selectedIndex = 2; // For host bottom nav: Home, Messages, Profile

  String hostName = "Host";
  String? profileImage;
  bool loadingProfile = true;

  static const Color primary = AppColors.darkTeal;
  static const Color bg = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF1E293B);
  static const Color textLight = Color(0xFF64748B);
  static const Color danger = Color(0xFFFF6B6B);

  @override
  void initState() {
    super.initState();
    fetchProfile();
  }

  Future<void> fetchProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = await supabase
          .from('hosts')
          .select('fullName, profile_pic')
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        setState(() {
          hostName = data['fullName'] ?? "Host";
          profileImage = data['profile_pic'];
          loadingProfile = false;
        });
      } else {
        setState(() => loadingProfile = false);
      }
    } catch (e) {
      print("Host Profile fetch error: $e");
      setState(() => loadingProfile = false);
    }
  }

  Future<void> uploadProfileImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);
    final user = supabase.auth.currentUser;

    setState(() => loadingProfile = true);

    try {
      final fileName = "host_profile_${user!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg";

      // Upload new image
      await supabase.storage.from('profile_pictures').upload(fileName, file);

      // Get public URL
      final imageUrl = supabase.storage.from('profile_pictures').getPublicUrl(fileName);

      // Update profile in DB
      await supabase
          .from('hosts')
          .update({'profile_pic': imageUrl})
          .eq('id', user.id);

      setState(() {
        profileImage = imageUrl;
        loadingProfile = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile picture updated!")),
      );
    } catch (e) {
      print("Image upload failed: $e");
      setState(() => loadingProfile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to upload image: $e")),
      );
    }
  }

  void _onNavTap(int index) {
    if (_selectedIndex == index) return;

    Widget page;
    switch (index) {
      case 0:
        page = const HostDashboard();
        break;
      case 1:
        page = const MessagesPage(isHost: true);
        break;
      case 2:
        return;
      default:
        return;
    }

    Navigator.pushReplacement(
      context,
      CustomPageRoute(child: page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: loadingProfile
            ? const Center(child: CircularProgressIndicator(color: primary))
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
                          colors: AppColors.primaryGradient,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: Text(
                          "Host Profile",
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
                                backgroundImage: (profileImage != null && profileImage!.isNotEmpty)
                                    ? NetworkImage(profileImage!)
                                    : const AssetImage("assets/pro.jpg") as ImageProvider,
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

                          /// Host Name
                          Text(
                            hostName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textDark,
                            ),
                          ),
                          const Text(
                            "Verified Host",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF28AFC1),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),

                    _actionTile(
                      icon: Icons.person_search_outlined,
                      title: "Switch to Traveller",
                      isPrimary: true,
                      onTap: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          CustomPageRoute(child: const TravellerDashboard()),
                          (route) => false,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _actionTile(
                      icon: Icons.home_work_outlined,
                      title: "My Properties",
                      onTap: () {
                         Navigator.pushReplacement(
                          context,
                          CustomPageRoute(child: const HostDashboard()),
                        );
                      },
                    ),
                    _actionTile(
                      icon: Icons.notifications_none_rounded,
                      title: "Notifications",
                      onTap: () {
                        Navigator.push(
                          context,
                          CustomPageRoute(child: const NotificationScreen()),
                        );
                      },
                    ),
                    _actionTile(
                      icon: Icons.payments_outlined,
                      title: "Earnings & Payments",
                      onTap: () {},
                    ),
                    _actionTile(
                      icon: Icons.settings_outlined,
                      title: "Account Settings",
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
                        await supabase.auth.signOut();
                        if (!mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          CustomPageRoute(child: const LoginScreen()),
                          (route) => false,
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF28AFC1),
        unselectedItemColor: textLight,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: "Messages"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
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
                colors: AppColors.primaryGradient,
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
}
