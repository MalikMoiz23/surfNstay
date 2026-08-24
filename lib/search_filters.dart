import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'amenities.dart';
import 'app_theme.dart';
import 'formatting.dart';

/// Everything the `search_properties` RPC can filter on.
///
/// The dashboard used to filter a full table dump in Dart on two fields:
/// category and a substring of name/location. Dates, guests, price and
/// amenities were not filterable at all.
class SearchFilters {
  String query;
  String? city;
  String? propertyType;
  double? minPrice;
  double? maxPrice;
  int? guests;
  DateTime? startDate;
  DateTime? endDate;
  Set<String> amenities;
  String sort; // recent | price_asc | price_desc | rating | distance
  double? radiusKm;
  double? latitude;
  double? longitude;

  SearchFilters({
    this.query = '',
    this.city,
    this.propertyType,
    this.minPrice,
    this.maxPrice,
    this.guests,
    this.startDate,
    this.endDate,
    Set<String>? amenities,
    this.sort = 'recent',
    this.radiusKm,
    this.latitude,
    this.longitude,
  }) : amenities = amenities ?? <String>{};

  SearchFilters copy() => SearchFilters(
        query: query,
        city: city,
        propertyType: propertyType,
        minPrice: minPrice,
        maxPrice: maxPrice,
        guests: guests,
        startDate: startDate,
        endDate: endDate,
        amenities: {...amenities},
        sort: sort,
        radiusKm: radiusKm,
        latitude: latitude,
        longitude: longitude,
      );

  /// Count shown on the Filters button. `query` is excluded because it has its
  /// own visible search box.
  int get activeCount {
    var n = 0;
    if (propertyType != null) n++;
    if (minPrice != null || maxPrice != null) n++;
    if (guests != null) n++;
    if (startDate != null && endDate != null) n++;
    if (amenities.isNotEmpty) n++;
    if (radiusKm != null && latitude != null) n++;
    if (sort != 'recent') n++;
    return n;
  }

  Map<String, dynamic> toRpcParams() => {
        'p_query': query.trim().isEmpty ? null : query.trim(),
        'p_city': city,
        'p_type': propertyType,
        'p_min_price': minPrice,
        'p_max_price': maxPrice,
        'p_guests': guests,
        'p_start_date': startDate == null ? null : Fmt.isoDate(startDate!),
        'p_end_date': endDate == null ? null : Fmt.isoDate(endDate!),
        'p_amenities': amenities.isEmpty ? null : amenities.toList(),
        'p_lat': latitude,
        'p_lng': longitude,
        'p_radius_km': radiusKm,
        'p_sort': sort,
        'p_limit': 200,
        'p_offset': 0,
      };

  void reset() {
    city = null;
    propertyType = null;
    minPrice = null;
    maxPrice = null;
    guests = null;
    startDate = null;
    endDate = null;
    amenities.clear();
    sort = 'recent';
    radiusKm = null;
    latitude = null;
    longitude = null;
  }
}

/// Bottom sheet that edits a copy of the filters and returns it on Apply, so
/// backing out leaves the current results untouched.
class SearchFilterSheet extends StatefulWidget {
  final SearchFilters initial;

  const SearchFilterSheet({super.key, required this.initial});

  static Future<SearchFilters?> show(
      BuildContext context, SearchFilters current) {
    return showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SearchFilterSheet(initial: current),
    );
  }

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  late SearchFilters _f;
  List<Amenity> _catalog = const [];
  bool _locating = false;

  static const _types = ['Room', 'Apartment', 'House', 'Villa'];

  static const _sorts = <String, String>{
    'recent': 'Newest',
    'price_asc': 'Price: low to high',
    'price_desc': 'Price: high to low',
    'rating': 'Top rated',
    'distance': 'Nearest',
  };

  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _f = widget.initial.copy();
    if (_f.minPrice != null) _minCtrl.text = _f.minPrice!.toStringAsFixed(0);
    if (_f.maxPrice != null) _maxCtrl.text = _f.maxPrice!.toStringAsFixed(0);
    AmenityCatalog.load().then((list) {
      if (mounted) setState(() => _catalog = list);
    });
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: (_f.startDate != null && _f.endDate != null)
          ? DateTimeRange(start: _f.startDate!, end: _f.endDate!)
          : null,
      helpText: 'Select your stay',
    );
    if (range == null) return;
    setState(() {
      _f.startDate = range.start;
      _f.endDate = range.end;
    });
  }

  Future<void> _enableNearMe() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Turn on location services to sort by distance.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _f.latitude = pos.latitude;
        _f.longitude = pos.longitude;
        _f.radiusKm ??= 25;
      });
    } catch (e) {
      _snack('Could not get your location.');
      debugPrint('near-me failed: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  void _apply() {
    _f.minPrice = double.tryParse(_minCtrl.text.trim());
    _f.maxPrice = double.tryParse(_maxCtrl.text.trim());
    if (_f.minPrice != null &&
        _f.maxPrice != null &&
        _f.minPrice! > _f.maxPrice!) {
      _snack('Minimum price is higher than the maximum.');
      return;
    }
    if (_f.sort == 'distance' && _f.latitude == null) {
      _snack('Turn on "Near me" to sort by distance.');
      return;
    }
    Navigator.pop(context, _f);
  }

  @override
  Widget build(BuildContext context) {
    final hasDates = _f.startDate != null && _f.endDate != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  const Text('Filters',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkTeal)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _f.reset();
                      _minCtrl.clear();
                      _maxCtrl.clear();
                    }),
                    child: const Text('Reset',
                        style: TextStyle(color: Colors.black54)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                children: [
                  _label('Dates'),
                  InkWell(
                    onTap: _pickDates,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(children: [
                        const Icon(Icons.date_range_rounded,
                            size: 18, color: AppColors.darkTeal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasDates
                                ? Fmt.dateRange(_f.startDate!, _f.endDate!)
                                : 'Any dates',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: hasDates ? Colors.black87 : Colors.black45,
                            ),
                          ),
                        ),
                        if (hasDates)
                          GestureDetector(
                            onTap: () => setState(() {
                              _f.startDate = null;
                              _f.endDate = null;
                            }),
                            child: const Icon(Icons.close,
                                size: 18, color: Colors.black38),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Only listings free for the whole range are shown.',
                    style: TextStyle(fontSize: 11, color: Colors.black45),
                  ),

                  _label('Guests'),
                  Row(
                    children: [
                      _stepperButton(Icons.remove, () {
                        final g = (_f.guests ?? 1) - 1;
                        setState(() => _f.guests = g < 1 ? null : g);
                      }),
                      Expanded(
                        child: Center(
                          child: Text(
                            _f.guests == null ? 'Any' : Fmt.guests(_f.guests!),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      _stepperButton(Icons.add, () {
                        setState(() => _f.guests = (_f.guests ?? 0) + 1);
                      }),
                    ],
                  ),

                  _label('Property type'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _choice('Any', _f.propertyType == null,
                          () => setState(() => _f.propertyType = null)),
                      for (final t in _types)
                        _choice(t, _f.propertyType == t,
                            () => setState(() => _f.propertyType = t)),
                    ],
                  ),

                  _label('Price per night (PKR)'),
                  Row(children: [
                    Expanded(child: _priceField('Min', _minCtrl)),
                    const SizedBox(width: 12),
                    Expanded(child: _priceField('Max', _maxCtrl)),
                  ]),

                  _label('Amenities'),
                  if (_catalog.isEmpty)
                    const Text('Loading…',
                        style: TextStyle(fontSize: 12, color: Colors.black45))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _catalog.map((a) {
                        final on = _f.amenities.contains(a.key);
                        return _choice(a.label, on, () {
                          setState(() => on
                              ? _f.amenities.remove(a.key)
                              : _f.amenities.add(a.key));
                        }, icon: a.iconData);
                      }).toList(),
                    ),

                  _label('Near me'),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.darkTeal,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _locating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Icon(
                                _f.latitude == null
                                    ? Icons.my_location
                                    : Icons.check_circle,
                                size: 16),
                        label: Text(_f.latitude == null
                            ? 'Use my location'
                            : 'Location set'),
                        onPressed: _locating ? null : _enableNearMe,
                      ),
                    ),
                    if (_f.latitude != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<double>(
                          initialValue: _f.radiusKm ?? 25,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          items: const [5.0, 10.0, 25.0, 50.0, 100.0]
                              .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text('${r.toStringAsFixed(0)} km')))
                              .toList(),
                          onChanged: (v) => setState(() => _f.radiusKm = v),
                        ),
                      ),
                    ],
                  ]),

                  _label('Sort by'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sorts.entries
                        .map((e) => _choice(e.value, _f.sort == e.key,
                            () => setState(() => _f.sort = e.key)))
                        .toList(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SafeArea(
                top: false,
                child: GradientButton(
                  text: 'Show results',
                  icon: Icons.search_rounded,
                  onPressed: _apply,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.darkTeal)),
      );

  Widget _choice(String label, bool selected, VoidCallback onTap,
      {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: AppColors.primaryGradient)
              : null,
          color: selected ? null : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? Colors.transparent : Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14, color: selected ? Colors.white : AppColors.darkTeal),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _priceField(String hint, TextEditingController c) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: hint,
          prefixText: 'PKR ',
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF5F7FA),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      );

  Widget _stepperButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Icon(icon, size: 18, color: AppColors.darkTeal),
        ),
      );
}
