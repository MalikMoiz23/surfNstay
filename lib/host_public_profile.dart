import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'page_transition.dart';
import 'RoomDetailPage.dart';
import 'wishlist_service.dart';
import 'wishlist_page.dart';

class HostPublicProfilePage extends StatefulWidget {
  final String hostId;

  const HostPublicProfilePage({super.key, required this.hostId});

  @override
  State<HostPublicProfilePage> createState() => _HostPublicProfilePageState();
}

class _HostPublicProfilePageState extends State<HostPublicProfilePage> {
  final supabase = Supabase.instance.client;
  bool loading = true;

  Map<String, dynamic>? hostData;
  List<Map<String, dynamic>> properties = [];
  double averageRating = 0.0;
  int totalReviews = 0;

  @override
  void initState() {
    super.initState();
    _fetchFullProfile();
  }

  Future<void> _fetchFullProfile() async {
    setState(() => loading = true);
    try {
      // 1. Fetch Host Bio
      final hRes = await supabase
          .from('hosts')
          .select()
          .eq('id', widget.hostId)
          .maybeSingle();
      
      hostData = hRes;

      // 2. Fetch Properties
      final pRes = await supabase
          .from('properties')
          .select()
          .eq('host_id', widget.hostId)
          .order('created_at', ascending: false);
      
      properties = List<Map<String, dynamic>>.from(pRes);

      // 3. Aggregate Ratings
      if (properties.isNotEmpty) {
        final List<String> propertyIds = properties.map((e) => e['id'].toString()).toList();
        final rRes = await supabase
            .from('ratings')
            .select('rating')
            .filter('property_id', 'in', propertyIds);

        if (rRes != null && rRes.isNotEmpty) {
          double sum = 0;
          for (var r in rRes) {
            sum += (r['rating'] as num).toDouble();
          }
          averageRating = sum / rRes.length;
          totalReviews = rRes.length;
        }
      }

    } catch (e) {
      debugPrint("Error fetching host profile: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.darkTeal)),
      );
    }

    if (hostData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Profile")),
        body: const Center(child: Text("Host not found")),
      );
    }

    final String name = hostData!['fullName'] ?? "Host";
    final String pic = hostData!['profile_pic'] ?? "";
    final DateTime createdAt = DateTime.tryParse(hostData!['created_at'] ?? "") ?? DateTime.now();
    final String joinedDate = DateFormat('MMMM yyyy').format(createdAt);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.primaryGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white,
                        backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                        child: pic.isEmpty 
                          ? const Icon(Icons.person, size: 50, color: AppColors.darkTeal) 
                          : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified, color: Colors.white, size: 20),
                      ],
                    ),
                    const Text(
                      "Professional Host",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statItem("Ratings", averageRating == 0 ? "N/A" : averageRating.toStringAsFixed(1), Icons.star_rounded),
                      _statItem("Reviews", totalReviews.toString(), Icons.reviews_outlined),
                      _statItem("Listings", properties.length.toString(), Icons.home_work_outlined),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Host Info Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Account Details", 
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal)),
                        const SizedBox(height: 16),
                        _infoRow(Icons.calendar_today, "Hosting since $joinedDate"),
                        _infoRow(Icons.phone_outlined, hostData!['phone'] ?? "N/A"),
                        _infoRow(Icons.email_outlined, hostData!['email'] ?? "N/A"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 35),
                  Text("All Listings (${properties.length})", 
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 15),
                ],
              ),
            ),
          ),

          // Properties Grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.63,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _listingCard(properties[index]),
                childCount: properties.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.darkTeal, size: 28),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.lightTeal),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 15, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _listingCard(Map<String, dynamic> p) {
    List<String> images = [];
    if (p['image1_url'] != null && p['image1_url'] != "") images.add(p['image1_url']);
    if (p['image2_url'] != null && p['image2_url'] != "") images.add(p['image2_url']);
    if (p['image3_url'] != null && p['image3_url'] != "") images.add(p['image3_url']);

    String price = p['price_per_night']?.toString() ?? "0";
    String location = p['location'] ?? "Unknown";
    String roomName = p['room_name'] ?? "Room";
    String propertyId = p['id'].toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                CustomPageRoute(
                  child: RoomDetailPage(
                    roomName: roomName,
                    location: location,
                    images: images,
                    price: double.tryParse(price) ?? 0,
                    propertyId: propertyId,
                    hostId: widget.hostId,
                  ),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  child: images.isEmpty
                      ? Container(height: 120, color: Colors.grey[300], child: const Icon(Icons.broken_image))
                      : Image.network(images[0], height: 120, width: double.infinity, fit: BoxFit.cover),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("PKR $price", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(location, style: const TextStyle(color: Colors.black54, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: StatefulBuilder(
              builder: (context, setCardState) {
                final inWishlist = WishlistService.instance.contains(propertyId);
                return GestureDetector(
                  onTap: () {
                    if (inWishlist) {
                      WishlistService.instance.remove(propertyId);
                    } else {
                      WishlistService.instance.add({
                        'property_id': propertyId,
                        'host_id': widget.hostId,
                        'roomName': roomName,
                        'location': location,
                        'price': double.tryParse(price) ?? 0,
                        'images': images,
                      });
                    }
                    setCardState(() {});
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(SnackBar(
                        content: Text(inWishlist ? "Removed from Wishlist" : "Added to Wishlist"),
                        duration: const Duration(seconds: 1),
                      ));
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      gradient: inWishlist 
                        ? const LinearGradient(colors: [AppColors.darkTeal, AppColors.darkTeal])
                        : const LinearGradient(colors: AppColors.primaryGradient),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(inWishlist ? Icons.favorite : Icons.favorite_border, color: Colors.white, size: 16),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
