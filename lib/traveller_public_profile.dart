import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'page_transition.dart';
import 'ChatScreen.dart';

class TravellerPublicProfilePage extends StatefulWidget {
  final String travellerId;

  const TravellerPublicProfilePage({super.key, required this.travellerId});

  @override
  State<TravellerPublicProfilePage> createState() => _TravellerPublicProfilePageState();
}

class _TravellerPublicProfilePageState extends State<TravellerPublicProfilePage> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  bool loadingChat = false;

  Map<String, dynamic>? travellerData;
  int completedBookings = 0;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => loading = true);
    try {
      // 1. Fetch Traveller Data
      final res = await supabase
          .from('travellers')
          .select()
          .eq('id', widget.travellerId)
          .maybeSingle();
      
      travellerData = res;

      // 2. Fetch Stats (Completed Bookings)
      final resBookings = await supabase
          .from('bookings')
          .select('id')
          .eq('traveller_id', widget.travellerId)
          .eq('status', 'confirmed');
      
      completedBookings = (resBookings as List).length;

    } catch (e) {
      debugPrint("Error fetching traveller profile: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openChat() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    if (currentUser.id == widget.travellerId) return;

    setState(() => loadingChat = true);
    try {
      // Check for existing chat
      final response = await supabase
          .from('chats')
          .select()
          .or('and(user1_id.eq.${currentUser.id},user2_id.eq.${widget.travellerId}),and(user1_id.eq.${widget.travellerId},user2_id.eq.${currentUser.id})')
          .maybeSingle();

      String chatId;
      if (response != null) {
        chatId = response['id'];
      } else {
        // Create new chat
        final ins = await supabase.from('chats').insert({
          'user1_id': currentUser.id,
          'user2_id': widget.travellerId,
        }).select().single();
        chatId = ins['id'];
      }

      if (!mounted) return;
      Navigator.push(
        context,
        CustomPageRoute(
          child: ChatScreen(
            chatId: chatId, 
            receiverId: widget.travellerId, 
            receiverName: travellerData?['name'] ?? "Traveller",
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Chat error: $e")));
    } finally {
      if (mounted) setState(() => loadingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.darkTeal)),
      );
    }

    if (travellerData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Profile")),
        body: const Center(child: Text("Traveller not found")),
      );
    }

    final String name = travellerData!['name'] ?? "Traveller";
    final String pic = travellerData!['profile_pic'] ?? "";
    final DateTime createdAt = DateTime.tryParse(travellerData!['created_at'] ?? "") ?? DateTime.now();
    final String joinedDate = DateFormat('MMMM yyyy').format(createdAt);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Traveller Profile"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: AppColors.primaryGradient),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15)],
                    ),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white,
                      backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                      child: pic.isEmpty 
                        ? const Icon(Icons.person, size: 60, color: AppColors.darkTeal) 
                        : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const Text(
                    "Verified Traveller",
                    style: TextStyle(color: AppColors.darkTeal, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Message Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                onPressed: loadingChat ? null : _openChat,
                icon: loadingChat 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.message_rounded),
                label: const Text("Message Traveller", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 32),

            // Stats row
            Row(
              children: [
                _statBox("Recent Stays", completedBookings.toString(), Icons.hotel_outlined),
                const SizedBox(width: 16),
                _statBox("Member Since", joinedDate.split(' ')[1], Icons.calendar_today_outlined),
              ],
            ),

            const SizedBox(height: 24),

            // Details Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Contact Information", 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal)),
                  const SizedBox(height: 20),
                  _detailRow(Icons.email_outlined, "Email", travellerData!['email'] ?? "Not shared"),
                  const Divider(height: 32),
                  _detailRow(Icons.phone_outlined, "Phone", travellerData!['phone'] ?? "Not shared"),
                  const Divider(height: 32),
                  _detailRow(Icons.location_on_outlined, "Home Base", travellerData!['address'] ?? "Not shared"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.lightTeal, size: 24),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.lightTeal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.darkTeal, size: 20),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87)),
          ],
        ),
      ],
    );
  }
}
