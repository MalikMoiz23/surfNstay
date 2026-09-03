import 'package:flutter/material.dart';
import 'animations.dart';
import 'app_theme.dart';
import 'page_transition.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';
import 'signup_choice_screen.dart';
import 'validators.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool loading = false;
  bool _obscurePassword = true; // 👁️ eye toggle

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    // If AuthGate signed someone out for being blocked, explain why.
    final msg = SessionResolver.blockedMessage;
    if (msg != null) {
      SessionResolver.blockedMessage = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      });
    }
  }

  void _snack(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : AppColors.darkTeal,
      ),
    );
  }

  /// Signs in only. Role routing and the blocked-account check live in
  /// [AuthGate], which reacts to the session change and swaps the root widget —
  /// so there is deliberately no Navigator call in the success path.
  void login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    final emailError = Validators.email(email);
    if (emailError != null) {
      _snack(emailError);
      return;
    }
    if (password.isEmpty) {
      _snack('Please enter your password');
      return;
    }

    setState(() => loading = true);

    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      // AuthGate takes over from here.
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Login failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 🌄 Background
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/launch_bg.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.55)),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  FadeSlideIn(index: 0, offsetY: 40,
                      child: Image.asset('assets/logo.png', height: 180)),
                  const SizedBox(height: 15),
                  const FadeSlideIn(
                    index: 1,
                    child: Text(
                      'Welcome to SurfNStay',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const FadeSlideIn(
                    index: 2,
                    child: Text(
                      'Your journey to comfortable stays begins here',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // 🔐 Login Box
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        _inputField(
                          'Email',
                          controller: emailController,
                          keyboard: TextInputType.emailAddress,
                        ),

                        // 👁️ Password with eye icon
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: TextField(
                            controller: passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.black),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              hintStyle:
                              const TextStyle(color: Colors.black45),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.7),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 18, horizontal: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[700],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        GradientButton(
                          text: 'Login',
                          onPressed: login,
                          loading: loading,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don’t have an account?",
                        style: TextStyle(color: Colors.white70),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            CustomPageRoute(child: const SignupChoiceScreen()),
                          );
                        },
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      )
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField(String hint,
      {required TextEditingController controller,
        bool isPassword = false,
        TextInputType keyboard = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.black),
        decoration: CustomInputDecoration.getDecoration(hint),
      ),
    );
  }
}
