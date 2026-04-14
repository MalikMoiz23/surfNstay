import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_theme.dart';
import 'page_transition.dart';

class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key});

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  final TextEditingController rentCtrl = TextEditingController();
  final TextEditingController discountCtrl = TextEditingController();
  final TextEditingController locationCtrl = TextEditingController();
  final TextEditingController facilitiesCtrl = TextEditingController();
  final TextEditingController descriptionCtrl = TextEditingController();

  List<File?> images = [null, null, null];
  bool loading = false;

  final supabase = Supabase.instance.client;

  final picker = ImagePicker();

  Future<void> pickImage(int index) async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => images[index] = File(picked.path));
    }
  }

  void _showMessage(String msg, {bool success = false}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Icon(
          success ? Icons.check_circle_rounded : Icons.error_rounded,
          color: success ? AppColors.darkTeal : Colors.red,
          size: 50,
        ),
        content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        actions: [
          Center(
            child: TextButton(
              child: const Text("Continue", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkTeal)),
              onPressed: () {
                Navigator.pop(context);
                if (success) Navigator.pop(context);
              },
            ),
          )
        ],
      ),
    );
  }

  Future<void> submitProperty() async {
    if (rentCtrl.text.isEmpty || locationCtrl.text.isEmpty) {
      _showMessage("Rent and location are required");
      return;
    }

    setState(() => loading = true);

    try {
      List<String?> imageUrls = [null, null, null];

      for (int i = 0; i < images.length; i++) {
        if (images[i] != null) {
          final bytes = await images[i]!.readAsBytes();
          final fileName = 'property_${DateTime.now().millisecondsSinceEpoch}_$i.png';
          await supabase.storage.from('property_images').uploadBinary(fileName, bytes);
          final urlResponse = supabase.storage.from('property_images').getPublicUrl(fileName);
          imageUrls[i] = urlResponse;
        }
      }

      await supabase.from('properties').insert({
        'image1_url': imageUrls[0],
        'image2_url': imageUrls[1],
        'image3_url': imageUrls[2],
        'price_per_night': double.tryParse(rentCtrl.text),
        'discount': double.tryParse(discountCtrl.text) ?? 0,
        'location': locationCtrl.text.trim(),
        'facilities': facilitiesCtrl.text.trim(),
        'description': descriptionCtrl.text.trim(),
        'host_id': supabase.auth.currentUser!.id,
        'created_at': DateTime.now().toIso8601String(),
      });

      setState(() => loading = false);
      _showMessage("Your property is now live!", success: true);
    } catch (e) {
      setState(() => loading = false);
      _showMessage("Failed to add property: $e");
    }
  }

  Widget imagePickerTile(int index) {
    return Expanded(
      child: GestureDetector(
        onTap: () => pickImage(index),
        child: Container(
          height: 120,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: images[index] == null ? Colors.grey.shade300 : AppColors.lightTeal,
              width: 1.5,
              style: images[index] == null ? BorderStyle.solid : BorderStyle.solid,
            ),
            boxShadow: [
              if (images[index] != null)
                BoxShadow(
                  color: AppColors.lightTeal.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
            ],
          ),
          child: images[index] == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade400, size: 30),
                    const SizedBox(height: 4),
                    Text("Add Image", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  ],
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(images[index]!, fit: BoxFit.cover),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("New Property", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.darkTeal,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Property Showcase",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal),
            ),
            const SizedBox(height: 4),
            const Text("Upload up to 3 high-quality photos.", style: TextStyle(color: Colors.black45, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: List.generate(3, (index) => imagePickerTile(index)),
            ),
            const SizedBox(height: 32),
            const Text(
              "Stay Details",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal),
            ),
            const SizedBox(height: 16),
            _inputField("Per Night Rent (PKR)", rentCtrl, icon: Icons.money_rounded, keyboard: TextInputType.number),
            _inputField("Discount (%)", discountCtrl, icon: Icons.percent_rounded, keyboard: TextInputType.number),
            _inputField("Full Location", locationCtrl, icon: Icons.location_on_rounded),
            _inputField("Amenities / Facilities", facilitiesCtrl, icon: Icons.home_repair_service_rounded),
            _inputField("Description", descriptionCtrl, icon: Icons.description_rounded, maxLines: 4),
            const SizedBox(height: 16),
            GradientButton(
              text: "Publish Property",
              onPressed: submitProperty,
              loading: loading,
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _inputField(String hint, TextEditingController ctrl,
      {required IconData icon, TextInputType keyboard = TextInputType.text, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.black87, fontSize: 15),
        decoration: CustomInputDecoration.getDecoration(hint, prefixIcon: icon),
      ),
    );
  }
}