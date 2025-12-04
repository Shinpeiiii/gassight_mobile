import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'profile_screen.dart';
import 'report_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  List<dynamic> _reports = [];
  bool _loading = true;
  String? _username;
  int _unreadCount = 0;

  // Filters
  String _selectedSeverity = 'All';
  String _selectedType = 'All';

  final MapController _mapController = MapController();

  // Severity colors
  final Map<String, Color> _severityColors = {
    'Pending': Colors.grey,
    'Low': Colors.green,
    'Moderate': Colors.orange,
    'High': Colors.deepOrange,
    'Critical': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadProfile();
    await _fetchReports();
    await _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final count = await NotificationService.getUnreadCount();
    if (mounted) {
      setState(() => _unreadCount = count);
    }
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.getUserProfile();
    if (!mounted) return;
    setState(() => _username = profile["username"]);
  }

  Future<void> _fetchReports() async {
    setState(() => _loading = true);

    try {
      final params = <String, String>{};
      if (_selectedSeverity != 'All') params['severity'] = _selectedSeverity;
      if (_selectedType != 'All') params['infestation_type'] = _selectedType;

      final uri = Uri.parse("${AuthService.baseUrl}/api/reports")
          .replace(queryParameters: params);

      final res = await http.get(uri);

      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() {
          _reports = jsonDecode(res.body);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        _showError("Failed to load reports");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError("Network error: $e");
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AuthService.logout();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text("Dashboard"),
        backgroundColor: const Color(0xFF2C7A2C),
        elevation: 0,
        actions: [
          // Notifications Button with Badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                  _loadUnreadCount(); // Refresh count when returning
                },
                tooltip: "Notifications",
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchReports();
              _loadUnreadCount();
            },
            tooltip: "Refresh",
          ),
          // Profile Button
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            tooltip: "Profile",
          ),
          // Logout Button
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: "Logout",
          ),
        ],
      ),
      body: _loading ? _buildLoading() : _buildDashboard(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReportScreen()),
          ).then((_) => _fetchReports()); // Refresh after submitting report
        },
        backgroundColor: const Color(0xFF2C7A2C),
        icon: const Icon(Icons.add),
        label: const Text("New Report"),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF2C7A2C)),
          SizedBox(height: 16),
          Text("Loading reports..."),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchReports();
        await _loadUnreadCount();
      },
      color: const Color(0xFF2C7A2C),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Statistics Cards
            _buildStatsCards(),

            const SizedBox(height: 16),

            // Filters
            _buildFilters(),

            const SizedBox(height: 16),

            // Heatmap
            _buildHeatmapSection(),

            const SizedBox(height: 16),

            // Recent Reports List
            _buildReportsList(),
          ],
        ),
      ),
    );
  }

  // Statistics cards
  Widget _buildStatsCards() {
    final totalReports = _reports.length;
    final criticalReports =
        _reports.where((r) => r['severity'] == 'Critical').length;
    final highReports = _reports.where((r) => r['severity'] == 'High').length;
    final pendingReports =
        _reports.where((r) => r['severity'] == 'Pending').length;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statCard(
                  "Total Reports",
                  totalReports.toString(),
                  Icons.assignment,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  "Critical",
                  criticalReports.toString(),
                  Icons.warning,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  "High Risk",
                  highReports.toString(),
                  Icons.error,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  "Pending",
                  pendingReports.toString(),
                  Icons.pending,
                  Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Filters
  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _filterDropdown(
              label: "Severity",
              value: _selectedSeverity,
              items: ['All', 'Pending', 'Low', 'Moderate', 'High', 'Critical'],
              onChanged: (v) {
                setState(() => _selectedSeverity = v!);
                _fetchReports();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _filterDropdown(
              label: "Type",
              value: _selectedType,
              items: [
                'All',
                'Golden Apple Snail (GAS)',
                'Rice Black Bug (RBB)',
                'Brown Plant Hopper (BPH)',
                'Others'
              ],
              onChanged: (v) {
                setState(() => _selectedType = v!);
                _fetchReports();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  // Heatmap Section
  Widget _buildHeatmapSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.map, color: Color(0xFF2C7A2C)),
              SizedBox(width: 8),
              Text(
                "Infestation Heatmap",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7A2C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildMap(),
            ),
          ),
          const SizedBox(height: 8),
          _buildLegend(),
        ],
      ),
    );
  }

  // Map with markers
  Widget _buildMap() {
    // Calculate center point
    double centerLat = 17.25;
    double centerLng = 120.45;

    if (_reports.isNotEmpty) {
      final validReports =
          _reports.where((r) => r['lat'] != null && r['lng'] != null).toList();
      if (validReports.isNotEmpty) {
        centerLat = validReports
                .map((r) => r['lat'] as double)
                .reduce((a, b) => a + b) /
            validReports.length;
        centerLng = validReports
                .map((r) => r['lng'] as double)
                .reduce((a, b) => a + b) /
            validReports.length;
      }
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: latlng.LatLng(centerLat, centerLng),
        initialZoom: 10,
      ),
      children: [
        TileLayer(
          urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        ),
        MarkerLayer(
          markers: _reports
              .where((r) => r['lat'] != null && r['lng'] != null)
              .map((r) {
            final severity = r['severity'] ?? 'Pending';
            final color = _severityColors[severity] ?? Colors.grey;

            return Marker(
              point: latlng.LatLng(r['lat'], r['lng']),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => _showReportDialog(r),
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.7),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Legend
  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: _severityColors.entries.map((e) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: e.value,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                e.key,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // Reports List
  Widget _buildReportsList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.list, color: Color(0xFF2C7A2C)),
              SizedBox(width: 8),
              Text(
                "Recent Reports",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7A2C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_reports.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      "No reports found",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _reports.length > 10 ? 10 : _reports.length,
              itemBuilder: (context, index) {
                final report = _reports[index];
                return _buildReportCard(report);
              },
            ),
        ],
      ),
    );
  }

  // Report card
  Widget _buildReportCard(Map<String, dynamic> report) {
    final severity = report['severity'] ?? 'Pending';
    final color = _severityColors[severity] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showReportDialog(report),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Severity badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      severity,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    report['date'] ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                report['infestation_type'] ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "${report['barangay']}, ${report['municipality']}, ${report['province']}",
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (report['description'] != null &&
                  report['description'].toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  report['description'],
                  style: const TextStyle(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Show report details dialog
  void _showReportDialog(Map<String, dynamic> report) {
    final severity = report['severity'] ?? 'Pending';
    final color = _severityColors[severity] ?? Colors.grey;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                severity,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow("Type", report['infestation_type']),
              _detailRow("Location",
                  "${report['barangay']}, ${report['municipality']}, ${report['province']}"),
              _detailRow("Reporter", report['reporter']),
              _detailRow("Date", report['date']),
              _detailRow("Coordinates",
                  "${report['lat']?.toStringAsFixed(5)}, ${report['lng']?.toStringAsFixed(5)}"),
              if (report['description'] != null)
                _detailRow("Description", report['description']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value?.toString() ?? 'N/A',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}