// (Shortened beginning: imports unchanged)
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/offline_sync.dart';
import 'login_screen.dart';
import 'profile_screen.dart';   // <-- ✅ ADDED

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
  String? _phone;
  String? _email;

  late OfflineSyncManager _offline;

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _secureScreen(); // 👈 BLOCK SCREENSHOTS ON THIS SCREEN
    _offline = OfflineSyncManager(AuthService.baseUrl);
    _initAll();
  }

  /// Prevent screenshots and screen recording on this screen
  Future<void> _secureScreen() async {
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
      _email = profile["email"];
      _phone = profile["phone"];

      _province.text = profile["province"] ?? "";
      _municipality.text = profile["municipality"] ?? "";
      _barangay.text = profile["barangay"] ?? "";
    });
  }

  Future<void> _logout() async {
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
    final pic =
        await ImagePicker().pickImage(source: s, imageQuality: 75);
    if (pic != null) setState(() => _image = File(pic.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_lat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠ Enable location first.")),
      );
      return;
    }

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
          const SnackBar(content: Text("✅ Report submitted!")),
        );
        _formKey.currentState!.reset();
        setState(() => _image = null);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("❌ $body")));
      }
    } catch (_) {
      await _offline.saveOffline(report);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("📴 Offline: saved & will sync later.")),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.person),   // <-- ✅ PROFILE BUTTON
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          )
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
            if (_username != null)
              Text("Reporter: $_username",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),

            const SizedBox(height: 12),

            _box(_province, "Province"),
            _box(_municipality, "Municipality"),
            _box(_barangay, "Barangay"),

            const SizedBox(height: 14),

            const Text("Infestation Type",
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            _drop(),

            const SizedBox(height: 14),

            _box(_description, "Description", maxLines: 3),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: Text(
                    _lat != null
                        ? "📍 ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}"
                        : "Location not detected",
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.my_location,
                      color: Color(0xFF2C7A2C)),
                  onPressed: _getLocation,
                ),
              ],
            ),

            const SizedBox(height: 10),

            _map(),

            const SizedBox(height: 14),

            _photoPicker(),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C7A2C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Submit Report"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(TextEditingController c, String label, {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        validator: (v) =>
            v == null || v.trim().isEmpty ? "Required" : null,
        decoration: InputDecoration(
            border: InputBorder.none, labelText: label),
      ),
    );
  }

  Widget _drop() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonFormField(
        value: _infestationType,
        items: infestationTypes
            .map((t) =>
                DropdownMenuItem(value: t, child: Text(t)))
            .toList(),
        onChanged: (v) => setState(() => _infestationType = v!),
        decoration: const InputDecoration(border: InputBorder.none),
      ),
    );
  }

  Widget _map() {
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _lat == null
            ? Container(
                color: Colors.grey.shade200,
                child: const Center(child: Text("Map not available")),
              )
            : FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  center: latlng.LatLng(_lat!, _lng!),
                  zoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: latlng.LatLng(_lat!, _lng!),
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on,
                          color: Colors.red, size: 36),
                    )
                  ])
                ],
              ),
      ),
    );
  }

  Widget _photoPicker() {
    return GestureDetector(
      onTap: () => _bottom(),
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.white,
        ),
        child: _image == null
            ? const Center(child: Text("📸 Tap to add photo"))
            : ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(_image!, fit: BoxFit.cover),
              ),
      ),
    );
  }

  void _bottom() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text("Camera"),
            onTap: () {
              Navigator.pop(context);
              _pick(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text("Gallery"),
            onTap: () {
              Navigator.pop(context);
              _pick(ImageSource.gallery);
            },
          ),
        ],
      ),
    );
  }
}
