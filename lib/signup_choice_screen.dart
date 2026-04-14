import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'page_transition.dart';
import 'traveller_signup_screen.dart';
import 'host_signup_screen.dart';

class SignupChoiceScreen extends StatefulWidget {
  const SignupChoiceScreen({super.key});

  @override
  State<SignupChoiceScreen> createState() => _SignupChoiceScreenState();
}

class _SignupChoiceScreenState extends State<SignupChoiceScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation =
        CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// 🌄 BACKGROUND IMAGE (KEPT)
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/launch_bg.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),

          /// LIGHT OVERLAY (for black text visibility)
          Container(color: Colors.black.withOpacity(0.40)),

          /// CONTENT
          FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // 🔥 FULL CENTER
                    children: [
                      /// LOGO (BIGGER)
                      Image.asset(
                        'assets/logo.png',
                        height: 210,
                      ),

                      const SizedBox(height: 12),

                      /// APP NAME
                      const Text(
                        'SurfNStay',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),

                      const SizedBox(height: 8),

                      /// SUBTITLE
                      const Text(
                        'How would you like to sign up?',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 38),

                      /// TRAVELLER
                      SignupOptionTile(
                        image: 'assets/traveller.png',
                        title: 'Sign up as Traveller',
                        onTap: () {
                          Navigator.push(
                            context,
                            CustomPageRoute(child: const TravellerSignupScreen()),
                          );
                        },
                      ),

                      const SizedBox(height: 22),

                      /// HOST
                      SignupOptionTile(
                        image: 'assets/host.png',
                        title: 'Sign up as Host',
                        onTap: () {
                          Navigator.push(
                            context,
                            CustomPageRoute(child: const HostSignupScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// GRADIENT OPTION TILE
/// =========================
class SignupOptionTile extends StatefulWidget {
  final String image;
  final String title;
  final VoidCallback onTap;

  const SignupOptionTile({
    super.key,
    required this.image,
    required this.title,
    required this.onTap,
  });

  @override
  State<SignupOptionTile> createState() => _SignupOptionTileState();
}

class _SignupOptionTileState extends State<SignupOptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: AppColors.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          transform: _hovered
              ? (Matrix4.identity()
            ..translate(0.0, -3.0)
            ..scale(1.03))
              : Matrix4.identity(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(widget.image, height: 42, width: 42),
              const SizedBox(width: 14),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
