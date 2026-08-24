import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'ChatScreen.dart';
import 'app_theme.dart';
import 'page_transition.dart';
import 'host_public_profile.dart';

class RoomDetailPage extends StatefulWidget {
  final String roomName;
  final String location;
  final List<String> images;
  final double price;
  final String propertyId;
  final String hostId;

  const RoomDetailPage({
    super.key,
    required this.roomName,
    required this.location,
    required this.images,
    required this.price,
    required this.propertyId,
    required this.hostId,
  });

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  final supabase = Supabase.instance.client;
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;

  bool loading = true;

  String facilities  = "No facilities provided";
  String description = "No description provided";
  String hostName    = "Unknown Host";
  String hostPhone   = "N/A";

  // New property fields
  String propertyType    = 'Room';
  String guestPreference = 'Any';
  int bedrooms           = 1;
  int bathrooms          = 1;
  int maxGuests          = 1;

  /// Percentage off the nightly rate. Was previously stored by the host and
  /// then never applied to anything the guest saw or paid.
  double discountPercent = 0;

  /// Nightly rate actually charged, after [discountPercent].
  double get effectivePrice =>
      (widget.price * (1 - discountPercent / 100)).clamp(0, widget.price);

  bool get hasDiscount => discountPercent > 0;

  List<DateTime> bookedDates = [];

  // Rating state
  double averageRating   = 0.0;
  int    totalRatings    = 0;
  double? myExistingRating;  // null if not yet rated
  String? eligibleBookingId; // booking id that qualifies for rating today
  bool   ratingLoading   = false;

  static const Map<String, IconData> _typeIcons = {
    'Room':      Icons.meeting_room_rounded,
    'Apartment': Icons.apartment_rounded,
    'House':     Icons.house_rounded,
    'Villa':     Icons.villa_rounded,
  };

  @override
  void initState() {
    super.initState();
    fetchExtraDetails();
  }

  Future<void> fetchExtraDetails() async {
    setState(() => loading = true);
    try {
      // Property details
      final propRes = await supabase
          .from('properties')
          .select()
          .eq('id', widget.propertyId)
          .maybeSingle();

      if (propRes != null) {
        facilities      = propRes['facilities']?.toString()  ?? "No facilities provided";
        description     = propRes['description']?.toString() ?? "No description provided";
        propertyType    = propRes['property_type']?.toString() ?? 'Room';
        guestPreference = propRes['guest_preference']?.toString() ?? 'Any';
        bedrooms        = int.tryParse(propRes['bedrooms']?.toString() ?? '1') ?? 1;
        bathrooms       = int.tryParse(propRes['bathrooms']?.toString() ?? '1') ?? 1;
        maxGuests       = int.tryParse(propRes['max_guests']?.toString() ?? '1') ?? 1;
        discountPercent =
            (double.tryParse(propRes['discount']?.toString() ?? '0') ?? 0)
                .clamp(0, 100);
      }

      // Host details
      final hostRes = await supabase
          .from('hosts')
          .select('fullName, phone')
          .eq('id', widget.hostId)
          .maybeSingle();

      if (hostRes != null) {
        hostName  = hostRes['fullName'] ?? "Unknown Host";
        hostPhone = hostRes['phone']    ?? "N/A";
      }

      // Booked dates for the calendar. Only genuinely unavailable dates block:
      // a pending request holds the dates for one hour and then stops counting,
      // so an unaccepted request can no longer lock a property indefinitely.
      final nowUtc = DateTime.now().toUtc();
      final bookingsRes = await supabase
          .from('bookings')
          .select('start_date, end_date, status, hold_expires_at')
          .eq('property_id', widget.propertyId)
          .inFilter('status', ['confirmed', 'completed', 'pending']);

      List<DateTime> tempDates = [];
      for (var b in bookingsRes) {
        if (b['status'] == 'pending') {
          final raw = b['hold_expires_at'];
          final holdUntil =
              raw == null ? null : DateTime.tryParse(raw.toString())?.toUtc();
          if (holdUntil == null || !holdUntil.isAfter(nowUtc)) {
            continue; // hold has lapsed — these dates are free again
          }
        }
        final start = DateTime.parse(b['start_date']);
        final end   = DateTime.parse(b['end_date']);
        for (int i = 0; i <= end.difference(start).inDays; i++) {
          tempDates.add(DateTime(start.year, start.month, start.day).add(Duration(days: i)));
        }
      }
      bookedDates = tempDates;

      // Ratings: average + count
      await _fetchRatings();

      setState(() => loading = false);
    } catch (e) {
      print("Error fetchExtraDetails: $e");
      setState(() => loading = false);
    }
  }

  Future<void> _fetchRatings() async {
    try {
      final ratingsRes = await supabase
          .from('ratings')
          .select('rating')
          .eq('property_id', widget.propertyId);

      if (ratingsRes.isNotEmpty) {
        final sum = (ratingsRes as List)
            .fold<double>(0, (acc, r) => acc + (r['rating'] as num).toDouble());
        averageRating = sum / ratingsRes.length;
        totalRatings  = ratingsRes.length;
      } else {
        averageRating = 0.0;
        totalRatings  = 0;
      }

      // A traveller may rate once their stay has begun, and from then on
      // forever — previously the window closed at checkout, which is exactly
      // when most people write reviews.
      final user = supabase.auth.currentUser;
      if (user != null) {
        final today = DateTime.now();
        final todayStr = DateFormat('yyyy-MM-dd').format(today);

        final eligibleRes = await supabase
            .from('bookings')
            .select('id, start_date, end_date')
            .eq('property_id', widget.propertyId)
            .eq('traveller_id', user.id)
            .inFilter('status', ['confirmed', 'completed'])
            .lte('start_date', todayStr)
            .order('start_date', ascending: false)
            .limit(1)
            .maybeSingle();

        eligibleBookingId = eligibleRes?['id'];

        // Check if already rated this booking
        if (eligibleBookingId != null) {
          final existingRating = await supabase
              .from('ratings')
              .select('rating')
              .eq('booking_id', eligibleBookingId!)
              .maybeSingle();

          myExistingRating = existingRating != null
              ? (existingRating['rating'] as num).toDouble()
              : null;
        } else {
          myExistingRating = null;
        }
      }
    } catch (e) {
      print("Rating fetch error: $e");
    }
  }

  Future<void> _submitRating(double selectedRating) async {
    setState(() => ratingLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null || eligibleBookingId == null) return;

      await supabase.from('ratings').upsert({
        'property_id':  widget.propertyId,
        'traveller_id': user.id,
        'booking_id':   eligibleBookingId,
        'rating':       selectedRating,
      }, onConflict: 'booking_id');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Thanks for rating ${selectedRating.toStringAsFixed(1)} ⭐"),
          backgroundColor: AppColors.darkTeal,
        ),
      );

      await _fetchRatings();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error submitting rating: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => ratingLoading = false);
    }
  }

  void _showRatingDialog() {
    double selectedRating = myExistingRating ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                myExistingRating != null ? "Update Your Rating" : "Rate this Stay",
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkTeal),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.roomName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final starValue = (i + 1).toDouble();
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedRating = starValue),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            selectedRating >= starValue
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 44,
                            color: selectedRating >= starValue
                                ? const Color(0xFFFFB800)
                                : Colors.grey.shade400,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    selectedRating == 0
                        ? "Tap a star to rate"
                        : "${selectedRating.toStringAsFixed(0)} / 5 Stars",
                    style: const TextStyle(color: AppColors.darkTeal, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  onPressed: selectedRating == 0
                      ? null
                      : () {
                          Navigator.pop(context);
                          _submitRating(selectedRating);
                        },
                  child: const Text("Submit", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool isDateBooked(DateTime day) {
    final n = DateTime(day.year, day.month, day.day);
    return bookedDates.any((b) => b.year == n.year && b.month == n.month && b.day == n.day);
  }

  void showReservationSheet() {
    DateTime? rangeStart;
    DateTime? rangeEnd;
    DateTime focusedDay = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            int numOfDays = 0;
            if (rangeStart != null && rangeEnd != null) {
              numOfDays = rangeEnd!.difference(rangeStart!).inDays + 1;
            } else if (rangeStart != null) {
              numOfDays = 1;
            }
            double totalRent = numOfDays * effectivePrice;

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                height: MediaQuery.of(context).size.height * 0.85,
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Select Stays",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkTeal),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        child: TableCalendar(
                          firstDay: DateTime.now(),
                          lastDay: DateTime.now().add(const Duration(days: 365)),
                          focusedDay: focusedDay,
                          rangeStartDay: rangeStart,
                          rangeEndDay: rangeEnd,
                          rangeSelectionMode: RangeSelectionMode.toggledOn,
                          enabledDayPredicate: (day) => !isDateBooked(day),
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal),
                            leftChevronIcon: Icon(Icons.chevron_left, color: AppColors.darkTeal),
                            rightChevronIcon: Icon(Icons.chevron_right, color: AppColors.darkTeal),
                          ),
                          onDaySelected: (selectedDay, fDay) {
                            if (isDateBooked(selectedDay)) return;
                            setSheetState(() {
                              focusedDay = fDay;
                              rangeStart = selectedDay;
                              rangeEnd = null;
                            });
                          },
                          onRangeSelected: (start, end, fDay) {
                            if (start != null && end != null) {
                              for (int i = 0; i <= end.difference(start).inDays; i++) {
                                if (isDateBooked(start.add(Duration(days: i)))) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Selected range includes already booked dates!")),
                                  );
                                  return;
                                }
                              }
                            }
                            setSheetState(() {
                              focusedDay = fDay;
                              rangeStart = start;
                              rangeEnd   = end;
                            });
                          },
                          calendarStyle: CalendarStyle(
                            disabledTextStyle: const TextStyle(
                                color: Colors.grey, decoration: TextDecoration.lineThrough),
                            rangeHighlightColor: AppColors.lightTeal.withOpacity(0.15),
                            withinRangeTextStyle: const TextStyle(color: AppColors.darkTeal, fontWeight: FontWeight.bold),
                            rangeStartDecoration: const BoxDecoration(
                                color: AppColors.darkTeal, shape: BoxShape.circle),
                            rangeEndDecoration: const BoxDecoration(
                                color: AppColors.darkTeal, shape: BoxShape.circle),
                            todayDecoration: BoxDecoration(
                                color: AppColors.lightTeal.withOpacity(0.3),
                                shape: BoxShape.circle),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Price per night:", style: TextStyle(fontSize: 16, color: Colors.black54)),
                        Row(
                          children: [
                            if (hasDiscount) ...[
                              Text(
                                "PKR ${widget.price.toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black38,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text("PKR ${effectivePrice.toStringAsFixed(0)}",
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                          ],
                        ),
                      ],
                    ),
                    if (hasDiscount) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Host discount (${discountPercent.toStringAsFixed(0)}%)",
                            style: TextStyle(fontSize: 13, color: Colors.green.shade700),
                          ),
                          Text(
                            "− PKR ${((widget.price - effectivePrice) * numOfDays).toStringAsFixed(0)}",
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Total ($numOfDays nights):",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                        Text("PKR ${totalRent.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkTeal)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    GradientButton(
                      text: "Confirm Booking",
                      onPressed: rangeStart == null
                        ? null
                        : () => confirmBooking(rangeStart!, rangeEnd ?? rangeStart!, totalRent),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Creates the booking through `create_booking`, a single database
  /// transaction that re-checks availability under a row lock and writes both
  /// notifications. Doing this client-side allowed two travellers to book the
  /// same dates and could leave a booking with no notifications attached.
  Future<void> confirmBooking(DateTime start, DateTime end, double totalRent) async {
    Navigator.pop(context);
    setState(() => loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception("Please login as a traveller to book.");

      await supabase.rpc('create_booking', params: {
        'p_property_id': widget.propertyId,
        'p_start_date': DateFormat('yyyy-MM-dd').format(start),
        'p_end_date': DateFormat('yyyy-MM-dd').format(end),
        'p_total_price': totalRent,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Booking Request Sent to Host!"),
            backgroundColor: AppColors.darkTeal),
      );
      await fetchExtraDetails();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // The function raises a friendly message when the dates were taken
      // between the calendar loading and the button being pressed.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
      await fetchExtraDetails();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to book: $e"), backgroundColor: Colors.red),
      );
      setState(() => loading = false);
    }
  }

  Future<void> openChat() async {
    setState(() => loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception("Please login first.");
      if (user.id == widget.hostId) throw Exception("You cannot message yourself.");

      final response = await supabase
          .from('chats')
          .select()
          .or('and(user1_id.eq.${user.id},user2_id.eq.${widget.hostId}),and(user1_id.eq.${widget.hostId},user2_id.eq.${user.id})')
          .maybeSingle();

      String chatId;
      if (response != null) {
        chatId = response['id'];
      } else {
        final ins = await supabase.from('chats').insert({
          'user1_id': user.id,
          'user2_id': widget.hostId,
        }).select().single();
        chatId = ins['id'];
      }

      setState(() => loading = false);
      Navigator.push(
        context,
        CustomPageRoute(
          child: ChatScreen(
              chatId: chatId, receiverId: widget.hostId, receiverName: hostName),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
      setState(() => loading = false);
    }
  }

  // ── Widgets ──────────────────────────────────────────────────

  Widget _detailCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.darkTeal, AppColors.lightTeal],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
               const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildQuickStat(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.darkTeal.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.darkTeal, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceBadge() {
    Color badgeColor;
    IconData prefIcon;
    String label;

    switch (guestPreference) {
      case 'Family':
        badgeColor = Colors.blue.shade700;
        prefIcon = Icons.family_restroom_rounded;
        label = "Family Only";
        break;
      case 'Female Only':
        badgeColor = Colors.pink.shade600;
        prefIcon = Icons.female_rounded;
        label = "Female Only";
        break;
      case 'Bachelors':
        badgeColor = Colors.orange.shade800;
        prefIcon = Icons.male_rounded;
        label = "Bachelors Only";
        break;
      default:
        badgeColor = AppColors.darkTeal;
        prefIcon = Icons.group_rounded;
        label = "Open to All Guests";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: badgeColor.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(prefIcon, size: 16, color: badgeColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostSection() {
    return _detailCard(
      icon: Icons.person_outline_rounded,
      title: "Presented By",
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            CustomPageRoute(child: HostPublicProfilePage(hostId: widget.hostId)),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: AppColors.primaryGradient),
                ),
                child: const CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, color: AppColors.darkTeal, size: 30),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hostName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined, size: 13, color: Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          hostPhone,
                          style: const TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.darkTeal),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingSection() {
    return _detailCard(
      icon: Icons.star_rounded,
      title: "Guest Experience",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        averageRating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkTeal,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        "/5",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black38,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: List.generate(5, (i) {
                      final filled = averageRating >= (i + 1);
                      final half = !filled && averageRating > i;
                      return Icon(
                        half ? Icons.star_half_rounded : Icons.star_rounded,
                        color: (filled || half) ? const Color(0xFFFFB800) : Colors.grey.shade200,
                        size: 20,
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    totalRatings == 0 ? "No ratings yet" : "Based on $totalRatings reviews",
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      totalRatings > 0 ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                      color: AppColors.lightTeal,
                      size: 28,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalRatings > 0 ? "Highly Rated" : "Fresh Listing",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkTeal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (eligibleBookingId != null) ...[
            const SizedBox(height: 20),
            GradientButton(
              height: 45,
              text: myExistingRating != null
                  ? "Update Rating (${myExistingRating!.toStringAsFixed(1)})"
                  : "Rate This Stay",
              onPressed: _showRatingDialog,
              loading: ratingLoading,
              icon: Icons.star_outline_rounded,
            ),
          ] else ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: Colors.black38),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    "You can submit a rating once your stay begins.",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black38,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: GradientButton(
                  text: "Reserve This Stay",
                  onPressed: showReservationSheet,
                ),
              ),
              const SizedBox(width: 16),
              Container(
                height: 52,
                width: 56,
                decoration: BoxDecoration(
                  color: AppColors.darkTeal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.darkTeal, size: 24),
                  onPressed: openChat,
                ),
              ),
            ],
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.darkTeal))
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 350,
                  pinned: true,
                  stretch: true,
                  backgroundColor: AppColors.darkTeal,
                  leading: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircleAvatar(
                      backgroundColor: Colors.white.withOpacity(0.9),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.darkTeal, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() => _currentImageIndex = index);
                          },
                          itemCount: widget.images.length,
                          itemBuilder: (context, index) => Image.network(
                            widget.images[index],
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Indicator (Dots in capsule)
                        if (widget.images.length > 1)
                          Positioned(
                            bottom: 20,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(
                                    widget.images.length,
                                    (index) => AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      height: 6,
                                      width: _currentImageIndex == index ? 18 : 6,
                                      decoration: BoxDecoration(
                                        color: _currentImageIndex == index
                                            ? Colors.white
                                            : Colors.white.withOpacity(0.4),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black54, Colors.transparent],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Property Type Badge & Guest Preference Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.darkTeal.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _typeIcons[propertyType] ?? Icons.home_rounded,
                                    size: 14,
                                    color: AppColors.darkTeal,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    propertyType,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.darkTeal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildPreferenceBadge(),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Title & Price Header
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.roomName,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined, size: 16, color: AppColors.lightTeal),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          widget.location,
                                          style: const TextStyle(color: Colors.black54, fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (hasDiscount)
                                  Text(
                                    "PKR ${widget.price.toStringAsFixed(0)}",
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black38,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                Text(
                                  "PKR ${effectivePrice.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkTeal,
                                  ),
                                ),
                                const Text("/ night", style: TextStyle(color: Colors.black38, fontSize: 12)),
                                if (hasDiscount)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "${discountPercent.toStringAsFixed(0)}% OFF",
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Quick stats horizontal row
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildQuickStat(Icons.king_bed_outlined, "$bedrooms", "Bedrooms"),
                              const SizedBox(width: 12),
                              _buildQuickStat(Icons.bathtub_outlined, "$bathrooms", "Bathrooms"),
                              const SizedBox(width: 12),
                              _buildQuickStat(Icons.people_outline_rounded, "$maxGuests", "Max Guests"),
                              const SizedBox(width: 12),
                              _buildQuickStat(_typeIcons[propertyType] ?? Icons.home_work_outlined, propertyType, "Type"),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Section 1: Guest Experience
                        _buildRatingSection(),

                        // Section 2: Presented by Host
                        _buildHostSection(),

                        // Section 3: Facilities
                        _detailCard(
                          icon: Icons.wifi_rounded,
                          title: "Amenities & Facilities",
                          child: Text(
                            facilities,
                            style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
                          ),
                        ),

                        // Section 4: Description
                        _detailCard(
                          icon: Icons.notes_rounded,
                          title: "About this Stay",
                          child: Text(
                            description,
                            style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}