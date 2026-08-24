import 'package:flutter/material.dart';
import 'wishlist_service.dart';
import 'RoomDetailPage.dart';

/// Reached from Profile → My Wishlist. It is no longer a bottom-nav
/// destination (the Trips tab took that slot), so it is a pushed route with a
/// back button instead of its own nav bar.
class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  static const Color primary   = Color(0xFF0F4C5C);
  static const Color bg        = Color(0xFFF7F9FB);

  void _removeItem(String propertyId) {
    setState(() => WishlistService.instance.remove(propertyId));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text("Removed from Wishlist"),
          duration: Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final items = WishlistService.instance.items;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F4C5C), Color(0xFF26C6DA)],
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Icon(Icons.favorite, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    "Wishlist  (${items.length})",
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),

            // List
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite_border, size: 70, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            "Your wishlist is empty.",
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          SizedBox(height: 6),
                          Text(
                            "Tap \"Add to Wishlist\" on any room to save it here.",
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, index) => _wishlistCard(items[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wishlistCard(Map<String, dynamic> room) {
    final images     = List<String>.from(room['images'] ?? []);
    final roomName   = room['roomName'] ?? 'Room';
    final location   = room['location'] ?? '';
    final price      = (room['price'] as double?) ?? 0.0;
    final propertyId = room['property_id'] as String;
    final hostId     = room['host_id'] as String;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoomDetailPage(
              roomName:   roomName,
              location:   location,
              images:     images,
              price:      price,
              propertyId: propertyId,
              hostId:     hostId,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: primary.withOpacity(0.12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image + Remove button overlay
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  child: images.isEmpty
                      ? Container(
                          height: 180,
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
                          ),
                        )
                      : Image.network(
                          images[0],
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 180,
                            color: Colors.grey[200],
                            child: const Center(
                              child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
                            ),
                          ),
                        ),
                ),
                // Remove (heart) button
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () => _removeItem(propertyId),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Icon(Icons.favorite, color: Color(0xFFFF6B6B), size: 22),
                    ),
                  ),
                ),
                // "Tap to view" hint
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        "Tap to view details",
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Details row
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roomName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 14, color: Color(0xFF64748B)),
                            const SizedBox(width: 3),
                            Text(location,
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "PKR ${price.toStringAsFixed(0)}",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F4C5C)),
                      ),
                      const Text("/ night",
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                ],
              ),
            ),

            // Remove button at bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _removeItem(propertyId),
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B), size: 18),
                  label: const Text("Remove from Wishlist",
                      style: TextStyle(color: Color(0xFFFF6B6B))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFF6B6B)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
