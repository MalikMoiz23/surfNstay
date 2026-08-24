import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'validators.dart';

class TravellerSignupScreen extends StatefulWidget {
  const TravellerSignupScreen({super.key});


  @override
  State<TravellerSignupScreen> createState() => _TravellerSignupScreenState();
}

class _TravellerSignupScreenState extends State<TravellerSignupScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  final Color primaryColor = const Color(0xFF28AFC1); // NEW BUTTON COLOR

  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController passwordCtrl = TextEditingController();
  final TextEditingController confirmPasswordCtrl = TextEditingController();
  final supabase = Supabase.instance.client;

  bool loading = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// BEAUTIFUL CENTER MESSAGE BOX
  void _showCenterMessage(String msg, {bool success = false}) {
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
                  BoxShadow(color: Colors.black26, blurRadius: 15)
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
                    msg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
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

  Future<void> signupTraveller() async {
    final error = Validators.required(nameCtrl.text, 'Full name') ??
        Validators.required(addressCtrl.text, 'Address') ??
        Validators.phone(phoneCtrl.text) ??
        Validators.email(emailCtrl.text) ??
        Validators.password(passwordCtrl.text) ??
        Validators.confirmPassword(
            passwordCtrl.text, confirmPasswordCtrl.text);

    if (error != null) {
      _showCenterMessage(error);
      return;
    }

    setState(() => loading = true);

    try {
      // UserCredential userCred =
      // await FirebaseAuth.instance.createUserWithEmailAndPassword(
      //   email: emailCtrl.text.trim(),
      //   password: passwordCtrl.text.trim(),
      // );
      //
      // await FirebaseFirestore.instance
      //     .collection('travellers')
      //     .doc(userCred.user!.uid)
      //     .set({
      //   'fullName': nameCtrl.text.trim(),
      //   'address': addressCtrl.text.trim(),
      //   'phone': phoneCtrl.text.trim(),
      //   'email': emailCtrl.text.trim(),
      //   'role': 'traveller',
      //   'createdAt': Timestamp.now(),
      // });

      // The profile row is created by the on_auth_user_created trigger from
      // this metadata. Inserting it here used to require an unauthenticated
      // write, which breaks the moment RLS is switched on — and silently
      // skipped the profile entirely when email confirmation was enabled.
      final response = await supabase.auth.signUp(
        email: emailCtrl.text.trim(),
        password: passwordCtrl.text,
        data: {
          'role': 'traveller',
          'name': nameCtrl.text.trim(),
          'phone': Validators.normalisePhone(phoneCtrl.text),
          'address': addressCtrl.text.trim(),
        },
      );

      if (!mounted) return;
      setState(() => loading = false);

      if (response.session != null) {
        // Signed in immediately — AuthGate will route to the dashboard once
        // this screen is popped off the stack.
        _showCenterMessage("Account created successfully", success: true);
        Future.delayed(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          Navigator.popUntil(context, (route) => route.isFirst);
        });
      } else {
        // Email confirmation is enabled on the project.
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
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/launch_bg.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.6)),

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
                        'Traveller Signup',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),

                      const SizedBox(height: 30),

                      /// FORM BOX (NO BUTTON INSIDE)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(18),
                          border:
                          Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            _inputField('Full Name', nameCtrl),
                            _inputField('Address', addressCtrl),
                            _inputField('Phone Number', phoneCtrl,
                                keyboard: TextInputType.phone),
                            _inputField('Email', emailCtrl,
                                keyboard: TextInputType.emailAddress),
                            _inputField('Password', passwordCtrl,
                                isPassword: true),
                            _inputField('Confirm Password',
                                confirmPasswordCtrl,
                                isPassword: true),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      /// BUTTON OUTSIDE FORM
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: Material(
                          borderRadius: BorderRadius.circular(30),
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: loading ? null : signupTraveller,
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
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text(
                                'Create Account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
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

  Widget _inputField(String hint, TextEditingController controller,
      {bool isPassword = false, TextInputType keyboard = TextInputType.text}) {
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
