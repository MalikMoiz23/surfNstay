import 'package:flutter/material.dart';
import 'AddPropertyScreen.dart';
import 'EditPropertyScreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'NotificationScreen.dart';
import 'package:badges/badges.dart' as badges;
import 'messages_page.dart';
import 'app_theme.dart';
import 'page_transition.dart';
import 'package:intl/intl.dart';
import 'host_profile_page.dart';
import 'animations.dart';
import 'manage_availability_page.dart';

class HostDashboard extends StatefulWidget {
  const HostDashboard({super.key});

  @override
  State<HostDashboard> createState() => _HostDashboardState();
}

class _HostDashboardState extends State<HostDashboard>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> properties = [];
  bool loading = true;
  int _selectedIndex = 0;

  String hostName = "Loading...";
  String? profileImage;
  String? verificationStatus;

  // Stats
  int totalBookings = 0;
  double totalEarnings = 0;

  static const Color darkTeal = Color(0xFF0F4C5C);
  static const Color lightTeal = Color(0xFF26C6DA);
  static const Color bg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1E293B);
  static const Color textLight = Color(0xFF64748B);

  late final Stream<List<Map<String, dynamic>>> _notificationsStream;
  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  late AnimationController _fabController;
  late Animation<double> _fabScale;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fabScale = CurvedAnimation(parent: _fabController, curve: Curves.elasticOut);

    final user = supabase.auth.currentUser;
    if (user != null) {
      _notificationsStream = supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id)
          .map((events) =>
              events.where((e) => e['is_read'] == false).toList());
      _messagesStream = supabase
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('receiver_id', user.id)
          .map((events) =>
              events.where((e) => e['is_read'] == false).toList());
    } else {
      _notificationsStream = const Stream.empty();
      _messagesStream = const Stream.empty();
    }
    fetchHostInfo();
    fetchProperties();
    fetchStats();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  Future<void> fetchHostInfo() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      try {
        final response = await supabase
            .from('hosts')
.select('fullName, profile_pic, verification_status')
            .eq('id', user.id)
            .maybeSingle();

        if (response != null) {
          setState(() {
            hostName = response['fullName'] ?? "Host";
            profileImage = response['profile_pic'];
            verificationStatus = response['verification_status']?.toString();
          });
          return;
        }
      } catch (e) {
        final response = await supabase
            .from('hosts')
            .select('fullName')
            .eq('id', user.id)
            .maybeSingle();

        if (response != null) {
          setState(() {
            hostName = response['fullName'] ?? "Host";
            profileImage = null;
          });
          return;
        }
      }

      setState(() => hostName = "Host");
    } catch (e) {
      print("Error fetching host info: $e");
      setState(() => hostName = "Host");
    }
  }

  Future<void> fetchStats() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Close out stays whose end date has passed before counting earnings.
      // Nothing used to move a booking to 'completed', so this figure counted
      // stays that had not happened yet as revenue.
      try {
        await supabase.rpc('refresh_booking_states');
      } catch (e) {
        debugPrint('refresh_booking_states unavailable: $e');
      }

      // Get all property IDs for this host
      final props = await supabase
          .from('properties')
          .select('id, price_per_night')
          .eq('host_id', user.id);

      final propIds = props.map((p) => p['id'].toString()).toList();
      if (propIds.isEmpty) return;

      // Get bookings for these properties
      final bookings = await supabase
          .from('bookings')
          .select('property_id, total_price, status')
          .inFilter('property_id', propIds.map((id) => int.tryParse(id) ?? id).toList());

      double earnings = 0;
      int completedBookings = 0;
      for (var b in bookings) {
        if (b['status'] == 'confirmed' || b['status'] == 'completed') {
          completedBookings++;
          if (b['total_price'] != null) {
            earnings += (b['total_price'] as num).toDouble();
          }
        }
      }

      setState(() {
        totalBookings = completedBookings;
        totalEarnings = earnings;
      });
    } catch (e) {
      print("Error fetching stats: $e");
    }
  }

  Future<void> fetchProperties() async {
    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('properties')
          .select()
          .eq('host_id', user.id)
          .order('created_at', ascending: false);

      properties = response.map<Map<String, dynamic>>((p) {
        List<String> imgs = [];
        if (p['image1_url'] != null && p['image1_url'] != "") {
          imgs.add(p['image1_url']);
        }
        if (p['image2_url'] != null && p['image2_url'] != "") {
          imgs.add(p['image2_url']);
        }
        if (p['image3_url'] != null && p['image3_url'] != "") {
          imgs.add(p['image3_url']);
        }

        return {
          "id": p['id'].toString(),
          "room_name": p['room_name'] ?? "Untitled listing",
          "images": imgs,
          "price_per_night": p['price_per_night'],
          "is_active": p['is_active'] ?? true,
          "facilities": p['facilities'] ?? "",
          "location": p['location'] ?? "",
          "description": p['description'] ?? "",
          "property_type": p['property_type'] ?? "Room",
          "guest_preference": p['guest_preference'] ?? "",
          "bedrooms": p['bedrooms'] ?? 1,
          "bathrooms": p['bathrooms'] ?? 1,
        };
      }).toList();

      setState(() => loading = false);
      _fabController.forward();
    } catch (e) {
      print("Error fetching properties: $e");
      setState(() => loading = false);
    }
  }

  void _onNavTapped(int index) {
    if (index == 1) {
      Navigator.pushReplacement(
        context,
        CustomPageRoute(child: const MessagesPage(isHost: true)),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        CustomPageRoute(child: const HostProfilePage()),
      );
    } else {
      setState(() => _selectedIndex = index);
    }
  }


  // ─────────────────────────────────────
  //  SKELETON  (replaces a blank spinner)
  // ─────────────────────────────────────
  Widget _buildSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      children: [
        const Shimmer(height: 108, radius: 24),
        const SizedBox(height: 18),
        Row(
          children: const [
            Expanded(child: Shimmer(height: 104, radius: 18)),
            SizedBox(width: 12),
            Expanded(child: Shimmer(height: 104, radius: 18)),
            SizedBox(width: 12),
            Expanded(child: Shimmer(height: 104, radius: 18)),
          ],
        ),
        const SizedBox(height: 28),
        const Shimmer(height: 22, width: 160, radius: 6),
        const SizedBox(height: 16),
        const Shimmer(height: 250, radius: 24),
        const SizedBox(height: 16),
        const Shimmer(height: 250, radius: 24),
      ],
    );
  }

  // ─────────────────────────────────────
  //  VERIFICATION STRIP
  //  Turns the CNIC flow into something the host is actually prompted to do,
  //  instead of an option buried in the profile tab.
  // ─────────────────────────────────────
  Widget _buildVerificationStrip() {
    final status = verificationStatus ?? 'unverified';
    if (status == 'verified') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF15803D).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFF15803D).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: const [
              Icon(Icons.verified_rounded, size: 18, color: Color(0xFF15803D)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Verified host — guests see a badge on your listings.',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF15803D)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pending = status == 'pending';
    final rejected = status == 'rejected';
    final accent = pending ? Colors.orange.shade800 : darkTeal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: PressableScale(
        onTap: pending
            ? null
            : () => Navigator.push(
                  context,
                  CustomPageRoute(child: const HostProfilePage()),
                ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  pending
                      ? Icons.hourglass_top_rounded
                      : rejected
                          ? Icons.gpp_bad_rounded
                          : Icons.badge_outlined,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending
                          ? 'Verification under review'
                          : rejected
                              ? 'Verification was rejected'
                              : 'Get verified to win more bookings',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: accent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pending
                          ? 'An admin is checking your CNIC.'
                          : 'Upload your CNIC once — guests see a Verified badge.',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              if (!pending)
                const Icon(Icons.chevron_right_rounded, color: textLight),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: loading
            ? _buildSkeleton()
            : RefreshIndicator(
                color: darkTeal,
                onRefresh: () async {
                  await fetchHostInfo();
                  await fetchProperties();
                  await fetchStats();
                },
                child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                slivers: [
                  // ── Hero Header ──
                  SliverToBoxAdapter(
                      child: FadeSlideIn(index: 0, child: _buildHeader())),
                  // ── Verification prompt ──
                  SliverToBoxAdapter(
                      child: FadeSlideIn(index: 1, child: _buildVerificationStrip())),
                  // ── Stats Row ──
                  SliverToBoxAdapter(
                      child: FadeSlideIn(index: 2, child: _buildStatsRow())),
                  // ── Section Title ──
                  SliverToBoxAdapter(
                    child: FadeSlideIn(index: 3, child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 22,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [darkTeal, lightTeal],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            "Your Properties",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textDark,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: lightTeal.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "${properties.length} listed",
                              style: const TextStyle(
                                color: darkTeal,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                  ),
                  // ── Properties List ──
                  properties.isEmpty
                      ? SliverFillRemaining(
                          child: _buildEmptyState(),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => FadeSlideIn(
                                index: index + 4,
                                child: _buildPropertyCard(properties[index]),
                              ),
                              childCount: properties.length,
                            ),
                          ),
                        ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 90)),
                ],
              ),
              ),
      ),
      floatingActionButton: properties.isNotEmpty
          ? ScaleTransition(
              scale: _fabScale,
              child: FloatingActionButton.extended(
                onPressed: () {
                  Navigator.push(
                    context,
                    CustomPageRoute(child: const AddPropertyScreen()),
                  ).then((_) {
                    fetchProperties();
                    fetchStats();
                  });
                },
                backgroundColor: darkTeal,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: const Text(
                  "Add Property",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                elevation: 6,
              ),
            )
          : null,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ─────────────────────────────────────
  //  HERO HEADER
  // ─────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [darkTeal, Color(0xFF1A6B7A), lightTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: darkTeal.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Profile avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white.withOpacity(0.2),
              backgroundImage:
                  (profileImage != null && profileImage!.isNotEmpty)
                      ? NetworkImage(profileImage!)
                      : null,
              child: (profileImage == null || profileImage!.isEmpty)
                  ? const Icon(Icons.person, color: Colors.white, size: 32)
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          // Welcome text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome back,",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hostName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "Manage your properties",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
          // Notification bell
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _notificationsStream,
            builder: (context, notifSnapshot) {
              bool hasNotif =
                  notifSnapshot.hasData && notifSnapshot.data!.isNotEmpty;
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _messagesStream,
                builder: (context, msgSnapshot) {
                  bool hasMsg =
                      msgSnapshot.hasData && msgSnapshot.data!.isNotEmpty;
                  bool hasUnread = hasNotif || hasMsg;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: badges.Badge(
                      showBadge: hasUnread,
                      badgeStyle: const badges.BadgeStyle(
                        badgeColor: Color(0xFFFF6B6B),
                        padding: EdgeInsets.all(5),
                      ),
                      position:
                          badges.BadgePosition.topEnd(top: 2, end: 2),
                      child: IconButton(
                        icon: const Icon(Icons.notifications_outlined,
                            color: Colors.white, size: 26),
                        onPressed: () {
                          Navigator.push(
                            context,
                            CustomPageRoute(
                                child: const NotificationScreen()),
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────
  //  STATS ROW
  // ─────────────────────────────────────
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Row(
        children: [
          _buildStatCard(
            icon: Icons.home_work_rounded,
            label: "Properties",
            count: properties.length,
            color: const Color(0xFF6C63FF),
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            icon: Icons.calendar_today_rounded,
            label: "Bookings",
            count: totalBookings,
            color: const Color(0xFFFF8A65),
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            icon: Icons.account_balance_wallet_rounded,
            label: "Earnings",
            count: totalEarnings,
            format: _formatEarnings,
            color: const Color(0xFF4CAF50),
          ),
        ],
      ),
    );
  }

  String _formatEarnings(double amount) {
    if (amount >= 1000000) {
      return "PKR ${(amount / 1000000).toStringAsFixed(1)}M";
    } else if (amount >= 1000) {
      return "PKR ${(amount / 1000).toStringAsFixed(1)}K";
    }
    return "PKR ${amount.toStringAsFixed(0)}";
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required num count,
    required Color color,
    String Function(double)? format,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            AnimatedCount(
              value: count,
              format: format == null
                  ? null
                  : (v) => format(v.toDouble()),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: textLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────
  //  EMPTY STATE
  // ─────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: lightTeal.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add_home_work_rounded,
              size: 64,
              color: darkTeal,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "No properties yet",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Start earning by listing your first\nproperty on SurfNStay",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: textLight,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 220,
            child: GradientButton(
              text: "Add Property",
              icon: Icons.add_rounded,
              onPressed: () {
                Navigator.push(
                  context,
                  CustomPageRoute(child: const AddPropertyScreen()),
                ).then((_) {
                  fetchProperties();
                  fetchStats();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────
  //  PROPERTY CARD
  // ─────────────────────────────────────
  Widget _buildPropertyCard(Map<String, dynamic> prop) {
    List images = prop["images"];
    String propertyId = prop["id"];
    final priceValue = prop["price_per_night"];
    String price = priceValue != null
        ? "PKR ${NumberFormat('#,###').format(priceValue)}"
        : "N/A";
    String propertyType = prop["property_type"] ?? "Room";
    String guestPref = prop["guest_preference"] ?? "";
    int bedrooms = prop["bedrooms"] ?? 1;
    int bathrooms = prop["bathrooms"] ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: darkTeal.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image Carousel ──
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
            child: SizedBox(
              height: 180,
              child: images.isEmpty
                  ? Container(
                      color: Colors.grey.shade100,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image_outlined,
                                size: 48, color: textLight),
                            SizedBox(height: 8),
                            Text("No images added",
                                style: TextStyle(
                                    color: textLight, fontSize: 13)),
                          ],
                        ),
                      ),
                    )
                  : _ImageCarousel(images: images.cast<String>()),
            ),
          ),
          // ── Card Content ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Type badge + price
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [darkTeal, lightTeal],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        propertyType,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (guestPref.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          guestPref,
                          style: const TextStyle(
                            color: Color(0xFFE65100),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: darkTeal,
                      ),
                    ),
                    const Text(
                      " / night",
                      style: TextStyle(
                        fontSize: 12,
                        color: textLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Location
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 16, color: lightTeal),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        prop["location"],
                        style: const TextStyle(
                          fontSize: 14,
                          color: textDark,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Amenities row
                Row(
                  children: [
                    _infoChip(Icons.bed_rounded, "$bedrooms Bed"),
                    const SizedBox(width: 12),
                    _infoChip(Icons.bathtub_outlined, "$bathrooms Bath"),
                    if (prop["facilities"].toString().isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          prop["facilities"],
                          style: const TextStyle(
                              fontSize: 12, color: textLight),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                // Availability — hosts previously had no way to close dates.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        CustomPageRoute(
                          child: ManageAvailabilityPage(
                            propertyId: propertyId,
                            propertyName:
                                prop['room_name']?.toString() ?? 'Your listing',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.event_available_rounded,
                        size: 18, color: lightTeal),
                    label: const Text(
                      "Manage availability",
                      style: TextStyle(
                          color: darkTeal, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: lightTeal, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            CustomPageRoute(
                              child: EditPropertyScreen(
                                  propertyId: propertyId),
                            ),
                          ).then((_) {
                            fetchProperties();
                            fetchStats();
                          });
                        },
                        icon: const Icon(Icons.edit_rounded,
                            size: 18, color: darkTeal),
                        label: const Text(
                          "Edit",
                          style: TextStyle(
                            color: darkTeal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: darkTeal, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _safeDeleteProperty(propertyId),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18, color: Color(0xFFFF6B6B)),
                        label: const Text(
                          "Delete",
                          style: TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: Color(0xFFFF6B6B), width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: lightTeal),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: textDark,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────
  //  DELETE PROPERTY
  // ─────────────────────────────────────
  Future<void> _safeDeleteProperty(String propertyId) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final bookings = await supabase
          .from('bookings')
          .select('id')
          .eq('property_id', propertyId)
          .gte('end_date', today)
          .neq('status', 'cancelled');

      if (bookings.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Cannot delete! This property has active or future bookings.",
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFFF6B6B)),
                ),
                const SizedBox(width: 12),
                const Text("Delete Property?"),
              ],
            ),
            content: const Text(
              "Are you sure you want to remove this property? This action cannot be undone.",
              style: TextStyle(color: textLight, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text("Cancel", style: TextStyle(color: textLight)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  setState(() => loading = true);
                  await supabase
                      .from('properties')
                      .delete()
                      .eq('id', propertyId);
                  await fetchProperties();
                  await fetchStats();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B6B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("Delete",
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error checking bookings: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────
  //  BOTTOM NAV
  // ─────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.white,
        unselectedItemColor: textLight,
        showUnselectedLabels: true,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: [
          _navItem(Icons.home_rounded, "Home", 0),
          _navItem(Icons.message_outlined, "Messages", 1),
          _navItem(Icons.person_outline, "Profile", 2),
        ],
      ),
    );
  }

  BottomNavigationBarItem _navItem(
      IconData icon, String label, int index) {
    final bool isSelected = _selectedIndex == index;
    return BottomNavigationBarItem(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: isSelected
            ? BoxDecoration(
                gradient: const LinearGradient(
                  colors: [darkTeal, lightTeal],
                ),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Icon(
          icon,
          color: isSelected ? Colors.white : textLight,
        ),
      ),
      label: label,
    );
  }
}

// ─────────────────────────────────────
//  IMAGE CAROUSEL (internal widget)
// ─────────────────────────────────────
class _ImageCarousel extends StatefulWidget {
  final List<String> images;
  const _ImageCarousel({required this.images});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _currentPage = 0;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _currentPage = i),
          itemBuilder: (context, i) {
            return Image.network(
              widget.images[i],
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey.shade100,
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded,
                        size: 48, color: Color(0xFF64748B)),
                  ),
                );
              },
            );
          },
        ),
        // Dot indicators
        if (widget.images.length > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.images.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == i ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == i
                        ? Colors.white
                        : Colors.white.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: _currentPage == i
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                            ),
                          ]
                        : [],
                  ),
                ),
              ),
            ),
          ),
        // Image counter
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "${_currentPage + 1}/${widget.images.length}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}