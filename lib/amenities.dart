import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One selectable amenity, mirroring a row of the `amenities` table.
class Amenity {
  final String key;
  final String label;
  final String? icon;

  const Amenity({required this.key, required this.label, this.icon});

  factory Amenity.fromMap(Map<String, dynamic> m) => Amenity(
        key: m['key'].toString(),
        label: m['label']?.toString() ?? m['key'].toString(),
        icon: m['icon']?.toString(),
      );

  IconData get iconData => AmenityIcons.resolve(icon);
}

/// The amenity list changes rarely, so it is fetched once per app run rather
/// than on every screen that needs it.
class AmenityCatalog {
  AmenityCatalog._();

  static List<Amenity>? _cache;
  static Future<List<Amenity>>? _inFlight;

  static Future<List<Amenity>> load() {
    if (_cache != null) return Future.value(_cache);
    return _inFlight ??= _fetch();
  }

  static Future<List<Amenity>> _fetch() async {
    try {
      final rows = await Supabase.instance.client
          .from('amenities')
          .select('key, label, icon, sort_order')
          .order('sort_order');
      _cache = List<Map<String, dynamic>>.from(rows)
          .map(Amenity.fromMap)
          .toList(growable: false);
    } catch (e) {
      debugPrint('Amenity catalog failed to load: $e');
      _cache = const [];
    } finally {
      _inFlight = null;
    }
    return _cache!;
  }

  static String labelFor(String key) {
    final match = _cache?.where((a) => a.key == key);
    if (match != null && match.isNotEmpty) return match.first.label;
    // Fall back to a readable form of the key itself.
    return key
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static IconData iconFor(String key) {
    final match = _cache?.where((a) => a.key == key);
    if (match != null && match.isNotEmpty) return match.first.iconData;
    return Icons.check_circle_outline;
  }
}

/// Icon names arrive from the database as strings; Flutter tree-shakes icons,
/// so they cannot be looked up dynamically and must be mapped explicitly.
class AmenityIcons {
  AmenityIcons._();

  static const Map<String, IconData> _byName = {
    'wifi': Icons.wifi,
    'ac_unit': Icons.ac_unit,
    'local_fire_department': Icons.local_fire_department,
    'shower': Icons.shower,
    'bolt': Icons.bolt,
    'kitchen': Icons.kitchen,
    'local_laundry_service': Icons.local_laundry_service,
    'tv': Icons.tv,
    'desk': Icons.desk,
    'local_parking': Icons.local_parking,
    'elevator': Icons.elevator,
    'shield': Icons.shield,
    'videocam': Icons.videocam,
    'balcony': Icons.balcony,
    'yard': Icons.yard,
    'pool': Icons.pool,
    'fitness_center': Icons.fitness_center,
    'free_breakfast': Icons.free_breakfast,
    'pets': Icons.pets,
    'accessible': Icons.accessible,
  };

  static IconData resolve(String? name) =>
      _byName[name] ?? Icons.check_circle_outline;
}
