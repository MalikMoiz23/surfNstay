import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'page_transition.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'signup_choice_screen.dart';
import 'traveller_dashboard.dart';
import 'host_dashboard.dart';
import 'admin_dashboard.dart';

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

  // final FirebaseAuth _auth = FirebaseAuth.instance;
  // final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final supabase = Supabase.instance.client;

  void login() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() => loading = true);

    try {
      // 🔑 Admin login
      if (email == 'admin@surfNstay.com' && password == '303136') {
        Navigator.pushReplacement(
          context,
          CustomPageRoute(child: const AdminDashboard()),
        );
        return;
      }

      // UserCredential userCred = await _auth.signInWithEmailAndPassword(
      //   email: email,
      //   password: password,
      // );
      //
      // String uid = userCred.user!.uid;

      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final uid = response.user!.id;



      // DocumentSnapshot travellerDoc =
      // await _firestore.collection('travellers').doc(uid).get();
      // if (travellerDoc.exists) {
      //   Navigator.pushReplacement(
      //     context,
      //     MaterialPageRoute(builder: (_) => const TravellerDashboard()),
      //   );
      //   return;
      // }

      final traveller = await supabase
          .from('travellers')
          .select()
          .eq('id', uid)
          .maybeSingle();

      if (traveller != null) {
        Navigator.pushReplacement(
          context,
          CustomPageRoute(child: const TravellerDashboard()),
        );
        return;
      }

      // DocumentSnapshot hostDoc =
      // await _firestore.collection('hosts').doc(uid).get();
      // if (hostDoc.exists) {
      //   Navigator.pushReplacement(
      //     context,
      //     MaterialPageRoute(builder: (_) => const HostDashboard()),
      //   );
      //   return;
      // }

      final host = await supabase
          .from('hosts')
          .select()
          .eq('id', uid)
          .maybeSingle();

      if (host != null) {
        Navigator.pushReplacement(
          context,
          CustomPageRoute(child: const HostDashboard()),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User role not found')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: ${e}')),
      );
    } finally {
      setState(() => loading = false);
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
                  Image.asset('assets/logo.png', height: 200),
                  const SizedBox(height: 15),
                  const Text(
                    'Welcome to SurfNStay',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your journey to comfortable stays begins here',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.white70),
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
