import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'page_transition.dart';
import 'host_public_profile.dart';
import 'traveller_public_profile.dart';
import 'auth_gate.dart';

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
  List<Map<String, dynamic>> auditLog = [];

  String userSearchQuery = "";

  /// Reports tab filter: open | resolved | dismissed | all
  String reportFilter = 'open';

  /// Hosts awaiting CNIC review (B8).
  List<Map<String, dynamic>> get pendingVerifications =>
      hosts.where((h) => h['verification_status'] == 'pending').toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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

      // 4. Audit trail. The Reports tab used to display "Audit Trail Logged"
      //    while nothing was ever written anywhere.
      try {
        final auditRes = await supabase
            .from('admin_actions')
            .select()
            .order('created_at', ascending: false)
            .limit(200);
        auditLog = List<Map<String, dynamic>>.from(auditRes);
      } catch (e) {
        debugPrint('Audit log unavailable (run sql/surfnstay_setup.sql): $e');
        auditLog = [];
      }
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

  bool _isHostBlocked(String hostId) {
    final host = hosts.firstWhere((h) => h['id'] == hostId, orElse: () => {});
    return host['is_blocked'] == true;
  }

  bool _isTravellerBlocked(String travellerId) {
    final traveller = travellers.firstWhere((t) => t['id'] == travellerId, orElse: () => {});
    return traveller['is_blocked'] == true;
  }

  Future<void> _toggleBlockUser({
    required String userId,
    required String role,
    required bool block,
  }) async {
    setState(() => loading = true);
    try {
      // Goes through the RPC rather than a direct table update so the action
      // lands in admin_actions.
      await supabase.rpc('admin_set_user_blocked', params: {
        'p_user_id': userId,
        'p_role': role.toLowerCase(),
        'p_blocked': block,
        'p_reason': null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${role.toUpperCase()} has been ${block ? 'blocked' : 'unblocked'} successfully!'),
          backgroundColor: block ? Colors.red : Colors.green,
        ),
      );
      await _fetchAllData();
    } catch (e) {
      debugPrint("Admin Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
      setState(() => loading = false);
    }
  }

  // ── Report resolution (B9) ───────────────────────────────────────────────

  Future<void> _resolveReport(Map<String, dynamic> report) async {
    final noteCtrl = TextEditingController(
        text: report['resolution_note']?.toString() ?? '');
    String status = 'resolved';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Close this report'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final s in ['resolved', 'dismissed'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s == 'resolved' ? 'Resolved' : 'Dismissed'),
                        selected: status == s,
                        onSelected: (_) => setDialog(() => status = s),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'What action was taken? (recorded in the audit log)',
                  hintStyle: const TextStyle(fontSize: 12.5),
                  filled: true,
                  fillColor: const Color(0xFFF5F7FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkTeal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.rpc('admin_resolve_report', params: {
        'p_report_id': report['id'].toString(),
        'p_status': status,
        'p_note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      });
      await _fetchAllData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Report marked $status'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _setPropertyActive(String propertyId, bool active) async {
    try {
      await supabase.rpc('admin_set_property_active', params: {
        'p_property_id': propertyId,
        'p_active': active,
        'p_reason': active ? 'Restored by admin' : 'Taken down after report',
      });
      await _fetchAllData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(active ? 'Listing restored' : 'Listing taken down'),
          backgroundColor: active ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── Host verification review (B8) ────────────────────────────────────────

  Future<void> _reviewVerification(
      Map<String, dynamic> host, bool approve) async {
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(approve ? 'Approve verification' : 'Reject verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              approve
                  ? 'This host will get a Verified badge on all their listings.'
                  : 'Tell the host why so they can resubmit.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: approve ? 'Note (optional)' : 'Reason',
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? Colors.green : Colors.red,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Approve' : 'Reject',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.rpc('admin_review_host_verification', params: {
        'p_host_id': host['id'],
        'p_approve': approve,
        'p_note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      });
      await _fetchAllData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Host verified' : 'Verification rejected'),
          backgroundColor: approve ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
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
            onPressed: () async {
              // Admin is now a real Supabase session, so it must actually be
              // ended — previously this only navigated away.
              await supabase.auth.signOut();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AuthGate()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.white,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(width: 4.0, color: Colors.white),
            insets: EdgeInsets.symmetric(horizontal: 40.0),
          ),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: [
            const Tab(icon: Icon(Icons.people_alt_rounded), text: "Community"),
            Tab(
              icon: const Icon(Icons.report_gmailerrorred_rounded),
              text: "Reports"
                  "${reports.where((r) => (r['status'] ?? 'open') == 'open').isEmpty ? '' : ' (${reports.where((r) => (r['status'] ?? 'open') == 'open').length})'}",
            ),
            Tab(
              icon: const Icon(Icons.verified_user_rounded),
              text: "Verify"
                  "${pendingVerifications.isEmpty ? '' : ' (${pendingVerifications.length})'}",
            ),
            const Tab(icon: Icon(Icons.history_rounded), text: "Audit"),
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
              _buildVerificationsTab(),
              _buildAuditTab(),
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

  // ── Verifications tab (B8) ───────────────────────────────────────────────

  /// `hosts.cnic_url` holds a storage object path, not a URL. Older rows may
  /// still hold a full public URL, so those are passed through unchanged.
  Future<String> _signedCnicUrl(String pathOrUrl) async {
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    try {
      return await supabase.storage
          .from('host_cnic')
          .createSignedUrl(pathOrUrl, 300);
    } catch (e) {
      debugPrint('Signed URL failed: $e');
      return '';
    }
  }

  Widget _buildVerificationsTab() {
    final pending = pendingVerifications;
    final decided = hosts
        .where((h) => ['verified', 'rejected']
            .contains(h['verification_status']))
        .toList();

    if (pending.isEmpty && decided.isEmpty) {
      return const Center(
        child: Text("No hosts have submitted their CNIC yet.",
            style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pending.isNotEmpty) ...[
          _sectionHeader("Awaiting review (${pending.length})"),
          ...pending.map(_verificationCard),
          const SizedBox(height: 24),
        ],
        if (decided.isNotEmpty) ...[
          _sectionHeader("Already decided (${decided.length})"),
          ...decided.map(_verificationCard),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _verificationCard(Map<String, dynamic> h) {
    final status = (h['verification_status'] ?? 'unverified').toString();
    final url = h['cnic_url']?.toString();
    final isPending = status == 'pending';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: (h['profile_pic'] ?? '').toString().isNotEmpty
                      ? NetworkImage(h['profile_pic'])
                      : null,
                  child: (h['profile_pic'] ?? '').toString().isEmpty
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h['fullName'] ?? 'Host',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(h['email'] ?? '',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                      if ((h['cnic_number'] ?? '').toString().isNotEmpty)
                        Text('CNIC: ${h['cnic_number']}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: status == 'verified'
                        ? Colors.green.withOpacity(0.12)
                        : status == 'rejected'
                            ? Colors.red.withOpacity(0.12)
                            : Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: status == 'verified'
                          ? Colors.green[800]
                          : status == 'rejected'
                              ? Colors.red[800]
                              : Colors.orange[800],
                    ),
                  ),
                ),
              ],
            ),
            if (url != null && url.isNotEmpty) ...[
              const SizedBox(height: 12),
              // The bucket is private, so the image is fetched through a
              // signed URL that expires after five minutes.
              FutureBuilder<String>(
                future: _signedCnicUrl(url),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  if (snap.hasError || (snap.data ?? '').isEmpty) {
                    return Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'CNIC image unavailable.\n'
                            'Check that the private "host_cnic" bucket exists.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    );
                  }
                  final signed = snap.data!;
                  return GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        child: InteractiveViewer(
                          child: Image.network(signed, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        signed,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Tap to enlarge · link expires in 5 minutes',
                    style: TextStyle(fontSize: 10, color: Colors.black38)),
              ),
            ],
            if ((h['verification_note'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Note: ${h['verification_note']}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: Colors.red),
                    label: const Text('Reject',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold)),
                    onPressed: () => _reviewVerification(h, false),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve'),
                    onPressed: () => _reviewVerification(h, true),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Audit tab (B9) ───────────────────────────────────────────────────────

  Widget _buildAuditTab() {
    if (auditLog.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            "No admin actions recorded yet.\n\n"
            "Every block, takedown, report resolution and verification "
            "decision is written here automatically.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: auditLog.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final a = auditLog[i];
        final when = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final action = (a['action'] ?? '').toString();

        final destructive = action.contains('block') ||
            action.contains('take_down') ||
            action.contains('reject');

        return ListTile(
          dense: true,
          leading: Icon(
            destructive ? Icons.gpp_bad_rounded : Icons.gpp_good_rounded,
            color: destructive ? Colors.red : Colors.green,
            size: 20,
          ),
          title: Text(
            action.replaceAll('_', ' '),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          subtitle: Text(
            '${a['target_type']} · ${a['target_id'] ?? '—'}'
            '${(a['detail'] ?? '').toString().isEmpty ? '' : '\n${a['detail']}'}',
            style: const TextStyle(fontSize: 11.5),
          ),
          isThreeLine: (a['detail'] ?? '').toString().isNotEmpty,
          trailing: Text(
            when == null ? '' : DateFormat('MMM dd\nHH:mm').format(when),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkTeal)),
    );
  }

  Widget _userCard({required String name, required String email, required String image, required String role, required String userId}) {
    final isBlocked = role == "Host" ? _isHostBlocked(userId) : _isTravellerBlocked(userId);
    
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isBlocked
                    ? Colors.red.withOpacity(0.1)
                    : (role == "Host" ? Colors.blue.withOpacity(0.1) : Colors.teal.withOpacity(0.1)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isBlocked ? "BLOCKED" : role.toUpperCase(),
                style: TextStyle(
                  color: isBlocked
                      ? Colors.red[800]
                      : (role == "Host" ? Colors.blue[800] : Colors.teal[800]),
                  fontSize: 10, 
                  fontWeight: FontWeight.bold
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                color: isBlocked ? Colors.green : Colors.red,
              ),
              tooltip: isBlocked ? 'Unblock User' : 'Block User',
              onPressed: () {
                _toggleBlockUser(userId: userId, role: role, block: !isBlocked);
              },
            ),
          ],
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
    final filtered = reportFilter == 'all'
        ? reports
        : reports
            .where((r) => (r['status'] ?? 'open') == reportFilter)
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              for (final f in ['open', 'resolved', 'dismissed', 'all'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      f[0].toUpperCase() + f.substring(1),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: reportFilter == f,
                    onSelected: (_) => setState(() => reportFilter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    reportFilter == 'open'
                        ? "No open reports. Nothing needs your attention."
                        : "Nothing here.",
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : _buildReportsList(filtered),
        ),
      ],
    );
  }

  Widget _buildReportsList(List<Map<String, dynamic>> list) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final r = list[index];
        final status = (r['status'] ?? 'open').toString();
        final type = r['report_type'] ?? "room";
        
        final reportedUserId = type == "traveller" ? r['reported_user_id'] : r['room_host_id'];
        final reportedUserRole = type == "traveller" ? "Traveller" : "Host";
        final bool isReportedUserBlocked = reportedUserId != null
            ? (type == "traveller" ? _isTravellerBlocked(reportedUserId) : _isHostBlocked(reportedUserId))
            : false;
        
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: status == 'open'
                                ? Colors.orange.withOpacity(0.12)
                                : status == 'resolved'
                                    ? Colors.green.withOpacity(0.12)
                                    : Colors.grey.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: status == 'open'
                                  ? Colors.orange[800]
                                  : status == 'resolved'
                                      ? Colors.green[800]
                                      : Colors.grey[700],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(time,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11)),
                      ],
                    ),
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
                
                if (r['resolution_note'] != null &&
                    r['resolution_note'].toString().trim().isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Resolution",
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                        const SizedBox(height: 4),
                        Text(r['resolution_note'].toString(),
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  children: [
                    if (type != 'traveller' && r['property_id'] != null)
                      TextButton.icon(
                        icon: const Icon(Icons.visibility_off_rounded,
                            size: 16, color: Colors.deepOrange),
                        label: const Text("Take down listing",
                            style: TextStyle(
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold)),
                        onPressed: () => _setPropertyActive(
                            r['property_id'].toString(), false),
                      ),
                    if (reportedUserId != null)
                      TextButton.icon(
                        icon: Icon(
                          isReportedUserBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                          size: 16,
                          color: isReportedUserBlocked ? Colors.green : Colors.red,
                        ),
                        label: Text(
                          isReportedUserBlocked ? "Unblock $reportedUserRole" : "Block $reportedUserRole",
                          style: TextStyle(color: isReportedUserBlocked ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          _toggleBlockUser(
                            userId: reportedUserId,
                            role: reportedUserRole,
                            block: !isReportedUserBlocked,
                          );
                        },
                      ),
                    if (status == 'open')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.darkTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: const Icon(Icons.gavel_rounded, size: 15),
                        label: const Text("Resolve"),
                        onPressed: () => _resolveReport(r),
                      )
                    else
                      TextButton(
                        onPressed: () => _resolveReport(r),
                        child: const Text("Change outcome"),
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
