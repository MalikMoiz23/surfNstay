import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  static const Color primary = Color(0xFF0F4C5C);
  static const Color bg = Color(0xFFF8FAFC); // Pop white cards on soft light background
  static const Color textLight = Color(0xFF64748B);

  String _searchQuery = "";
  String _selectedCategory = "All"; // All, Rooms, Apartments, Houses, Villas
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
    fetchRooms();
  }

  Future<void> fetchRooms() async {
    setState(() => loading = true);

    try {
      // 1. Fetch properties
      final response = await supabase
          .from('properties')
          .select()
          .order('created_at', ascending: false);

      // 2. Fetch all ratings to calculate average rating
      final ratingsRes = await supabase
          .from('ratings')
          .select('property_id, rating');

      // Create a map of propertyId -> List of ratings
      Map<String, List<double>> propertyRatings = {};
      for (var r in ratingsRes) {
        final pid = r['property_id'].toString();
        final rate = (r['rating'] as num).toDouble();
        propertyRatings.putIfAbsent(pid, () => []).add(rate);
      }

      rooms = response.map<Map<String, dynamic>>((p) {
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

        final pid = p['id'].toString();
        final rates = propertyRatings[pid] ?? [];
        double avgRating = 0.0;
        if (rates.isNotEmpty) {
          final sum = rates.fold<double>(0.0, (acc, val) => acc + val);
          avgRating = sum / rates.length;
        }

        return {
          "property_id": pid,
          "host_id": p['host_id'],
          "images": imgs,
          "price_per_night": p['price_per_night'] ?? 0,
          "location": p['location'] ?? "",
          "roomName": p['room_name'] ?? "Room",
          "property_type": p['property_type'] ?? 'Room',
          "bedrooms": p['bedrooms'] ?? 1,
          "bathrooms": p['bathrooms'] ?? 1,
          "max_guests": p['max_guests'] ?? 1,
          "avg_rating": avgRating,
          "total_reviews": rates.length,
        };
      }).toList();

      setState(() => loading = false);
    } catch (e) {
      print("Error fetching rooms: $e");
      setState(() => loading = false);
    }
  }

  Map<String, List<Map<String, dynamic>>> groupRooms() {
    // 1. Filter by category
    Iterable<Map<String, dynamic>> tempRooms = rooms;
    if (_selectedCategory != "All") {
      String mappedType = "Room";
      if (_selectedCategory == "Apartments") mappedType = "Apartment";
      if (_selectedCategory == "Houses") mappedType = "House";
      if (_selectedCategory == "Villas") mappedType = "Villa";

      tempRooms = tempRooms.where((r) => r["property_type"] == mappedType);
    }

    // 2. Filter by search query
    final query = _searchQuery.toLowerCase().trim();
    final filtered = query.isEmpty
        ? tempRooms.toList()
        : tempRooms.where((r) {
            final loc  = r["location"].toString().toLowerCase();
            final name = r["roomName"].toString().toLowerCase();
            return loc.contains(query) || name.contains(query);
          }).toList();

    Map<String, List<Map<String, dynamic>>> grouped = {
      "Islamabad": [],
      "Karachi": [],
      "Lahore": [],
      "Taxila": [],
      "Wah": [],
      "Other Cities": []
    };

    for (var room in filtered) {
      String loc = room["location"].toString().toLowerCase();
      if (loc.contains("islamabad")) {
        grouped["Islamabad"]!.add(room);
      } else if (loc.contains("karachi")) {
        grouped["Karachi"]!.add(room);
      } else if (loc.contains("lahore")) {
        grouped["Lahore"]!.add(room);
      } else if (loc.contains("taxila")) {
        grouped["Taxila"]!.add(room);
      } else if (loc.contains("wah")) {
        grouped["Wah"]!.add(room);
      } else {
        grouped["Other Cities"]!.add(room);
      }
    }
    return grouped;
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
            onTap: () => setState(() => _selectedCategory = cat["name"]),
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
    List<String> cityOrder = [
      "Islamabad",
      "Karachi",
      "Lahore",
      "Taxila",
      "Wah",
      "Other Cities"
    ];

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
        child: loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.darkTeal))
            : Column(
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
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: CustomInputDecoration.getDecoration(
                        "Search city or room name...",
                        prefixIcon: Icons.search_rounded,
                      ).copyWith(
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = "");
                                },
                              )
                            : null,
                      ),
                    ),
                  ),

                  // Category Filter Bar
                  _buildCategoryFilterBar(),

                  // Room List / Sections
                  Expanded(
                    child: () {
                      final hasAnyRooms = cityOrder.any((c) => grouped[c]!.isNotEmpty);
                      if (!hasAnyRooms) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.location_off_rounded, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No results for "$_searchQuery"'
                                    : 'No stays available in this category',
                                style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                              ),
                              if (_searchQuery.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = "");
                                  },
                                  child: const Text("Clear search", style: TextStyle(color: AppColors.darkTeal, fontWeight: FontWeight.bold)),
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
                                            child: _roomCard(cityRooms[index]),
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
                                      itemBuilder: (context, index) => _roomCard(cityRooms[index]),
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

  Widget _roomCard(Map<String, dynamic> room) {
    List images = room["images"];
    String price = room["price_per_night"].toString();
    String location = room["location"];
    String roomName = room["roomName"] ?? "Room";
    String propType = room["property_type"] ?? "Room";
    int beds = room["bedrooms"] ?? 1;
    int baths = room["bathrooms"] ?? 1;
    double avgRating = room["avg_rating"] ?? 0.0;

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
                          : Image.network(
                              images[0],
                              width: double.infinity,
                              fit: BoxFit.cover,
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
                          // Title
                          Text(
                            roomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
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
                          const SizedBox(height: 8),
                          // Price
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                "PKR $price",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppColors.darkTeal,
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