import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'ChatScreen.dart';
import 'app_theme.dart';
import 'page_transition.dart';
import 'host_public_profile.dart'; // ✅ added

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

  bool loading = true;

  String facilities  = "No facilities provided";
  String description = "No description provided";
  String hostName    = "Unknown Host";
  String hostPhone   = "N/A";

  List<DateTime> bookedDates = [];

  // Rating state
  double averageRating   = 0.0;
  int    totalRatings    = 0;
  double? myExistingRating;  // null if not yet rated
  String? eligibleBookingId; // booking id that qualifies for rating today
  bool   ratingLoading   = false;

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
        facilities  = propRes['facilities']?.toString()  ?? "No facilities provided";
        description = propRes['description']?.toString() ?? "No description provided";
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

      // Booked dates for calendar
      final bookingsRes = await supabase
          .from('bookings')
          .select('start_date, end_date')
          .eq('property_id', widget.propertyId)
          .neq('status', 'cancelled');

      List<DateTime> tempDates = [];
      for (var b in bookingsRes) {
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

      // Check if current traveller has a booking that covers today
      final user = supabase.auth.currentUser;
      if (user != null) {
        final today = DateTime.now();
        final todayStr = DateFormat('yyyy-MM-dd').format(today);

        // Booking that covers today (start_date <= today <= end_date)
        final eligibleRes = await supabase
            .from('bookings')
            .select('id, start_date, end_date')
            .eq('property_id', widget.propertyId)
            .eq('traveller_id', user.id)
            .lte('start_date', todayStr)
            .gte('end_date', todayStr)
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                myExistingRating != null ? "Update Your Rating" : "Rate this Room",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.roomName,
                      style: const TextStyle(color: Colors.black54)),
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
                            size: 40,
                            color: selectedRating >= starValue
                                ? const Color(0xFFFFB800)
                                : Colors.grey,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    selectedRating == 0
                        ? "Tap a star to rate"
                        : "${selectedRating.toStringAsFixed(0)} / 5 Stars",
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: selectedRating == 0
                      ? null
                      : () {
                          Navigator.pop(context);
                          _submitRating(selectedRating);
                        },
                  child: const Text("Submit", style: TextStyle(color: Colors.white)),
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
            double totalRent = numOfDays * widget.price;

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
                    const Text("Select Stays",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                            titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                        Text("PKR ${widget.price.toStringAsFixed(0)}",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Total ($numOfDays nights):",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text("PKR ${totalRent.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontSize: 22,
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

  Future<void> confirmBooking(DateTime start, DateTime end, double totalRent) async {
    Navigator.pop(context);
    setState(() => loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception("Please login as a traveller to book.");

      // Fetch Traveller Name
      final travellerData = await supabase
          .from('travellers')
          .select('name')
          .eq('id', user.id)
          .single();
      final String travellerName = travellerData['name'] ?? "A traveller";

      final bookingResponse = await supabase.from('bookings').insert({
        'property_id':  widget.propertyId,
        'traveller_id': user.id,
        'start_date':   start.toIso8601String().split('T')[0],
        'end_date':     end.toIso8601String().split('T')[0],
        'total_price':  totalRent,
        'status':       'pending', // ✅ Default to pending
      }).select('id').single();

      final String bookingId = bookingResponse['id'];

      final startStr = DateFormat('MMM d, yyyy').format(start);
      final endStr   = DateFormat('MMM d, yyyy').format(end);

      // Notification for Traveller
      await supabase.from('notifications').insert({
        'user_id': user.id,
        'booking_id': bookingId,
        'category': 'booking_info',
        'message':
            'Your booking request for ${widget.roomName} from $startStr to $endStr has been sent to the host!',
      });

      // Notification for Host
      await supabase.from('notifications').insert({
        'user_id': widget.hostId,
        'booking_id': bookingId,
        'category': 'booking_request', // ✅ Mark as actionable
        'message':
            '$travellerName has requested to book ${widget.roomName} from $startStr to $endStr.',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Booking Request Sent to Host!"),
            backgroundColor: AppColors.darkTeal),
      );
      await fetchExtraDetails();
    } catch (e) {
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

  Widget sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 24),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.darkTeal,
        ),
      ),
    );
  }

  Widget infoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget hostCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          CustomPageRoute(child: HostPublicProfilePage(hostId: widget.hostId)),
        );
      },
      child: infoCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: AppColors.primaryGradient),
              ),
              child: const CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: AppColors.darkTeal, size: 35),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(hostName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text(
                        "View Profile",
                        style: TextStyle(
                          color: AppColors.darkTeal,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: Colors.black54),
                      const SizedBox(width: 4),
                      Text(hostPhone, style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget ratingSection() {
    return infoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Guest Experience",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (totalRatings > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lightTeal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 18),
                      const SizedBox(width: 4),
                      Text(
                        averageRating.toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkTeal),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ...List.generate(5, (i) {
                final filled = averageRating >= (i + 1);
                final half   = !filled && averageRating > i;
                return Icon(
                  half ? Icons.star_half_rounded : Icons.star_rounded,
                  color: (filled || half)
                      ? const Color(0xFFFFB800)
                      : Colors.grey.shade200,
                  size: 28,
                );
              }),
              const SizedBox(width: 12),
              Text(
                totalRatings == 0
                    ? "No ratings yet"
                    : "($totalRatings Reviews)",
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ],
          ),
          if (eligibleBookingId != null) ...[
            const SizedBox(height: 20),
            GradientButton(
              height: 45,
              text: myExistingRating != null ? "Update Rating (${myExistingRating!.toStringAsFixed(1)})" : "Rate This Stay",
              onPressed: _showRatingDialog,
              loading: ratingLoading,
              icon: Icons.star_outline_rounded,
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Text(
              "Ratings will be available on your check-in day.",
              style: TextStyle(fontSize: 12, color: Colors.black38, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: GradientButton(
                  text: "Reserve This Stay",
                  onPressed: showReservationSheet,
                ),
              ),
              const SizedBox(width: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.darkTeal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.darkTeal),
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
                  leading: const BackButton(color: Colors.white),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          itemCount: widget.images.length,
                          itemBuilder: (context, index) => Image.network(
                            widget.images[index],
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Indicator or Gradient overlay
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black54, Colors.transparent],
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
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined, size: 16, color: AppColors.lightTeal),
                                      const SizedBox(width: 4),
                                      Text(widget.location, style: const TextStyle(color: Colors.black54)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "PKR ${widget.price.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkTeal,
                                  ),
                                ),
                                const Text("/ night", style: TextStyle(color: Colors.black38, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),
                        const Divider(height: 40),

                        // Section 1: Rating
                        ratingSection(),

                        // Section 2: Host
                        sectionHeader("Presented by"),
                        hostCard(),

                        // Section 3: Facilities
                        sectionHeader("Amenities & Facilities"),
                        infoCard(
                          child: Text(
                            facilities,
                            style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
                          ),
                        ),

                        // Section 4: Description
                        sectionHeader("About this stay"),
                        infoCard(
                          child: Text(
                            description,
                            style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
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