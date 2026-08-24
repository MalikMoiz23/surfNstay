import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'animations.dart';
import 'formatting.dart';
import 'search_filters.dart';
import 'wishlist_page.dart';
import 'my_trips_page.dart';
import 'profile_page.dart';
import 'messages_page.dart';
import 'ai_chatbot_page.dart';
import 'RoomDetailPage.dart';
import 'NotificationScreen.dart';
import 'package:badges/badges.dart' as badges;
import 'wishlist_service.dart';
import 'app_theme.dart';
import 'page_transition.dart';

class TravellerDashboard extends StatefulWidget {
  const TravellerDashboard({super.key});

  @override
  State<TravellerDashboard> createState() => _TravellerDashboardState();
}

class _TravellerDashboardState extends State<TravellerDashboard> {
  final supabase = Supabase.instance.client;
  int _selectedIndex = 0;
  bool loading = true;
  List<Map<String, dynamic>> rooms = [];

  static const Color bg = Color(0xFFF8FAFC); // Pop white cards on soft light background
  static const Color textLight = Color(0xFF64748B);

  String _searchQuery = "";
  String _selectedCategory = "All"; // All, Rooms, Apartments, Houses, Villas
  final TextEditingController _searchCtrl = TextEditingController();

  /// All filtering now happens in Postgres via search_properties. This holds
  /// the criteria; `rooms` holds whatever the server sent back.
  final SearchFilters _filters = SearchFilters();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Typing fires a query per keystroke otherwise.
  void _onQueryChanged(String value) {
    setState(() => _searchQuery = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _filters.query = value;
      _search();
    });
  }

  Future<void> _openFilters() async {
    final applied = await SearchFilterSheet.show(context, _filters);
    if (applied == null || !mounted) return;
    setState(() {
      _filters
        ..city = applied.city
        ..propertyType = applied.propertyType
        ..minPrice = applied.minPrice
        ..maxPrice = applied.maxPrice
        ..guests = applied.guests
        ..startDate = applied.startDate
        ..endDate = applied.endDate
        ..amenities = applied.amenities
        ..sort = applied.sort
        ..radiusKm = applied.radiusKm
        ..latitude = applied.latitude
        ..longitude = applied.longitude;

      // Keep the category strip in sync with the sheet.
      _selectedCategory = switch (applied.propertyType) {
        'Room' => 'Rooms',
        'Apartment' => 'Apartments',
        'House' => 'Houses',
        'Villa' => 'Villas',
        _ => 'All',
      };
    });
    await _search();
  }

  late final Stream<List<Map<String, dynamic>>> _notificationsStream;
  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  @override
  void initState() {
    super.initState();
    final user = supabase.auth.currentUser;
    if (user != null) {
      _notificationsStream = supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id)
          .map((events) => events.where((e) => e['is_read'] == false).toList());
      _messagesStream = supabase
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('receiver_id', user.id)
          .map((events) => events.where((e) => e['is_read'] == false).toList());
    } else {
      _notificationsStream = const Stream.empty();
      _messagesStream = const Stream.empty();
    }
    _search();
  }

  /// One round trip. Text, city, type, price band, guest count, date
  /// availability, amenities, radius and sort order are all applied in
  /// Postgres — previously the app pulled every property plus every rating
  /// row and filtered two fields in Dart.
  Future<void> _search() async {
    if (mounted) setState(() => loading = true);

    try {
      // Retire lapsed holds and close out finished stays so availability and
      // the host's earnings figure reflect reality.
      try {
        await supabase.rpc('refresh_booking_states');
      } catch (e) {
        debugPrint('refresh_booking_states unavailable: $e');
      }

      final response =
          await supabase.rpc('search_properties', params: _filters.toRpcParams());

      final list = List<Map<String, dynamic>>.from(response as List);

      rooms = list.map<Map<String, dynamic>>((p) {
        final imgs = <String>[
          for (final key in ['image1_url', 'image2_url', 'image3_url'])
            if (p[key] != null && p[key].toString().isNotEmpty)
              p[key].toString()
        ];

        return {
          "property_id": p['id'].toString(),
          "host_id": p['host_id'],
          "images": imgs,
          "price_per_night": (p['price_per_night'] as num?)?.toDouble() ?? 0,
          "effective_price": (p['effective_price'] as num?)?.toDouble() ?? 0,
          "discount": (p['discount'] as num?)?.toDouble() ?? 0,
          "location": p['location'] ?? "",
          "city": p['city'] ?? "",
          "roomName": p['room_name'] ?? "Room",
          "property_type": p['property_type'] ?? 'Room',
          "bedrooms": p['bedrooms'] ?? 1,
          "bathrooms": p['bathrooms'] ?? 1,
          "max_guests": p['max_guests'] ?? 1,
          "avg_rating": (p['avg_rating'] as num?)?.toDouble() ?? 0.0,
          "total_reviews": p['total_reviews'] ?? 0,
          "distance_km": (p['distance_km'] as num?)?.toDouble(),
          "amenities": List<String>.from(p['amenity_keys'] ?? const []),
          "host_verified": p['host_verified'] == true,
        };
      }).toList();

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      debugPrint("Error searching properties: $e");
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load stays: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Groups whatever the server returned by its own `city` value.
  ///
  /// This used to be five hardcoded city names plus an "Other Cities" bucket,
  /// matched by substring against the free-text address — so a listing in
  /// Multan or Skardu was permanently filed under "Other".
  ///
  /// When the results are sorted (price, rating, distance) grouping would
  /// scramble that order, so in those modes everything stays in one list.
  Map<String, List<Map<String, dynamic>>> groupRooms() {
    if (_filters.sort != 'recent') {
      return {'Results': List<Map<String, dynamic>>.from(rooms)};
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final room in rooms) {
      var city = (room['city'] ?? '').toString().trim();
      if (city.isEmpty) {
        city = (room['location'] ?? '').toString().split(',').first.trim();
      }
      if (city.isEmpty) city = 'Other';
      grouped.putIfAbsent(city, () => []).add(room);
    }

    // Busiest cities first, then alphabetically for a stable order.
    final ordered = grouped.keys.toList()
      ..sort((a, b) {
        final byCount = grouped[b]!.length.compareTo(grouped[a]!.length);
        return byCount != 0 ? byCount : a.compareTo(b);
      });

    return {for (final c in ordered) c: grouped[c]!};
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

    Navigator.pushReplacement(
      context,
      CustomPageRoute(child: page),
    );
  }

  BottomNavigationBarItem _bottomNavItem(
      IconData icon, String label, int index) {
    return BottomNavigationBarItem(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: _selectedIndex == index
            ? BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppColors.primaryGradient,
                ),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Icon(
          icon,
          color: _selectedIndex == index ? Colors.white : textLight,
        ),
      ),
      label: label,
    );
  }

  Widget _buildTopBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.darkTeal, AppColors.lightTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkTeal.withOpacity(0.18),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    "assets/logo.png",
                    height: 32,
                    color: Colors.white, // Render logo in white
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "SurfNStay",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                "Find a Perfect Stay 🌊",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Discover unique rooms, apartments, and villas.",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _notificationsStream,
              builder: (context, notifSnapshot) {
                bool hasNotif = notifSnapshot.hasData && notifSnapshot.data!.isNotEmpty;

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _messagesStream,
                  builder: (context, msgSnapshot) {
                    bool hasMsg = msgSnapshot.hasData && msgSnapshot.data!.isNotEmpty;
                    bool hasUnread = hasNotif || hasMsg;

                    return badges.Badge(
                      showBadge: hasUnread,
                      position: badges.BadgePosition.topEnd(top: 2, end: 4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.notifications_none_rounded, size: 24, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const NotificationScreen()),
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton() {
    final count = _filters.activeCount;
    return GestureDetector(
      onTap: _openFilters,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: count > 0
              ? const LinearGradient(colors: AppColors.primaryGradient)
              : null,
          color: count > 0 ? null : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: count > 0 ? Colors.transparent : Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded,
                size: 18, color: count > 0 ? Colors.white : AppColors.darkTeal),
            const SizedBox(width: 6),
            Text(
              count > 0 ? 'Filters ($count)' : 'Filters',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: count > 0 ? Colors.white : AppColors.darkTeal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact readout of what is currently narrowing the results, so a user
  /// staring at three listings knows why.
  Widget _buildActiveFilterSummary() {
    if (_filters.activeCount == 0) return const SizedBox.shrink();

    final bits = <String>[];
    if (_filters.startDate != null && _filters.endDate != null) {
      bits.add(Fmt.dateRange(_filters.startDate!, _filters.endDate!));
    }
    if (_filters.guests != null) bits.add(Fmt.guests(_filters.guests!));
    if (_filters.minPrice != null || _filters.maxPrice != null) {
      final lo = _filters.minPrice == null ? '' : Fmt.money(_filters.minPrice);
      final hi = _filters.maxPrice == null ? '' : Fmt.money(_filters.maxPrice);
      bits.add(lo.isEmpty
          ? 'under $hi'
          : hi.isEmpty
              ? 'over $lo'
              : '$lo – $hi');
    }
    if (_filters.amenities.isNotEmpty) {
      bits.add('${_filters.amenities.length} amenities');
    }
    if (_filters.radiusKm != null && _filters.latitude != null) {
      bits.add('within ${_filters.radiusKm!.toStringAsFixed(0)} km');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${rooms.length} ${rooms.length == 1 ? 'stay' : 'stays'}'
              '${bits.isEmpty ? '' : ' · ${bits.join(' · ')}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: textLight),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = 'All';
                _filters.reset();
              });
              _search();
            },
            child: const Text('Clear',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkTeal)),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterBar() {
    final List<Map<String, dynamic>> categories = [
      {"name": "All", "icon": Icons.explore_outlined},
      {"name": "Rooms", "icon": Icons.meeting_room_outlined},
      {"name": "Apartments", "icon": Icons.apartment_outlined},
      {"name": "Houses", "icon": Icons.house_outlined},
      {"name": "Villas", "icon": Icons.villa_outlined},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat["name"];
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = cat["name"];
                _filters.propertyType = switch (cat["name"]) {
                  'Rooms' => 'Room',
                  'Apartments' => 'Apartment',
                  'Houses' => 'House',
                  'Villas' => 'Villa',
                  _ => null,
                };
              });
              _search();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(colors: AppColors.primaryGradient)
                    : null,
                color: isSelected ? null : Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.grey.shade200,
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.darkTeal.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.01),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
              ),
              child: Row(
                children: [
                  Icon(
                    cat["icon"],
                    size: 16,
                    color: isSelected ? Colors.white : AppColors.darkTeal,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cat["name"],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupRooms();
    final cityOrder = grouped.keys.toList();

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
          _bottomNavItem(Icons.home, "Home", 0),
          _bottomNavItem(Icons.luggage_rounded, "Trips", 1),
          _bottomNavItem(Icons.smart_toy_outlined, "Chatbot", 2),
          _bottomNavItem(Icons.message_outlined, "Messages", 3),
          _bottomNavItem(Icons.person_outline, "Profile", 4),
        ],
        onTap: _onNavTap,
      ),
      body: SafeArea(
        // The banner, search box and filters stay mounted while a query runs,
        // so you can keep typing. Only the results area swaps to skeletons —
        // the old full-screen spinner blanked the search box mid-search.
        child: Column(
                children: [
                  // Top Gradient Banner (SurfNStay + Find a Perfect Stay)
                  _buildTopBanner(),

                  // Search Bar
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onQueryChanged,
                      decoration: CustomInputDecoration.getDecoration(
                        "Search city or room name...",
                        prefixIcon: Icons.search_rounded,
                      ).copyWith(
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _onQueryChanged("");
                                },
                              )
                            : null,
                      ),
                    ),
                  ),

                  // Category strip + filters entry point
                  Row(
                    children: [
                      Expanded(child: _buildCategoryFilterBar()),
                      _buildFilterButton(),
                      const SizedBox(width: 12),
                    ],
                  ),

                  _buildActiveFilterSummary(),

                  // Room List / Sections
                  Expanded(
                    child: loading
                        ? _buildResultsSkeleton()
                        : () {
                      final hasAnyRooms = cityOrder.any((c) => grouped[c]!.isNotEmpty);
                      if (!hasAnyRooms) {
                        final filtered = _filters.activeCount > 0;
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.location_off_rounded, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No results for "$_searchQuery"'
                                    : filtered
                                        ? 'No stays match these filters'
                                        : 'No stays available yet',
                                style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                              ),
                              if (_searchQuery.isNotEmpty || filtered) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {
                                      _searchQuery = "";
                                      _selectedCategory = "All";
                                      _filters
                                        ..query = ""
                                        ..reset();
                                    });
                                    _search();
                                  },
                                  child: const Text("Clear all filters", style: TextStyle(color: AppColors.darkTeal, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: cityOrder.length,
                        itemBuilder: (context, cityIndex) {
                          final city = cityOrder[cityIndex];
                          final cityRooms = grouped[city]!;
                          if (cityRooms.isEmpty) return const SizedBox.shrink();

                          final bool isHorizontal = cityRooms.length > 2;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // City Section Title
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      city,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.darkTeal,
                                          letterSpacing: -0.5),
                                    ),
                                    if (isHorizontal)
                                      Row(
                                        children: const [
                                          Text(
                                            "Swipe right",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black38,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.black38),
                                        ],
                                      ),
                                  ],
                                ),
                              ),

                              // If > 2 rooms, display a horizontal list; otherwise, grid layout
                              isHorizontal
                                  ? SizedBox(
                                      height: 260,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: cityRooms.length,
                                        itemBuilder: (context, index) {
                                          return Container(
                                            width: MediaQuery.of(context).size.width * 0.46,
                                            margin: const EdgeInsets.only(right: 16, bottom: 8),
                                            child: FadeSlideIn(
                                              index: index,
                                              child: _roomCard(cityRooms[index]),
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  : GridView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: cityRooms.length,
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 16,
                                        childAspectRatio: 0.76,
                                      ),
                                      itemBuilder: (context, index) => FadeSlideIn(
                                        index: index,
                                        child: _roomCard(cityRooms[index]),
                                      ),
                                    ),
                              const SizedBox(height: 12),
                            ],
                          );
                        },
                      );
                    }(),
                  ),
                ],
              ),
      ),
    );
  }


  /// Placeholder grid shown while a search runs. Mirrors the real card shape so
  /// the layout does not jump when results arrive.
  Widget _buildResultsSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        const Shimmer(height: 20, width: 130, radius: 6),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.76,
          children: List.generate(4, (_) => const Shimmer(height: 220, radius: 22)),
        ),
      ],
    );
  }

  Widget _roomCard(Map<String, dynamic> room) {
    List images = room["images"];
    String price = room["price_per_night"].toString();
    String location = room["location"];
    String roomName = room["roomName"] ?? "Room";
    String propType = room["property_type"] ?? "Room";
    int beds = room["bedrooms"] ?? 1;
    int baths = room["bathrooms"] ?? 1;
    double avgRating = room["avg_rating"] ?? 0.0;

    final double listPrice = (room["price_per_night"] as num?)?.toDouble() ?? 0;
    final double effPrice =
        (room["effective_price"] as num?)?.toDouble() ?? listPrice;
    final double discount = (room["discount"] as num?)?.toDouble() ?? 0;
    final double? distanceKm = room["distance_km"] as double?;
    final bool hostVerified = room["host_verified"] == true;

    String propertyId = room["property_id"].toString();
    String hostId = room["host_id"].toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    CustomPageRoute(
                      child: RoomDetailPage(
                        roomName: roomName,
                        location: location,
                        images: List<String>.from(images),
                        price: double.tryParse(price) ?? 0,
                        propertyId: propertyId,
                        hostId: hostId,
                      ),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Property Image
                    AspectRatio(
                      aspectRatio: 1.4,
                      child: images.isEmpty
                          ? Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image, size: 40, color: Colors.black38),
                            )
                          : Hero(
                              tag: "property-image-",
                              child: Image.network(
                                images[0],
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Category & beds/baths stats
                          Text(
                            "$propType • $beds ${beds == 1 ? 'bed' : 'beds'} • $baths ${baths == 1 ? 'bath' : 'baths'}",
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.black38,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Title, with the host verification tick beside it
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  roomName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (hostVerified) ...[
                                const SizedBox(width: 5),
                                const VerifiedBadge(
                                    status: 'verified', compact: true),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Location
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 12, color: AppColors.lightTeal),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.black45,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (distanceKm != null) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.near_me_outlined,
                                    size: 11, color: AppColors.darkTeal),
                                const SizedBox(width: 4),
                                Text(
                                  Fmt.distance(distanceKm),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.darkTeal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Price — struck-through original when discounted
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              if (discount > 0) ...[
                                Text(
                                  Fmt.money(listPrice),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black38,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  Fmt.money(effPrice),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppColors.darkTeal,
                                  ),
                                ),
                              ),
                              const Text(
                                " / night",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Live Rating Overlay (Top-Left)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 12),
                    const SizedBox(width: 3),
                    Text(
                      avgRating > 0 ? avgRating.toStringAsFixed(1) : "New",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Wishlist heart overlay (Top-Right)
            Positioned(
              top: 8,
              right: 8,
              child: StatefulBuilder(
                builder: (context, setCardState) {
                  final inWishlist = WishlistService.instance.contains(propertyId);
                  return GestureDetector(
                    onTap: () {
                      if (inWishlist) {
                        WishlistService.instance.remove(propertyId);
                        setCardState(() {});
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text("Removed from Wishlist"),
                              duration: Duration(seconds: 1),
                            ),
                          );
                      } else {
                        WishlistService.instance.add({
                          'property_id': propertyId,
                          'host_id':     hostId,
                          'roomName':    roomName,
                          'location':    location,
                          'price':       double.tryParse(price) ?? 0,
                          'images':      List<String>.from(images),
                        });
                        setCardState(() {});
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text('"$roomName" added to Wishlist! ❤️'),
                              backgroundColor: AppColors.darkTeal,
                              duration: const Duration(seconds: 1),
                              action: SnackBarAction(
                                label: "View",
                                textColor: Colors.white,
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    CustomPageRoute(child: const WishlistPage()),
                                  );
                                },
                              ),
                            ),
                          );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        inWishlist ? Icons.favorite : Icons.favorite_border,
                        color: inWishlist ? Colors.red : Colors.grey.shade600,
                        size: 16,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}