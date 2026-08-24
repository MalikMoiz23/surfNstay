import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'validators.dart';

class HostSignupScreen extends StatefulWidget {
  const HostSignupScreen({super.key});

  @override
  State<HostSignupScreen> createState() => _HostSignupScreenState();
}

class _HostSignupScreenState extends State<HostSignupScreen>
    with SingleTickerProviderStateMixin {
  // Animations
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  // 🔒 SINGLE SOURCE OF TRUTH (DO NOT CHANGE)
  static const Color primaryColor = Color(0xFF28AFC1);

  // Controllers
  final TextEditingController fullName = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController address = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController cnic = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController confirmPassword = TextEditingController();
  final supabase = Supabase.instance.client;

  // File? _cnicImage; // preview only
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.2),
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

  // CNIC IMAGE PICK (NOT SAVED)
  // Future<void> _pickCnicImage() async {
  //   final picked =
  //   await ImagePicker().pickImage(source: ImageSource.gallery);
  //   if (picked != null) {
  //     setState(() => _cnicImage = File(picked.path));
  //   }
  // }

  // CENTER MESSAGE WITH ANIMATION
  void _showCenterMessage(String message, {bool success = false}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 15),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    success ? Icons.check_circle : Icons.error,
                    size: 50,
                    color: success ? primaryColor : Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: child,
        );
      },
    );
  }

  // SIGNUP (SAME BACKEND LOGIC AS TRAVELLER)
  // Future<void> _signupHost() async {
  //   if (fullName.text.isEmpty ||
  //       phone.text.isEmpty ||
  //       address.text.isEmpty ||
  //       email.text.isEmpty ||
  //       cnic.text.isEmpty ||
  //       password.text.isEmpty ||
  //       confirmPassword.text.isEmpty) {
  //     _showCenterMessage("All fields are required");
  //     return;
  //   }
  //
  //   if (password.text != confirmPassword.text) {
  //     _showCenterMessage("Passwords do not match");
  //     return;
  //   }
  //
  //   setState(() => loading = true);
  //
  //   try {
  //     // Firebase Auth
  //     UserCredential userCred =
  //     await FirebaseAuth.instance.createUserWithEmailAndPassword(
  //       email: email.text.trim(),
  //       password: password.text.trim(),
  //     );
  //
  //     // Firestore (NO PASSWORD, NO IMAGE)
  //     await FirebaseFirestore.instance
  //         .collection('hosts')
  //         .doc(userCred.user!.uid)
  //         .set({
  //       'fullName': fullName.text.trim(),
  //       'phone': phone.text.trim(),
  //       'address': address.text.trim(),
  //       'email': email.text.trim(),
  //       'cnic': cnic.text.trim(),
  //       'role': 'host',
  //       'createdAt': Timestamp.now(),
  //     });
  //
  //     setState(() => loading = false);
  //
  //     _showCenterMessage(
  //       "Host account created successfully",
  //       success: true,
  //     );
  //
  //     Future.delayed(const Duration(milliseconds: 900), () {
  //       Navigator.pushReplacement(
  //         context,
  //         PageRouteBuilder(
  //           transitionDuration: const Duration(milliseconds: 600),
  //           pageBuilder: (_, anim, __) =>
  //               FadeTransition(opacity: anim, child: const LoginScreen()),
  //         ),
  //       );
  //     });
  //   } on FirebaseAuthException catch (e) {
  //     setState(() => loading = false);
  //     _showCenterMessage(e.message ?? "Firebase error");
  //   } catch (e) {
  //     setState(() => loading = false);
  //     _showCenterMessage("Error: $e");
  //   }
  // }

  Future<void> _signupHost() async {
    final error = Validators.required(fullName.text, 'Full name') ??
        Validators.phone(phone.text) ??
        Validators.required(address.text, 'Address') ??
        Validators.email(email.text) ??
        Validators.password(password.text) ??
        Validators.confirmPassword(password.text, confirmPassword.text);

    if (error != null) {
      _showCenterMessage(error);
      return;
    }

    setState(() => loading = true);

    try {
      // The hosts row is created by the on_auth_user_created trigger from this
      // metadata, so it works with RLS enabled and with email confirmation on.
      final response = await supabase.auth.signUp(
        email: email.text.trim(),
        password: password.text,
        data: {
          'role': 'host',
          'fullName': fullName.text.trim(),
          'phone': Validators.normalisePhone(phone.text),
          'address': address.text.trim(),
        },
      );

      if (!mounted) return;
      setState(() => loading = false);

      if (response.session != null) {
        _showCenterMessage("Host account created successfully", success: true);
        Future.delayed(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          Navigator.popUntil(context, (route) => route.isFirst);
        });
      } else {
        _showCenterMessage(
          "Account created. Check your inbox to confirm your email, then log in.",
          success: true,
        );
        Future.delayed(const Duration(milliseconds: 1600), () {
          if (!mounted) return;
          Navigator.popUntil(context, (route) => route.isFirst);
        });
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _showCenterMessage(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _showCenterMessage("Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/launch_bg.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Overlay
          Container(color: Colors.black.withOpacity(0.6)),

          // Content
          FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Host Signup',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // FORM BOX
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            _inputField("Full Name", fullName),
                            _inputField("Phone Number", phone,
                                keyboard: TextInputType.phone),
                            _inputField("Address", address),
                            _inputField("Email", email,
                                keyboard: TextInputType.emailAddress),
                            // _inputField("CNIC Number", cnic),
                            // const SizedBox(height: 10),
                            // GestureDetector(
                            //   onTap: _pickCnicImage,
                            //   child: Container(
                            //     height: 130,
                            //     decoration: BoxDecoration(
                            //       color: Colors.white.withOpacity(0.2),
                            //       borderRadius: BorderRadius.circular(16),
                            //       border: Border.all(color: Colors.white54),
                            //     ),
                            //     child: _cnicImage == null
                            //         ? const Center(
                            //       child: Text(
                            //         "Upload CNIC Front Image (Preview)",
                            //         style:
                            //         TextStyle(color: Colors.white70),
                            //       ),
                            //     )
                            //         : ClipRRect(
                            //       borderRadius: BorderRadius.circular(16),
                            //       child: Image.file(
                            //         _cnicImage!,
                            //         fit: BoxFit.cover,
                            //       ),
                            //     ),
                            //   ),
                            // ),
                            const SizedBox(height: 20),
                            _inputField("Password", password, isPassword: true),
                            _inputField("Confirm Password", confirmPassword,
                                isPassword: true),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      // 🔒 CREATE ACCOUNT BUTTON WITH GRADIENT
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: Material(
                          borderRadius: BorderRadius.circular(30),
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: loading ? null : _signupHost,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0F4C5C), // dark teal
                                    Color(0xFF26C6DA), // light cyan
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              alignment: Alignment.center,
                              child: loading
                                  ? const CircularProgressIndicator(
                                  color: Colors.white)
                                  : const Text(
                                'Create Account',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black),
                              ),
                            ),
                          ),
                        ),
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

  Widget _inputField(
      String hint,
      TextEditingController controller, {
        bool isPassword = false,
        TextInputType keyboard = TextInputType.text,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black45),
          filled: true,
          fillColor: Colors.white.withOpacity(0.7),
          contentPadding:
          const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
