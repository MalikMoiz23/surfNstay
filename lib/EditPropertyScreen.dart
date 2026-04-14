import 'dart:io';
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

  final TextEditingController locationCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController discountCtrl = TextEditingController();
  final TextEditingController facilitiesCtrl = TextEditingController();
  final TextEditingController descriptionCtrl = TextEditingController();

  List<String?> imageUrls = [null, null, null]; // old images
  List<File?> newImages = [null, null, null];   // newly picked images

  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchProperty();
  }

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
          const SnackBar(content: Text("Property not found")),
        );
        Navigator.pop(context);
        return;
      }

      setState(() {
        locationCtrl.text = response['location'] ?? "";
        priceCtrl.text = response['price_per_night']?.toString() ?? "";
        discountCtrl.text = response['discount']?.toString() ?? "";
        facilitiesCtrl.text = response['facilities'] ?? "";
        descriptionCtrl.text = response['description'] ?? "";

        imageUrls[0] = response['image1_url'];
        imageUrls[1] = response['image2_url'];
        imageUrls[2] = response['image3_url'];
      });
    } catch (e) {
      print("Error fetching property: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching property: $e")));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> pickImage(int index) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      newImages[index] = File(picked.path);
    });
  }

  Future<void> saveProperty() async {
    setState(() => loading = true);
    try {
      for (int i = 0; i < 3; i++) {
        if (newImages[i] != null) {
          final fileName =
              "property_${widget.propertyId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
          await supabase.storage.from('property_images').uploadBinary(fileName, await newImages[i]!.readAsBytes());
          final url = supabase.storage.from('property_images').getPublicUrl(fileName);
          imageUrls[i] = url;
        }
      }

      await supabase.from('properties').update({
        'location': locationCtrl.text.trim(),
        'price_per_night': double.tryParse(priceCtrl.text.trim()) ?? 0,
        'discount': double.tryParse(discountCtrl.text.trim()) ?? 0,
        'facilities': facilitiesCtrl.text.trim(),
        'description': descriptionCtrl.text.trim(),
        'image1_url': imageUrls[0],
        'image2_url': imageUrls[1],
        'image3_url': imageUrls[2],
      }).eq('id', widget.propertyId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Property updated successfully"), backgroundColor: AppColors.darkTeal),
      );

      Navigator.pop(context);
    } catch (e) {
      print("Error updating property: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => loading = false);
    }
  }

  Widget imageBox(int index) {
    return Expanded(
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => pickImage(index),
            child: Container(
              height: 120,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (newImages[index] == null && imageUrls[index] == null) 
                      ? Colors.grey.shade300 
                      : AppColors.lightTeal,
                  width: 1.5,
                ),
                image: newImages[index] != null
                    ? DecorationImage(image: FileImage(newImages[index]!), fit: BoxFit.cover)
                    : imageUrls[index] != null
                    ? DecorationImage(image: NetworkImage(imageUrls[index]!), fit: BoxFit.cover)
                    : null,
              ),
              child: (newImages[index] == null && imageUrls[index] == null)
                  ? const Center(child: Icon(Icons.add_a_photo, color: Colors.black26))
                  : null,
            ),
          ),
          if (imageUrls[index] != null || newImages[index] != null)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    imageUrls[index] = null;
                    newImages[index] = null;
                  });
                },
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Edit Listing", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.darkTeal,
        elevation: 0,
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.darkTeal))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Property Gallery",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal),
            ),
            const SizedBox(height: 16),
            Row(children: [0, 1, 2].map((i) => imageBox(i)).toList()),

            const SizedBox(height: 32),
            const Text(
              "Update Information",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal),
            ),
            const SizedBox(height: 16),
            _inputField("Location", locationCtrl, icon: Icons.location_on_rounded),
            _inputField("Price per Stay (PKR)", priceCtrl, icon: Icons.money_rounded, keyboard: TextInputType.number),
            _inputField("Active Discount (%)", discountCtrl, icon: Icons.percent_rounded, keyboard: TextInputType.number),
            _inputField("Facilities & Perks", facilitiesCtrl, icon: Icons.home_repair_service_rounded),
            _inputField("Full Description", descriptionCtrl, icon: Icons.description_rounded, maxLines: 4),

            const SizedBox(height: 20),
            GradientButton(
              text: "Save & Update",
              onPressed: saveProperty,
            ),
            const SizedBox(height: 40),
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