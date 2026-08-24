import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_theme.dart';
import 'page_transition.dart';

class EditPropertyScreen extends StatefulWidget {
  final String propertyId;

  const EditPropertyScreen({super.key, required this.propertyId});

  @override
  State<EditPropertyScreen> createState() => _EditPropertyScreenState();
}

class _EditPropertyScreenState extends State<EditPropertyScreen> {
  final supabase = Supabase.instance.client;

  final TextEditingController locationCtrl    = TextEditingController();
  final TextEditingController priceCtrl       = TextEditingController();
  final TextEditingController roomNameCtrl    = TextEditingController();
  final TextEditingController discountCtrl    = TextEditingController();
  final TextEditingController facilitiesCtrl  = TextEditingController();
  final TextEditingController descriptionCtrl = TextEditingController();
  final TextEditingController bedroomsCtrl    = TextEditingController();
  final TextEditingController bathroomsCtrl   = TextEditingController();
  final TextEditingController maxGuestsCtrl   = TextEditingController();

  // ── New fields ───────────────────────────────────────────────────────────
  String _propertyType    = 'Room';
  String _guestPreference = 'Any';

  static const List<String> _propertyTypes    = ['Room', 'Apartment', 'House', 'Villa'];
  static const List<String> _guestPreferences = ['Any', 'Family', 'Female Only', 'Bachelors'];

  static const Map<String, IconData> _typeIcons = {
    'Room':      Icons.meeting_room_rounded,
    'Apartment': Icons.apartment_rounded,
    'House':     Icons.house_rounded,
    'Villa':     Icons.villa_rounded,
  };

  static const Map<String, IconData> _prefIcons = {
    'Any':         Icons.people_rounded,
    'Family':      Icons.family_restroom_rounded,
    'Female Only': Icons.female_rounded,
    'Bachelors':   Icons.male_rounded,
  };

  List<String?> imageUrls  = [null, null, null];
  List<File?>   newImages  = [null, null, null];
  List<bool?>   _aiFlags   = [null, null, null];
  List<bool>    _checking  = [false, false, false];

  bool loading = true;

  // ── AI Detector endpoint ─────────────────────────────────────────────────
  static const String _detectorUrl =
      'https://malikmoiz-surf-n-stay-detector.hf.space/detect';

  @override
  void initState() {
    super.initState();
    fetchProperty();
  }

  // ── Fetch existing property ──────────────────────────────────────────────
  Future<void> fetchProperty() async {
    setState(() => loading = true);
    try {
      final response = await supabase
          .from('properties')
          .select('*')
          .eq('id', widget.propertyId)
          .maybeSingle();

      if (response == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Property not found')));
        Navigator.pop(context);
        return;
      }

      setState(() {
        roomNameCtrl.text    = response['room_name'] ?? '';
        locationCtrl.text    = response['location'] ?? '';
        priceCtrl.text       = response['price_per_night']?.toString() ?? '';
        discountCtrl.text    = response['discount']?.toString() ?? '';
        facilitiesCtrl.text  = response['facilities'] ?? '';
        descriptionCtrl.text = response['description'] ?? '';
        bedroomsCtrl.text    = response['bedrooms']?.toString() ?? '1';
        bathroomsCtrl.text   = response['bathrooms']?.toString() ?? '1';
        maxGuestsCtrl.text   = response['max_guests']?.toString() ?? '1';
        _propertyType =
            response['property_type'] ?? 'Room';
        _guestPreference =
            response['guest_preference'] ?? 'Any';

        imageUrls[0] = response['image1_url'];
        imageUrls[1] = response['image2_url'];
        imageUrls[2] = response['image3_url'];
      });
    } catch (e) {
      debugPrint('Error fetching property: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching property: $e')));
    } finally {
      setState(() => loading = false);
    }
  }

  // ── Pick + AI-check a new image ──────────────────────────────────────────
  Future<void> pickImage(int index) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      newImages[index]  = file;
      _aiFlags[index]   = null;
      _checking[index]  = true;
    });

    final isAi = await _checkAiImage(file);
    if (!mounted) return;

    setState(() {
      _checking[index] = false;
      _aiFlags[index]  = isAi;
    });

    if (isAi) _showAiError(index);
  }

  Future<bool> _checkAiImage(File file) async {
    try {
      final uri     = Uri.parse(_detectorUrl);
      final client  = HttpClient();
      final request = await client.postUrl(uri);

      request.headers.removeAll(HttpHeaders.expectHeader);

      final boundary =
          '----SurfNStayBoundary${DateTime.now().millisecondsSinceEpoch}';
      request.headers.set(
          'content-type', 'multipart/form-data; boundary=$boundary');

      final fileName = file.path.split('/').last.split('\\').last;
      final header =
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
          'Content-Type: image/jpeg\r\n\r\n';
      final footer = '\r\n--$boundary--\r\n';

      final fileBytes = await file.readAsBytes();
      request.write(header);
      request.add(fileBytes);
      request.write(footer);

      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        return data['is_ai'] == true;
      } else {
        _showConnectionWarning(
            'Server returned status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('AI detector error: $e');
      _showConnectionWarning(
          'Could not connect to AI detector server. Please check your backend.');
    }
    return false;
  }

  void _showConnectionWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.orange.shade800,
      duration: const Duration(seconds: 4),
    ));
  }

  // ── AI error dialog ──────────────────────────────────────────────────────
  void _showAiError(int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration:
                BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
            child: Icon(Icons.smart_toy_rounded,
                color: Colors.red.shade400, size: 44),
          ),
          const SizedBox(height: 12),
          const Text('AI-Generated Image Detected',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
          'This image appears to be AI-generated.\n\n'
          'Please upload a real photograph of your property to maintain trust with guests.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
        ),
        actions: [
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.photo_library_outlined,
                  color: AppColors.darkTeal),
              label: const Text('Choose Another',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.darkTeal)),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  newImages[index]  = null;
                  _aiFlags[index]   = null;
                });
                pickImage(index);
              },
            ),
          ),
          Center(
            child: TextButton(
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.black38)),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  newImages[index]  = null;
                  _aiFlags[index]   = null;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Save updated property ────────────────────────────────────────────────
  Future<void> saveProperty() async {
    if (roomNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Listing name is required'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    for (int i = 0; i < newImages.length; i++) {
      if (newImages[i] != null && _aiFlags[i] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Image ${i + 1} was flagged as AI-generated. Please replace it.'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    if (_checking.any((c) => c)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please wait while your images are being verified…')));
      return;
    }

    setState(() => loading = true);
    try {
      for (int i = 0; i < 3; i++) {
        if (newImages[i] != null) {
          final fileName =
              'property_${widget.propertyId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          await supabase.storage
              .from('property_images')
              .uploadBinary(fileName, await newImages[i]!.readAsBytes());
          imageUrls[i] = supabase.storage
              .from('property_images')
              .getPublicUrl(fileName);
        }
      }

      await supabase
          .from('properties')
          .update({
            'room_name':        roomNameCtrl.text.trim(),
            'location':         locationCtrl.text.trim(),
            'price_per_night':  double.tryParse(priceCtrl.text.trim()) ?? 0,
            'discount':         double.tryParse(discountCtrl.text.trim()) ?? 0,
            'facilities':       facilitiesCtrl.text.trim(),
            'description':      descriptionCtrl.text.trim(),
            'property_type':    _propertyType,
            'guest_preference': _guestPreference,
            'bedrooms':         int.tryParse(bedroomsCtrl.text.trim()) ?? 1,
            'bathrooms':        int.tryParse(bathroomsCtrl.text.trim()) ?? 1,
            'max_guests':       int.tryParse(maxGuestsCtrl.text.trim()) ?? 1,
            'image1_url':       imageUrls[0],
            'image2_url':       imageUrls[1],
            'image3_url':       imageUrls[2],
          })
          .eq('id', widget.propertyId);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Property updated successfully ✅'),
        backgroundColor: AppColors.darkTeal,
      ));

      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error updating property: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => loading = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: CustomScrollView(
        slivers: [
          // ── Hero AppBar ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.darkTeal,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              title: const Text(
                'Edit Listing',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F4C5C), Color(0xFF26C6DA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(children: [
                  Positioned(
                    right: -30,
                    top: -20,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.06),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 40,
                    bottom: 20,
                    child: Icon(Icons.edit_note_rounded,
                        size: 60, color: Colors.white.withOpacity(0.12)),
                  ),
                ]),
              ),
            ),
          ),

          loading
              ? const SliverFillRemaining(
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.darkTeal)))
              : SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Photos ───────────────────────────────────────
                        _sectionCard(
                          icon: Icons.photo_library_rounded,
                          title: 'Property Photos',
                          subtitle:
                              'Tap to replace a photo · AI images rejected automatically',
                          child: Column(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(children: [
                                Icon(Icons.shield_rounded,
                                    color: Colors.amber.shade700, size: 18),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'New images are automatically scanned for AI generation.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF8D6E00),
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 14),
                            Row(
                                children: [0, 1, 2]
                                    .map((i) => _imageBox(i))
                                    .toList()),
                          ]),
                        ),

                        const SizedBox(height: 16),

                        // ── Property Type ────────────────────────────────
                        _sectionCard(
                          icon: Icons.category_rounded,
                          title: 'Property Type',
                          subtitle: 'What kind of space are you listing?',
                          child: _chipSelector(
                            items: _propertyTypes,
                            icons: _typeIcons,
                            selected: _propertyType,
                            onSelect: (v) =>
                                setState(() => _propertyType = v),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Guest Preference ─────────────────────────────
                        _sectionCard(
                          icon: Icons.group_rounded,
                          title: 'Suitable For',
                          subtitle: 'Who is this property open to?',
                          child: _chipSelector(
                            items: _guestPreferences,
                            icons: _prefIcons,
                            selected: _guestPreference,
                            onSelect: (v) =>
                                setState(() => _guestPreference = v),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Room Details ─────────────────────────────────
                        _sectionCard(
                          icon: Icons.bed_rounded,
                          title: 'Room Details',
                          subtitle:
                              'Bedrooms, bathrooms & guest capacity',
                          child: Row(children: [
                            Expanded(
                                child: _compactField('Bedrooms',
                                    bedroomsCtrl, Icons.bed_rounded)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _compactField('Bathrooms',
                                    bathroomsCtrl, Icons.bathtub_rounded)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _compactField('Max Guests',
                                    maxGuestsCtrl, Icons.people_rounded)),
                          ]),
                        ),

                        const SizedBox(height: 16),

                        // ── Pricing ──────────────────────────────────────
                        _sectionCard(
                          icon: Icons.payments_rounded,
                          title: 'Pricing',
                          subtitle:
                              'Update your nightly rate and discount',
                          child: Column(children: [
                            _inputField('Price per Stay (PKR)', priceCtrl,
                                icon: Icons.money_rounded,
                                keyboard: TextInputType.number),
                            _inputField(
                                'Active Discount (%)', discountCtrl,
                                icon: Icons.percent_rounded,
                                keyboard: TextInputType.number,
                                bottomPad: 0),
                          ]),
                        ),

                        const SizedBox(height: 16),

                        // ── Location & Details ───────────────────────────
                        _sectionCard(
                          icon: Icons.location_on_rounded,
                          title: 'Location & Details',
                          subtitle:
                              'Update your address and property details',
                          child: Column(children: [
                            _inputField('Listing Name', roomNameCtrl,
                                icon: Icons.badge_rounded),
                            _inputField('Full Location / Address',
                                locationCtrl,
                                icon: Icons.location_on_rounded),
                            _inputField(
                                'Facilities & Perks', facilitiesCtrl,
                                icon:
                                    Icons.home_repair_service_rounded),
                            _inputField('Full Description',
                                descriptionCtrl,
                                icon: Icons.description_rounded,
                                maxLines: 4,
                                bottomPad: 0),
                          ]),
                        ),

                        const SizedBox(height: 28),

                        // ── Save Button ──────────────────────────────────
                        GradientButton(
                          text: 'Save & Update',
                          icon: Icons.save_rounded,
                          onPressed: saveProperty,
                          height: 56,
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

  // ── UI Helpers ───────────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
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
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.darkTeal, AppColors.lightTeal]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkTeal)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black38)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _chipSelector({
    required List<String> items,
    required Map<String, IconData> icons,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        final isSelected = item == selected;
        return GestureDetector(
          onTap: () => onSelect(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [AppColors.darkTeal, AppColors.lightTeal])
                  : null,
              color: isSelected ? null : const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : Colors.grey.shade300),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: AppColors.darkTeal.withOpacity(0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icons[item],
                    size: 16,
                    color: isSelected ? Colors.white : Colors.black54),
                const SizedBox(width: 6),
                Text(item,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.black54)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _imageBox(int index) {
    final isChecking = _checking[index];
    final isAi       = _aiFlags[index] == true;
    final hasNew      = newImages[index] != null;
    final hasExisting = imageUrls[index] != null;
    final hasAny      = hasNew || hasExisting;

    Color borderColor = hasAny && !isChecking
        ? (isAi ? Colors.red.shade400 : AppColors.lightTeal)
        : Colors.grey.shade200;

    return Expanded(
      child: Stack(
        children: [
          GestureDetector(
            onTap: isChecking ? null : () => pickImage(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 115,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor, width: 1.8),
                image: hasNew
                    ? DecorationImage(
                        image: FileImage(newImages[index]!),
                        fit: BoxFit.cover)
                    : hasExisting
                        ? DecorationImage(
                            image: NetworkImage(imageUrls[index]!),
                            fit: BoxFit.cover)
                        : null,
              ),
              child: (!hasNew && !hasExisting)
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.darkTeal.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add_photo_alternate_rounded,
                              color: AppColors.darkTeal, size: 24),
                        ),
                        const SizedBox(height: 6),
                        const Text('Add Photo',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.darkTeal,
                                fontWeight: FontWeight.w600)),
                      ],
                    )
                  : null,
            ),
          ),

          // Scanning overlay
          if (isChecking)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: Colors.black.withOpacity(0.5),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5)),
                      SizedBox(height: 6),
                      Text('Scanning…',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),

          // AI badge
          if (hasNew && !isChecking && isAi)
            Positioned(
                top: 6,
                left: 8,
                child: _badge('AI', Colors.red.shade600, Icons.smart_toy_rounded)),

          // Real badge
          if (hasNew && !isChecking && _aiFlags[index] == false)
            Positioned(
                top: 6,
                left: 8,
                child: _badge(
                    'Real', Colors.green.shade600, Icons.verified_rounded)),

          // Remove button
          if (hasAny && !isChecking)
            Positioned(
              top: 6,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    imageUrls[index]  = null;
                    newImages[index]  = null;
                    _aiFlags[index]   = null;
                  });
                },
                child: Container(
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(4),
                  child:
                      const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 11),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _inputField(
    String hint,
    TextEditingController ctrl, {
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    double bottomPad = 16,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.black87, fontSize: 15),
        decoration:
            CustomInputDecoration.getDecoration(hint, prefixIcon: icon),
      ),
    );
  }

  Widget _compactField(
      String label, TextEditingController ctrl, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.black45,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.darkTeal),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.darkTeal, size: 18),
            filled: true,
            fillColor: const Color(0xFFF0F4F8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: AppColors.lightTeal, width: 1.5)),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          ),
        ),
      ],
    );
  }
}
