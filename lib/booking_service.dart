import 'package:supabase_flutter/supabase_flutter.dart';

/// Booking state changes run as single database transactions.
///
/// These used to be four sequential client-side writes (update status, read
/// details, insert two notifications, mark the source notification read). A
/// dropped connection part-way through left a confirmed booking that nobody
/// was told about, or a rejected booking whose dates stayed blocked. The SQL
/// functions in sql/001_plan_a.sql do all of it atomically and also enforce
/// that the caller actually owns the property.
class BookingService {
  static final supabase = Supabase.instance.client;

  /// Host accepts a request. Conflicting pending requests for the same dates
  /// are rejected and their travellers notified, inside the same transaction.
  static Future<void> acceptBooking(String bookingId, String notificationId) async {
    await supabase.rpc('accept_booking', params: {
      'p_booking_id': bookingId,
      'p_notification_id': notificationId,
    });
  }

  /// Host declines a request.
  static Future<void> rejectBooking(String bookingId, String notificationId) async {
    await supabase.rpc('reject_booking', params: {
      'p_booking_id': bookingId,
      'p_notification_id': notificationId,
    });
  }
}
