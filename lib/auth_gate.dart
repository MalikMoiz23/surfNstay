import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_dashboard.dart';
import 'host_dashboard.dart';
import 'launch_screen.dart';
import 'login_screen.dart';
import 'traveller_dashboard.dart';

enum UserRole { admin, host, traveller, none }

/// Resolves which role the signed-in user has, and enforces the blocked flag
/// on every app start — not just at login.
class SessionResolver {
  static final _sb = Supabase.instance.client;

  /// Set when [resolve] signs a user out because their account is blocked, so
  /// the login screen can explain why they were kicked back.
  static String? blockedMessage;

  static Future<UserRole> resolve() async {
    final user = _sb.auth.currentUser;
    if (user == null) return UserRole.none;

    // The admins table only exists after sql/001_plan_a.sql has been applied.
    // Treat a missing table as "not an admin" so the app still runs before then.
    try {
      final admin = await _sb
          .from('admins')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      if (admin != null) return UserRole.admin;
    } catch (_) {
      // table absent or not readable — fall through to the other roles
    }

    final traveller = await _sb
        .from('travellers')
        .select('is_blocked')
        .eq('id', user.id)
        .maybeSingle();
    if (traveller != null) {
      if (traveller['is_blocked'] == true) return _signOutBlocked();
      return UserRole.traveller;
    }

    final host = await _sb
        .from('hosts')
        .select('is_blocked')
        .eq('id', user.id)
        .maybeSingle();
    if (host != null) {
      if (host['is_blocked'] == true) return _signOutBlocked();
      return UserRole.host;
    }

    // Authenticated but no profile row: the signup trigger has not run yet, or
    // the profile was deleted. Do not leave them in a half-signed-in state.
    await _sb.auth.signOut();
    return UserRole.none;
  }

  static Future<UserRole> _signOutBlocked() async {
    blockedMessage =
        'Your account has been blocked by the admin. Please contact support.';
    await _sb.auth.signOut();
    return UserRole.none;
  }
}

/// Root widget. Owns the decision of which screen the app shows, driven by the
/// Supabase session rather than by imperative navigation from the login screen.
///
/// Because this sits at the root, signing in or out anywhere in the app swaps
/// the tree automatically — screens should call `signOut()` and then
/// `Navigator.popUntil(context, (r) => r.isFirst)` rather than pushing
/// LoginScreen themselves.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _sb = Supabase.instance.client;

  StreamSubscription<AuthState>? _sub;
  UserRole? _role; // null while the first resolve is in flight
  bool _minimumSplashElapsed = false;

  /// Guards against an out-of-order resolve overwriting a newer one.
  int _resolveToken = 0;

  @override
  void initState() {
    super.initState();

    // supabase_flutter emits an initialSession event on subscribe, so this
    // covers both cold start and every later sign-in / sign-out / token refresh.
    _sub = _sb.auth.onAuthStateChange.listen((_) => _resolve());

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _minimumSplashElapsed = true);
    });
  }

  Future<void> _resolve() async {
    final token = ++_resolveToken;
    UserRole role;
    try {
      role = await SessionResolver.resolve();
    } catch (e) {
      debugPrint('AuthGate resolve failed: $e');
      role = UserRole.none;
    }
    if (!mounted || token != _resolveToken) return;
    setState(() => _role = role);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_role == null || !_minimumSplashElapsed) {
      return const LaunchScreen();
    }

    switch (_role!) {
      case UserRole.admin:
        return const AdminDashboard();
      case UserRole.host:
        return const HostDashboard();
      case UserRole.traveller:
        return const TravellerDashboard();
      case UserRole.none:
        return const LoginScreen();
    }
  }
}
