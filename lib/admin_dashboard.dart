import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'page_transition.dart';
import 'host_public_profile.dart';
import 'traveller_public_profile.dart';
import 'login_screen.dart'; // ✅ added

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final supabase = Supabase.instance.client;
  bool loading = true;

  List<Map<String, dynamic>> hosts = [];
  List<Map<String, dynamic>> travellers = [];
  List<Map<String, dynamic>> reports = [];
  
  String userSearchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    setState(() => loading = true);
    try {
      // 1. Fetch Hosts
      final hostRes = await supabase.from('hosts').select().order('fullName');
      hosts = List<Map<String, dynamic>>.from(hostRes);

      // 2. Fetch Travellers
      final travellerRes = await supabase.from('travellers').select().order('name');
      travellers = List<Map<String, dynamic>>.from(travellerRes);

      // 3. Fetch Reports (Using the new Virtual View)
      final reportRes = await supabase
          .from('admin_report_view')
          .select()
          .order('created_at', ascending: false);
      
      reports = List<Map<String, dynamic>>.from(reportRes);

    } catch (e) {
      debugPrint("Admin Dashboard Data Fetch Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Database Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Admin Console', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(onPressed: _fetchAllData, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () {
              // ✅ Correct Logout navigation
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(width: 4.0, color: Colors.white),
            insets: EdgeInsets.symmetric(horizontal: 40.0),
          ),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_rounded), text: "Community"),
            Tab(icon: Icon(Icons.report_gmailerrorred_rounded), text: "Reports"),
          ],
        ),
      ),
      body: loading 
        ? const Center(child: CircularProgressIndicator(color: AppColors.darkTeal))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildUsersTab(),
              _buildReportsTab(),
            ],
          ),
    );
  }

  // ── Community Tab ──────────────────────────────────────────────

  Widget _buildUsersTab() {
    final filteredHosts = hosts.where((h) => 
      (h['fullName'] ?? "").toLowerCase().contains(userSearchQuery.toLowerCase()) ||
      (h['email'] ?? "").toLowerCase().contains(userSearchQuery.toLowerCase())).toList();

    final filteredTravellers = travellers.where((t) => 
      (t['name'] ?? "").toLowerCase().contains(userSearchQuery.toLowerCase()) ||
      (t['email'] ?? "").toLowerCase().contains(userSearchQuery.toLowerCase())).toList();

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (val) => setState(() => userSearchQuery = val),
            decoration: InputDecoration(
              hintText: "Search name or email...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _sectionHeader("Hosts (${filteredHosts.length})"),
              ...filteredHosts.map((h) => _userCard(
                name: h['fullName'] ?? "Host",
                email: h['email'] ?? "No email",
                image: h['profile_pic'] ?? "",
                role: "Host",
                userId: h['id'],
              )),
              const SizedBox(height: 24),
              _sectionHeader("Travellers (${filteredTravellers.length})"),
              ...filteredTravellers.map((t) => _userCard(
                name: t['name'] ?? "Traveller",
                email: t['email'] ?? "No email",
                image: t['profile_pic'] ?? "",
                role: "Traveller",
                userId: t['id'],
              )),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal)),
    );
  }

  Widget _userCard({required String name, required String email, required String image, required String role, required String userId}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: Colors.grey[200],
          backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
          child: image.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(email, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: role == "Host" ? Colors.blue.withOpacity(0.1) : Colors.teal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(role.toUpperCase(), style: TextStyle(
            color: role == "Host" ? Colors.blue[800] : Colors.teal[800],
            fontSize: 10, 
            fontWeight: FontWeight.bold
          )),
        ),
        onTap: () {
          if (role == "Host") {
            Navigator.push(context, CustomPageRoute(child: HostPublicProfilePage(hostId: userId)));
          } else {
            Navigator.push(context, CustomPageRoute(child: TravellerPublicProfilePage(travellerId: userId)));
          }
        },
      ),
    );
  }

  // ── Reports Tab ────────────────────────────────────────────────

  Widget _buildReportsTab() {
    if (reports.isEmpty) {
      return const Center(child: Text("No reports logged yet.", style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final r = reports[index];
        final type = r['report_type'] ?? "room";
        
        // Data derived directly from the SQL View
        final reporterName = r['reporter_name'] ?? "A User";
        final targetName = r['target_display_name'] ?? "Unknown";
        
        final String bookingInfo = (r['start_date'] != null) 
            ? "${r['start_date']} to ${r['end_date']}"
            : "No booking data";

        final time = DateFormat('MMM dd, yyyy').format(DateTime.parse(r['created_at']));
        
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: type == "traveller" ? Colors.orange.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        type == "traveller" ? "REPORT AGAINST GUEST" : "REPORT AGAINST ROOM",
                        style: TextStyle(
                          color: type == "traveller" ? Colors.orange[800] : Colors.red[800],
                          fontSize: 10,
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ),
                    Text(time, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Reporter Box
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        final id = r['reporter_id'];
                        final role = r['reporter_role'];
                        if (id != null) {
                          if (role == 'host') {
                            Navigator.push(context, CustomPageRoute(child: HostPublicProfilePage(hostId: id)));
                          } else {
                            Navigator.push(context, CustomPageRoute(child: TravellerPublicProfilePage(travellerId: id)));
                          }
                        }
                      },
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black54, fontSize: 13),
                          children: [
                            const TextSpan(text: "Reported by "),
                            TextSpan(
                                text: reporterName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkTeal,
                                    decoration: TextDecoration.underline)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Target Box
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.gavel_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (type == 'traveller') {
                            final id = r['reported_user_id'];
                            if (id != null) {
                              Navigator.push(context, CustomPageRoute(child: TravellerPublicProfilePage(travellerId: id)));
                            }
                          } else {
                            final id = r['room_host_id'];
                            if (id != null) {
                              Navigator.push(context, CustomPageRoute(child: HostPublicProfilePage(hostId: id)));
                            }
                          }
                        },
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(color: Colors.black54, fontSize: 13),
                            children: [
                              const TextSpan(text: "Action Against "),
                              TextSpan(
                                  text: targetName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.redAccent,
                                      decoration: TextDecoration.underline)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const Divider(),
                const SizedBox(height: 12),

                // Reason & Details
                Text(
                  r['reason'] ?? "Generic Issue",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal),
                ),
                const SizedBox(height: 8),
                Text(
                  r['details'] ?? "No description provided.",
                  style: TextStyle(color: Colors.grey[700], fontSize: 14, height: 1.4),
                ),

                const SizedBox(height: 20),
                
                // Booking Metadata
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available, size: 18, color: AppColors.darkTeal),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Booking Period", style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(bookingInfo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                Row(
                  children: [
                    const Icon(Icons.history, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    const Text("Audit Trail Logged", style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Resolution features coming soon!")));
                      },
                      child: const Text("Resolve Issue"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}
