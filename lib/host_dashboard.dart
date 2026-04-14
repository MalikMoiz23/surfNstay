import 'package:flutter/material.dart';
import 'AddPropertyScreen.dart';
import 'EditPropertyScreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'NotificationScreen.dart';
import 'package:badges/badges.dart' as badges;
import 'messages_page.dart';
import 'app_theme.dart';
import 'page_transition.dart';
import 'package:intl/intl.dart';
import 'host_profile_page.dart';

class HostDashboard extends StatefulWidget {
  const HostDashboard({super.key});

  @override
  State<HostDashboard> createState() => _HostDashboardState();
}

class _HostDashboardState extends State<HostDashboard> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> properties = [];
  bool loading = true;
  int _selectedIndex = 0;

  String hostName = "Loading...";
  String? profileImage; // Network URL or null

  static const List<Color> primaryGradientColors = AppColors.primaryGradient;

  late final Stream<List<Map<String, dynamic>>> _notificationsStream;
  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  @override
  void initState() {
    super.initState();
    final user = supabase.auth.currentUser;
    if (user != null) {
      _notificationsStream = supabase.from('notifications').stream(primaryKey: ['id']).eq('user_id', user.id).map((events) => events.where((e) => e['is_read'] == false).toList());
      _messagesStream = supabase.from('messages').stream(primaryKey: ['id']).eq('receiver_id', user.id).map((events) => events.where((e) => e['is_read'] == false).toList());
    } else {
      _notificationsStream = const Stream.empty();
      _messagesStream = const Stream.empty();
    }
    fetchHostInfo();
    fetchProperties();
  }

  Future<void> fetchHostInfo() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Try fetching both. If it fails (e.g. column doesn't exist), try just name.
      try {
        final response = await supabase
            .from('hosts')
            .select('fullName, profile_pic')
            .eq('id', user.id)
            .maybeSingle();

        if (response != null) {
          setState(() {
            hostName = response['fullName'] ?? "Host";
            profileImage = response['profile_pic'];
          });
          return;
        }
      } catch (e) {
        // Fallback for missing profile_pic column
        final response = await supabase
            .from('hosts')
            .select('fullName')
            .eq('id', user.id)
            .maybeSingle();

        if (response != null) {
          setState(() {
            hostName = response['fullName'] ?? "Host";
            profileImage = null;
          });
          return;
        }
      }
      
      // If no response at all
      setState(() => hostName = "Host");
      
    } catch (e) {
      print("Error fetching host info: $e");
      setState(() => hostName = "Host");
    }
  }

  Future<void> fetchProperties() async {
    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('properties')
          .select()
          .eq('host_id', user.id)
          .order('created_at', ascending: false);

      properties = response.map<Map<String, dynamic>>((p) {
        List<String> imgs = [];
        if (p['image1_url'] != null && p['image1_url'] != "") imgs.add(p['image1_url']);
        if (p['image2_url'] != null && p['image2_url'] != "") imgs.add(p['image2_url']);
        if (p['image3_url'] != null && p['image3_url'] != "") imgs.add(p['image3_url']);

        return {
          "id": p['id'].toString(), // property id
          "images": imgs,
          "price_per_night": p['price_per_night'],
          "facilities": p['facilities'] ?? "",
          "location": p['location'] ?? "",
          "description": p['description'] ?? "",
        };
      }).toList();

      setState(() => loading = false);
    } catch (e) {
      print("Error fetching properties: $e");
      setState(() => loading = false);
    }
  }

  void _onNavTapped(int index) {
    if (index == 1) {
      Navigator.pushReplacement(
        context,
        CustomPageRoute(child: const MessagesPage(isHost: true)),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        CustomPageRoute(child: const HostProfilePage()),
      );
    } else {
      setState(() => _selectedIndex = index);
    }
  }

  Widget propertyCard(Map<String, dynamic> prop) {
    List images = prop["images"];
    String propertyId = prop["id"]; // pass to edit screen

    final priceValue = prop["price_per_night"];
    String price = priceValue != null ? "PKR ${priceValue.toString()} / night" : "Price not available";

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 160,
            child: images.isEmpty
                ? const Center(child: Text("No Image"))
                : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              itemBuilder: (context, i) {
                return Container(
                  width: 180,
                  margin: const EdgeInsets.all(6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      images[i],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(child: Icon(Icons.broken_image, size: 50));
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(price, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(prop["location"], style: const TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 4),
                Text(prop["facilities"], style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, color: AppColors.darkTeal),
                      onPressed: () {
                        Navigator.push(
                          context,
                          CustomPageRoute(
                            child: EditPropertyScreen(propertyId: propertyId),
                          ),
                        ).then((_) => fetchProperties());
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                      onPressed: () => _safeDeleteProperty(propertyId),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _safeDeleteProperty(String propertyId) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      // Check for active/future bookings
      final bookings = await supabase
          .from('bookings')
          .select('id')
          .eq('property_id', propertyId)
          .gte('end_date', today)
          .neq('status', 'cancelled');

      if (bookings.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Cannot delete! This property has active or future bookings."),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Show confirmation dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Delete Property?"),
            content: const Text("Are you sure you want to remove this property? This action cannot be undone."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  setState(() => loading = true);
                  await supabase.from('properties').delete().eq('id', propertyId);
                  await fetchProperties();
                },
                child: const Text("Delete", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error checking bookings: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget addPropertyButton(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: GradientButton(
        text: text,
        onPressed: () {
          Navigator.push(
            context,
            CustomPageRoute(child: const AddPropertyScreen()),
          ).then((_) => fetchProperties());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.lightTeal.withOpacity(0.2),
              backgroundImage: (profileImage != null && profileImage!.isNotEmpty)
                  ? NetworkImage(profileImage!)
                  : null,
              child: (profileImage == null || profileImage!.isEmpty)
                  ? const Icon(Icons.person, color: AppColors.darkTeal, size: 28)
                  : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Welcome", style: TextStyle(fontSize: 13, color: Colors.black54)),
                Text(hostName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              ],
            ),
          ],
        ),
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _notificationsStream,
            builder: (context, notifSnapshot) {
              bool hasNotif = notifSnapshot.hasData && notifSnapshot.data!.isNotEmpty;
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _messagesStream,
                builder: (context, msgSnapshot) {
                  bool hasMsg = msgSnapshot.hasData && msgSnapshot.data!.isNotEmpty;
                  bool hasUnread = hasNotif || hasMsg;

                  return badges.Badge(
                    showBadge: hasUnread,
                    position: badges.BadgePosition.topEnd(top: 10, end: 10),
                    child: IconButton(
                      icon: const Icon(Icons.notifications, color: Colors.black54),
                      onPressed: () {
                        Navigator.push(
                          context,
                          CustomPageRoute(child: const NotificationScreen()),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : properties.isEmpty
          ? addPropertyButton("+ Add Your First Property")
          : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: ListView.builder(
          itemCount: properties.length + 1,
          itemBuilder: (context, index) {
            if (index < properties.length) {
              return propertyCard(properties[index]);
            }
            return addPropertyButton("+ Add New Property");
          },
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
        selectedItemColor: const Color(0xFF28AFC1),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: "Messages"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}