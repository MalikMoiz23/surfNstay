import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'ReportRoomScreen.dart';
import 'booking_service.dart'; // ✅ added
import 'traveller_public_profile.dart'; // ✅ added
import 'RoomDetailPage.dart';  // ✅ added
import 'page_transition.dart'; // ✅ added
import 'ReportUserScreen.dart'; // ✅ added

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> notifications = [];
  bool loading = true;

  /// Realtime cannot carry the booking/property embed this screen needs, so
  /// the subscription is used purely as a signal to re-run the real query.
  StreamSubscription<List<Map<String, dynamic>>>? _liveSub;

  @override
  void initState() {
    super.initState();
    fetchNotifications();

    final user = supabase.auth.currentUser;
    if (user != null) {
      _liveSub = supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id)
          .listen((_) {
        if (mounted && !loading) fetchNotifications();
      }, onError: (e) => debugPrint('Notification stream error: $e'));
    }
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  Future<void> fetchNotifications() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final response = await supabase
          .from('notifications')
          .select('*, bookings(*, properties(*))')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        notifications = List<Map<String, dynamic>>.from(response);
        loading = false;
      });

      // Deliberately NOT marking everything read here. Opening the screen used
      // to wipe every unread flag, including booking requests the host had not
      // acted on yet, so the badge cleared while the work remained.
    } catch (e) {
      debugPrint("Error fetching notifications: $e");
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  /// Marks one notification read without disturbing the rest.
  Future<void> _markRead(Map<String, dynamic> notif) async {
    if (notif['is_read'] == true) return;
    setState(() => notif['is_read'] = true);
    try {
      await supabase
          .from('notifications')
          .update({'is_read': true}).eq('id', notif['id']);
    } catch (e) {
      debugPrint('Could not mark read: $e');
      if (mounted) setState(() => notif['is_read'] = false);
    }
  }

  Future<void> _markAllRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);
      await fetchNotifications();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> notif) async {
    await _markRead(notif);
    final bookingId = notif['booking_id'];
    if (bookingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This notification is not linked to a booking.")),
      );
      return;
    }

    final category = notif['category'];

    // 1. If it's a Booking Request -> View Traveller Profile
    if (category == 'booking_request') {
      try {
        final bookingData = await supabase
            .from('bookings')
            .select('traveller_id')
            .eq('id', bookingId)
            .single();
        
        final travellerId = bookingData['traveller_id'];
        
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TravellerPublicProfilePage(travellerId: travellerId),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
      return;
    }

    // 2. If it's a Booking Accepted -> View Room Detail (for Traveller) or Traveller Profile (for Host)
    if (category == 'booking_accepted') {
      try {
        // Fetch Booking, Property, and Host/Traveller IDs
        final bookingData = await supabase
            .from('bookings')
            .select('*, properties(*)')
            .eq('id', bookingId)
            .single();
        
        final user = supabase.auth.currentUser;
        if (user == null) return;

        final bool isHost = user.id == bookingData['properties']['host_id'];

        if (!mounted) return;

        if (isHost) {
          // Navigate to Traveller Profile
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TravellerPublicProfilePage(travellerId: bookingData['traveller_id']),
            ),
          );
        } else {
          // Navigate to Room Details (Reconstruct RoomDetailPage params)
          final prop = bookingData['properties'];
          List<String> images = [];
          if (prop['image1_url'] != null && prop['image1_url'] != "") images.add(prop['image1_url']);
          if (prop['image2_url'] != null && prop['image2_url'] != "") images.add(prop['image2_url']);
          if (prop['image3_url'] != null && prop['image3_url'] != "") images.add(prop['image3_url']);

          Navigator.push(
            context,
            CustomPageRoute(
              child: RoomDetailPage(
                roomName: prop['room_name'] ?? "Room",
                location: prop['location'] ?? "Unknown",
                images: images,
                price: (prop['price_per_night'] as num).toDouble(),
                propertyId: prop['id'].toString(),
                hostId: prop['host_id'].toString(),
              ),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
      return;
    }

    // 3. Original Report logic for travellers
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF0F4C5C))),
    );

    try {
      final bookingData = await supabase
          .from('bookings')
          .select('*, properties(*)')
          .eq('id', bookingId)
          .single();

      if (!mounted) return;
      Navigator.pop(context); // Remove loading dialog

      final startDate = DateTime.parse(bookingData['start_date']);
      final today = DateTime.now();
      final isCheckInDay = startDate.year == today.year && 
                           startDate.month == today.month && 
                           startDate.day == today.day;

      if (isCheckInDay) {
        final propertyId   = bookingData['property_id'];
        final prop         = bookingData['properties'];
        final propertyName = prop['room_name'] ?? prop['location'] ?? "this room";

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReportRoomScreen(
              propertyId: propertyId,
              bookingId: bookingId,
              propertyName: propertyName,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You can only report a room on your check-in date.")),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error checking booking: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _navigateToReport(Map<String, dynamic> notif) {
    final booking = notif['bookings'];
    if (booking == null) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final bool isHost = user.id == booking['properties']['host_id'];

    if (isHost) {
      // Host reporting traveller
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportUserScreen(
            travellerId: booking['traveller_id'],
            bookingId: booking['id'],
            propertyId: booking['property_id'], // ✅ added
            travellerName: "The Guest", 
          ),
        ),
      );
    } else {
      // Traveller reporting room
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportRoomScreen(
            propertyId: booking['property_id'],
            bookingId: booking['id'],
            propertyName: booking['properties']['room_name'] ?? "Room",
          ),
        ),
      );
    }
  }

  Future<void> _processBooking(Map<String, dynamic> notif, bool accepted) async {
    setState(() => loading = true);
    try {
      // The RPCs take text ids so they work regardless of the underlying
      // column type, so coerce here rather than assuming these are strings.
      final String bookingId = notif['booking_id'].toString();
      final String notifId = notif['id'].toString();

      if (accepted) {
        await BookingService.acceptBooking(bookingId, notifId);
      } else {
        await BookingService.rejectBooking(bookingId, notifId);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accepted ? "Booking Accepted! Info sent to traveller." : "Booking Declined."),
          backgroundColor: accepted ? Colors.green : Colors.red,
        ),
      );

      // Refresh list
      await fetchNotifications();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: const Color(0xFF0F4C5C),
        foregroundColor: Colors.white,
        actions: [
          if (notifications.any((n) => n['is_read'] != true))
            TextButton.icon(
              icon: const Icon(Icons.done_all_rounded,
                  size: 18, color: Colors.white),
              label: const Text('Mark all read',
                  style: TextStyle(color: Colors.white, fontSize: 12.5)),
              onPressed: _markAllRead,
            ),
        ],
      ),
      backgroundColor: const Color(0xFFF7F9FB),
      body: loading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F4C5C))) 
          : notifications.isEmpty 
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off, size: 60, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("No notifications yet.", style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 10),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notif = notifications[index];
                    final isRead = notif['is_read'] == true;
                    DateTime createdAt = DateTime.parse(notif['created_at']).toLocal();
                    String formattedTime = DateFormat('MMM d, yyyy - h:mm a').format(createdAt);

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _handleNotificationTap(notif),
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        elevation: isRead ? 0 : 2,
                        color: isRead ? Colors.white : const Color(0xFFE0F7FA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isRead ? Colors.grey.shade200 : const Color(0xFF26C6DA).withOpacity(0.5)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            onTap: () => _handleNotificationTap(notif),
                            leading: CircleAvatar(
                              backgroundColor: isRead ? Colors.grey[200] : const Color(0xFF26C6DA),
                              child: Icon(Icons.notifications, color: isRead ? Colors.grey[500] : Colors.white),
                            ),
                            title: Text(
                              notif['message'] ?? "",
                              style: TextStyle(
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(formattedTime, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                ),
                                 if (notif['booking_id'] != null && notif['category'] != 'booking_request')
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                      "Tap to report this room on check-in day",
                                      style: TextStyle(fontSize: 11, color: Color(0xFF0F4C5C), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                if (notif['category'] == 'booking_request' && notif['is_read'] == false) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () => _processBooking(notif, true),
                                          child: const Text("Accept"),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.redAccent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () => _processBooking(notif, false),
                                          child: const Text("Decline"),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else if (notif['category'] == 'booking_request' && notif['is_read'] == true)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      "Action Completed",
                                      style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
                                    ),
                                  ),

                                // NEW: Report Button on Check-in Day
                                if (notif['booking_id'] != null && notif['bookings'] != null) ...[
                                  () {
                                    final String? startDateStr = notif['bookings']['start_date'];
                                    if (startDateStr == null) return const SizedBox.shrink();
                                    
                                    final DateTime startDate = DateTime.parse(startDateStr);
                                    final DateTime now = DateTime.now();
                                    final bool isCheckInDay = (startDate.year == now.year && startDate.month == now.month && startDate.day == now.day);
                                    
                                    if (!isCheckInDay) return const SizedBox.shrink();

                                    final bool isHost = supabase.auth.currentUser?.id == notif['bookings']['properties']['host_id'];

                                    return Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.redAccent,
                                            side: const BorderSide(color: Colors.redAccent),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                          onPressed: () => _navigateToReport(notif),
                                          icon: const Icon(Icons.report_problem_outlined, size: 18),
                                          label: Text(isHost ? "Report Guest" : "Report Room Issue"),
                                        ),
                                      ),
                                    );
                                  }(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
