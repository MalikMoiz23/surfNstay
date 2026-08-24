import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'RoomDetailPage.dart';
import 'ai_chatbot_page.dart';
import 'app_theme.dart';
import 'messages_page.dart';
import 'page_transition.dart';
import 'profile_page.dart';
import 'traveller_dashboard.dart';

/// A traveller's own bookings. Before this screen existed a traveller could
/// create a booking and then had no way to see, track or cancel it.
class MyTripsPage extends StatefulWidget {
  const MyTripsPage({super.key});

  @override
  State<MyTripsPage> createState() => _MyTripsPageState();
}

class _MyTripsPageState extends State<MyTripsPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  static const Color bg = Color(0xFFF7F9FB);
  static const Color textLight = Color(0xFF64748B);

  final int _selectedIndex = 1;

  late TabController _tabController;
  bool loading = true;
  List<Map<String, dynamic>> _bookings = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchBookings() async {
    if (mounted) setState(() => loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => loading = false);
        return;
      }

      final res = await supabase
          .from('bookings')
          .select('*, properties(*)')
          .eq('traveller_id', user.id)
          .order('start_date', ascending: false);

      if (!mounted) return;
      setState(() {
        _bookings = List<Map<String, dynamic>>.from(res);
        loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching trips: $e');
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load your trips: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool _isUpcoming(Map<String, dynamic> b) {
    final status = b['status'];
    if (status == 'cancelled' || status == 'expired') return false;
    final end = DateTime.parse(b['end_date']);
    return !end.isBefore(_today());
  }

  bool _isPast(Map<String, dynamic> b) {
    final status = b['status'];
    if (status == 'cancelled' || status == 'expired') return false;
    final end = DateTime.parse(b['end_date']);
    return end.isBefore(_today());
  }

  bool _isCancelled(Map<String, dynamic> b) =>
      b['status'] == 'cancelled' || b['status'] == 'expired';

  /// A traveller may withdraw a request or cancel a confirmed stay only before
  /// it starts. Once the stay has begun it is the host's to resolve.
  bool _canCancel(Map<String, dynamic> b) {
    final status = b['status'];
    if (status != 'pending' && status != 'confirmed') return false;
    return DateTime.parse(b['start_date']).isAfter(_today());
  }

  Future<void> _cancelBooking(Map<String, dynamic> b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel this booking?'),
        content: Text(
          b['status'] == 'pending'
              ? 'Your request will be withdrawn and the host will be notified.'
              : 'Your confirmed stay will be cancelled and the host will be notified. '
                  'These dates become available to other travellers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.rpc('cancel_booking', params: {
        'p_booking_id': b['id'],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Booking cancelled'),
            backgroundColor: AppColors.darkTeal),
      );
      await _fetchBookings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _openProperty(Map<String, dynamic> b) {
    final prop = b['properties'];
    if (prop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This property is no longer available.')),
      );
      return;
    }

    final images = <String>[];
    for (final key in ['image1_url', 'image2_url', 'image3_url']) {
      final url = prop[key];
      if (url != null && url.toString().isNotEmpty) images.add(url.toString());
    }

    Navigator.push(
      context,
      CustomPageRoute(
        child: RoomDetailPage(
          roomName: prop['room_name'] ?? 'Room',
          location: prop['location'] ?? 'Unknown',
          images: images,
          price: (prop['price_per_night'] as num?)?.toDouble() ?? 0,
          propertyId: prop['id'].toString(),
          hostId: prop['host_id'].toString(),
        ),
      ),
    ).then((_) => _fetchBookings());
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

    Navigator.pushReplacement(context, CustomPageRoute(child: page));
  }

  BottomNavigationBarItem _bottomNavItem(
      IconData icon, String label, int index) {
    return BottomNavigationBarItem(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: _selectedIndex == index
            ? BoxDecoration(
                gradient: const LinearGradient(
                    colors: AppColors.primaryGradient),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Icon(icon,
            color: _selectedIndex == index ? Colors.white : textLight),
      ),
      label: label,
    );
  }

  // ── Status presentation ────────────────────────────────────────────────

  ({Color color, IconData icon, String label}) _statusStyle(String status) {
    switch (status) {
      case 'pending':
        return (
          color: Colors.orange.shade700,
          icon: Icons.hourglass_top_rounded,
          label: 'Awaiting host'
        );
      case 'confirmed':
        return (
          color: Colors.green.shade700,
          icon: Icons.check_circle_rounded,
          label: 'Confirmed'
        );
      case 'completed':
        return (
          color: AppColors.darkTeal,
          icon: Icons.verified_rounded,
          label: 'Completed'
        );
      case 'expired':
        return (
          color: Colors.grey.shade600,
          icon: Icons.timer_off_rounded,
          label: 'Request expired'
        );
      case 'cancelled':
      default:
        return (
          color: Colors.red.shade600,
          icon: Icons.cancel_rounded,
          label: 'Cancelled'
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _bookings.where(_isUpcoming).toList();
    final past = _bookings.where(_isPast).toList();
    final cancelled = _bookings.where(_isCancelled).toList();

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.white,
        unselectedItemColor: textLight,
        showUnselectedLabels: true,
        backgroundColor: Colors.white,
        items: [
          _bottomNavItem(Icons.home, 'Home', 0),
          _bottomNavItem(Icons.luggage_rounded, 'Trips', 1),
          _bottomNavItem(Icons.smart_toy_outlined, 'Chatbot', 2),
          _bottomNavItem(Icons.message_outlined, 'Messages', 3),
          _bottomNavItem(Icons.person_outline, 'Profile', 4),
        ],
        onTap: _onNavTap,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: const BoxDecoration(
                gradient:
                    LinearGradient(colors: AppColors.primaryGradient),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.luggage_rounded,
                          color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      const Text(
                        'My Trips',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: _fetchBookings,
                      ),
                    ],
                  ),
                  TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    indicatorColor: Colors.white,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: [
                      Tab(text: 'Upcoming (${upcoming.length})'),
                      Tab(text: 'Past (${past.length})'),
                      Tab(text: 'Cancelled (${cancelled.length})'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.darkTeal))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(upcoming,
                            'No upcoming trips. Find a stay on the Home tab.'),
                        _buildList(past, 'No completed stays yet.'),
                        _buildList(cancelled, 'Nothing cancelled.'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items, String emptyMessage) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchBookings,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Icon(Icons.luggage_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Center(
              child: Text(emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: textLight)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchBookings,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, i) => _buildCard(items[i]),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> b) {
    final prop = b['properties'] as Map<String, dynamic>?;
    final status = (b['status'] ?? 'pending').toString();
    final style = _statusStyle(status);

    final start = DateTime.parse(b['start_date']);
    final end = DateTime.parse(b['end_date']);
    final nights = end.difference(start).inDays + 1;
    final fmt = DateFormat('MMM d, yyyy');

    final image = [prop?['image1_url'], prop?['image2_url'], prop?['image3_url']]
        .firstWhere((u) => u != null && u.toString().isNotEmpty,
            orElse: () => null);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openProperty(b),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: image == null
                          ? Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.image_not_supported,
                                  color: Colors.black26),
                            )
                          : Image.network(image.toString(), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prop?['room_name'] ?? 'Room',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 13, color: AppColors.lightTeal),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                prop?['location'] ?? 'Unknown',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: textLight),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: style.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(style.icon, size: 13, color: style.color),
                              const SizedBox(width: 5),
                              Text(
                                style.label,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: style.color),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                const Icon(Icons.event_rounded, size: 16, color: textLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${fmt.format(start)}  →  ${fmt.format(end)}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87),
                      ),
                      Text(
                        '$nights ${nights == 1 ? 'night' : 'nights'}',
                        style: const TextStyle(fontSize: 11, color: textLight),
                      ),
                    ],
                  ),
                ),
                Text(
                  'PKR ${(b['total_price'] as num?)?.toStringAsFixed(0) ?? '—'}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkTeal),
                ),
              ],
            ),
          ),
          if (_canCancel(b))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: Colors.red.shade100),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(b['status'] == 'pending'
                      ? 'Withdraw request'
                      : 'Cancel booking'),
                  onPressed: () => _cancelBooking(b),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
