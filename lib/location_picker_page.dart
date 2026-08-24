import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'app_theme.dart';

/// What the picker hands back to the caller.
class PickedLocation {
  final double latitude;
  final double longitude;
  final String address;
  final String city;

  const PickedLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.city,
  });
}

/// OpenStreetMap-backed location picker.
///
/// Deliberately not Google Maps: OSM tiles need no API key, no Google Cloud
/// project and no billing account, which keeps the app runnable by anyone who
/// clones the repo.
class LocationPickerPage extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  const LocationPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  // Roughly the centre of Pakistan, used when we have nothing better.
  static const LatLng _fallbackCentre = LatLng(30.3753, 69.3451);

  final MapController _map = MapController();
  final TextEditingController _searchCtrl = TextEditingController();

  // geocoding 5.x is instance-based; the top-level helpers were removed.
  final Geocoding _geocoding = Geocoding();

  late LatLng _pin;
  bool _resolving = false;
  bool _locating = false;
  String _address = '';
  String _city = '';

  @override
  void initState() {
    super.initState();
    final hasInitial =
        widget.initialLatitude != null && widget.initialLongitude != null;
    _pin = hasInitial
        ? LatLng(widget.initialLatitude!, widget.initialLongitude!)
        : _fallbackCentre;
    _address = widget.initialAddress ?? '';
    if (hasInitial) _reverseGeocode(_pin);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _resolving = true);
    try {
      final marks = await _geocoding.placemarkFromCoordinates(
          point.latitude, point.longitude);
      if (!mounted) return;
      if (marks.isNotEmpty) {
        final m = marks.first;
        final parts = [
          m.street,
          m.subLocality,
          m.locality,
          m.administrativeArea,
        ].where((p) => p != null && p.trim().isNotEmpty).cast<String>();
        setState(() {
          _address = parts.join(', ');
          _city = (m.locality?.trim().isNotEmpty ?? false)
              ? m.locality!.trim()
              : (m.subAdministrativeArea?.trim() ?? '');
        });
      }
    } catch (e) {
      // Reverse geocoding is a convenience. The coordinates are what matter,
      // so a failure here must not block the host from saving.
      debugPrint('Reverse geocode failed: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _resolving = true);
    try {
      final results = await _geocoding.locationFromAddress(query);
      if (!mounted) return;
      if (results.isEmpty) {
        _snack('No match for that address. Try a nearby landmark or city.');
        return;
      }
      final found = LatLng(results.first.latitude, results.first.longitude);
      setState(() => _pin = found);
      _map.move(found, 15);
      await _reverseGeocode(found);
    } catch (e) {
      if (!mounted) return;
      _snack('Could not look up that address.');
      debugPrint('Forward geocode failed: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Turn on location services to use this.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _snack('Location permission denied. Pick the spot on the map instead.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() => _pin = here);
      _map.move(here, 16);
      await _reverseGeocode(here);
    } catch (e) {
      if (!mounted) return;
      _snack('Could not get your location.');
      debugPrint('Geolocation failed: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _confirm() {
    Navigator.pop(
      context,
      PickedLocation(
        latitude: _pin.latitude,
        longitude: _pin.longitude,
        address: _address.trim(),
        city: _city.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasInitial =
        widget.initialLatitude != null && widget.initialLongitude != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin your property'),
        backgroundColor: AppColors.darkTeal,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _pin,
              initialZoom: hasInitial ? 15 : 5.5,
              onTap: (_, point) {
                setState(() => _pin = point);
                _reverseGeocode(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.surfnstay',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pin,
                    width: 46,
                    height: 46,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on,
                        size: 46, color: AppColors.darkTeal),
                  ),
                ],
              ),
            ],
          ),

          // Search bar
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchAddress(),
                decoration: InputDecoration(
                  hintText: 'Search an address, area or landmark',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _searchAddress,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),

          // OSM attribution is required by the tile usage policy.
          Positioned(
            bottom: 168,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.white70,
              child: const Text('© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 9, color: Colors.black87)),
            ),
          ),

          // Bottom sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 16),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 18, color: AppColors.darkTeal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _resolving
                              ? const Text('Finding address…',
                                  style: TextStyle(color: Colors.black45))
                              : Text(
                                  _address.isEmpty
                                      ? 'Tap the map to drop a pin'
                                      : _address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_pin.latitude.toStringAsFixed(5)}, '
                      '${_pin.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(fontSize: 11, color: Colors.black38),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.darkTeal,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28)),
                            ),
                            icon: _locating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.my_location, size: 18),
                            label: const Text('My location'),
                            onPressed: _locating ? null : _useMyLocation,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GradientButton(
                            text: 'Use this spot',
                            icon: Icons.check_rounded,
                            onPressed: _confirm,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
