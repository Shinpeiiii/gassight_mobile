import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/offline_sync.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();

  final _province = TextEditingController();
  final _municipality = TextEditingController();
  final _barangay = TextEditingController();
  final _description = TextEditingController();

  String _infestationType = 'Golden Apple Snail (GAS)';

  final List<String> infestationTypes = [
    'Golden Apple Snail (GAS)',
    'Rice Black Bug (RBB)',
    'Brown Plant Hopper (BPH)',
    'Others',
  ];

  bool _submitting = false;
  File? _image;
  double? _lat;
  double? _lng;

  String? _username;
  String? _fullName;

  late OfflineSyncManager _offline;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _offline = OfflineSyncManager(AuthService.baseUrl);
    _initAll();
  }

  Future<void> _initAll() async {
    await _offline.init();
    await _offline.syncReports();
    await _loadProfile();
    await _getLocation();
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.getUserProfile();
    if (!mounted) return;

    setState(() {
      _username = profile["username"];
      _fullName = profile["full_name"];

      _province.text = profile["province"] ?? "";
      _municipality.text = profile["municipality"] ?? "";
      _barangay.text = profile["barangay"] ?? "";
    });
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
      (route) => false,
    );
  }

  Future<void> _getLocation() async {
    final pos = await LocationService.getCurrentLocation(context);
    if (pos == null) return;

    if (!mounted) return;
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
    });

    _mapController.move(latlng.LatLng(_lat!, _lng!), 15);
  }

  Future<void> _pick(ImageSource s) async {
    final pic = await ImagePicker().pickImage(source: s, imageQuality: 75);
    if (pic != null) setState(() => _image = File(pic.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_lat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠ Please enable location first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Submit Report"),
        content: const Text(
          "Are you sure you want to submit this report? Make sure all information is correct.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2C7A2C),
            ),
            child: const Text("Submit"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _submitting = true);

    final token = await AuthService.getValidAccessToken();
    if (token == null) {
      _logout();
      return;
    }

    final report = {
      "reporter": _username,
      "province": _province.text.trim(),
      "municipality": _municipality.text.trim(),
      "barangay": _barangay.text.trim(),
      "infestation_type": _infestationType,
      "description": _description.text.trim(),
      "lat": _lat,
      "lng": _lng,
      "gps_metadata": {
        "lat": _lat,
        "lng": _lng,
        "timestamp": DateTime.now().toIso8601String(),
      }
    };

    try {
      http.StreamedResponse res;

      if (_image != null) {
        final req = http.MultipartRequest(
          'POST',
          Uri.parse("${AuthService.baseUrl}/api/report"),
        );

        req.headers["Authorization"] = "Bearer $token";

        report.forEach((k, v) {
          if (k == "gps_metadata") return;
          req.fields[k] = v.toString();
        });

        req.fields["gps_metadata"] = jsonEncode(report["gps_metadata"]);
        req.files.add(await http.MultipartFile.fromPath("photo", _image!.path));

        res = await req.send();
      } else {
        final jsonRes = await http.post(
          Uri.parse("${AuthService.baseUrl}/api/report"),
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
          body: jsonEncode(report),
        );

        res = http.StreamedResponse(
          Stream.value(utf8.encode(jsonRes.body)),
          jsonRes.statusCode,
        );
      }

      final body = await res.stream.bytesToString();

      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text("✅ Report submitted successfully!"),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
        
        // Reset form
        _formKey.currentState!.reset();
        setState(() {
          _image = null;
          _description.clear();
        });
        
        // Reload location data
        await _loadProfile();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Error: $body"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      await _offline.saveOffline(report);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📴 Offline: Report saved & will sync when online."),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
    }

    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text("Submit Report"),
        backgroundColor: const Color(0xFF2C7A2C),
        elevation: 0,
        actions: [
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
      body: _buildUI(),
    );
  }

  Widget _buildUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Info Card
            if (_username != null) _userInfoCard(),

            const SizedBox(height: 20),

            // Location Fields
            _sectionTitle("Location Information", Icons.location_on),
            const SizedBox(height: 12),
            _textField(_province, "Province", Icons.map),
            _textField(_municipality, "Municipality", Icons.location_city),
            _textField(_barangay, "Barangay", Icons.home),

            const SizedBox(height: 20),

            // Infestation Type
            _sectionTitle("Infestation Details", Icons.bug_report),
            const SizedBox(height: 12),
            _infestationDropdown(),

            const SizedBox(height: 14),

            // Description
            _textField(
              _description,
              "Description",
              Icons.description,
              maxLines: 4,
              hint: "Describe the infestation in detail...",
            ),

            const SizedBox(height: 20),

            // GPS Location
            _sectionTitle("GPS Location", Icons.gps_fixed),
            const SizedBox(height: 12),
            _gpsCard(),

            const SizedBox(height: 14),
            _map(),

            const SizedBox(height: 20),

            // Photo
            _sectionTitle("Photo Evidence", Icons.camera_alt),
            const SizedBox(height: 12),
            _photoPicker(),

            const SizedBox(height: 30),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C7A2C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send),
                          SizedBox(width: 8),
                          Text(
                            "Submit Report",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // User info card
  Widget _userInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C7A2C), Color(0xFF1E5A1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _username![0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7A2C),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Reporter",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _fullName ?? _username!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Section title
  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2C7A2C), size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C7A2C),
          ),
        ),
      ],
    );
  }

  // Text field with icon
  Widget _textField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    String? hint,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: (v) => v == null || v.trim().isEmpty ? "Required" : null,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xFF2C7A2C)),
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  // Infestation dropdown
  Widget _infestationDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
        value: _infestationType,
        items: infestationTypes
            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
            .toList(),
        onChanged: (v) => setState(() => _infestationType = v!),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.pest_control, color: Color(0xFF2C7A2C)),
          border: InputBorder.none,
          labelText: "Infestation Type",
        ),
      ),
    );
  }

  // GPS card
  Widget _gpsCard() {
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Coordinates",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _lat != null
                      ? "${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}"
                      : "Location not detected",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _lat != null ? Colors.black87 : Colors.red,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.my_location, color: Color(0xFF2C7A2C)),
            onPressed: _getLocation,
            tooltip: "Get Current Location",
          ),
        ],
      ),
    );
  }

  // Map widget
  Widget _map() {
    return Container(
      height: 220,
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
        child: _lat == null
            ? Container(
                color: Colors.grey.shade200,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        "Location not available",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            : FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: latlng.LatLng(_lat!, _lng!),
                  initialZoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: latlng.LatLng(_lat!, _lng!),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  // Photo picker
  Widget _photoPicker() {
    return GestureDetector(
      onTap: _showImageSourceDialog,
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300, width: 2),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _image == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    "📸 Tap to add photo",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Camera or Gallery",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              )
            : Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _image!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () => setState(() => _image = null),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Show image source dialog
  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Choose Photo Source",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF2C7A2C)),
              title: const Text("Camera"),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: Color(0xFF2C7A2C)),
              title: const Text("Gallery"),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}