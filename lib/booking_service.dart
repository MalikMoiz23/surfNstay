import 'package:supabase_flutter/supabase_flutter.dart';

class BookingService {
  static final supabase = Supabase.instance.client;

  static Future<void> acceptBooking(String bookingId, String notificationId) async {
    // 1. Update Booking Status
    await supabase
        .from('bookings')
        .update({'status': 'confirmed'})
        .eq('id', bookingId);

    // 2. Fetch booking details to notify both parties
    final booking = await supabase
        .from('bookings')
        .select('traveller_id, properties(room_name, host_id), travellers(name)')
        .eq('id', bookingId)
        .single();

    final travellerId = booking['traveller_id'];
    final travellerName = booking['travellers']['name'] ?? "Traveller";
    final roomName = booking['properties']['room_name'] ?? "your room";
    final hostId = booking['properties']['host_id'];

    // 3. Notify Traveller
    await supabase.from('notifications').insert({
      'user_id': travellerId,
      'booking_id': bookingId,
      'category': 'booking_accepted', // ✅ Unified category
      'message': 'Stay Confirmed! Your booking for $roomName has been accepted by the host.',
    });

    // 4. Notify Host (Own confirmation)
    await supabase.from('notifications').insert({
      'user_id': hostId,
      'booking_id': bookingId,
      'category': 'booking_accepted', // ✅ Unified category
      'message': 'Booking Confirmed! You accepted $travellerName\'s request for $roomName.',
    });

    // 5. Mark current notification (the request) as read
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  static Future<void> rejectBooking(String bookingId, String notificationId) async {
    // 1. Update Booking Status
    await supabase
        .from('bookings')
        .update({'status': 'cancelled'})
        .eq('id', bookingId);

    // 2. Fetch booking details to notify traveller
    final booking = await supabase
        .from('bookings')
        .select('traveller_id, properties(room_name)')
        .eq('id', bookingId)
        .single();

    final travellerId = booking['traveller_id'];
    final roomName = booking['properties']['room_name'] ?? "your room";

    // 3. Notify Traveller
    await supabase.from('notifications').insert({
      'user_id': travellerId,
      'booking_id': bookingId,
      'category': 'booking_info',
      'message': 'Sorry, your booking request for $roomName was declined by the host.',
    });

    // 4. Mark current notification as read
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }
}
