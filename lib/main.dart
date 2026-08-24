import 'package:flutter/material.dart';
import 'auth_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The anon key is intended to ship in the client. It is only safe because
  // Row Level Security restricts what it can reach — see sql/surfnstay_setup.sql.
  await Supabase.initialize(
    url: 'https://unxqxwmmbzyjwmavmvyz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVueHF4d21tYnp5andtYXZtdnl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3ODY4NTEsImV4cCI6MjA4ODM2Mjg1MX0.VoMox07mbUxAu5ysqLvzxM4Ilk6wlYV2qZPkelaQtg4',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'surfnstay',
      home: AuthGate(),
    );
  }
}
