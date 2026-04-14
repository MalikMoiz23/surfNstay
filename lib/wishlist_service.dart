/// Singleton that holds the current session's wishlist.
/// Any screen can add/remove items and they all see the same list.
class WishlistService {
  WishlistService._();
  static final WishlistService instance = WishlistService._();

  final List<Map<String, dynamic>> items = [];

  bool contains(String propertyId) =>
      items.any((r) => r['property_id'] == propertyId);

  void add(Map<String, dynamic> room) {
    if (!contains(room['property_id'])) {
      items.add(room);
    }
  }

  void remove(String propertyId) =>
      items.removeWhere((r) => r['property_id'] == propertyId);
}
