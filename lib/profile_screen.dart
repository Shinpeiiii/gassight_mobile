import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, String?> _profile = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _debugAndLoadProfile();
  }

  Future<void> _debugAndLoadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      print("\n" + "=" * 60);
      print("🔍 PROFILE DEBUG - CHECKING TOKEN SOURCE");
      print("=" * 60);

      final token = await AuthService.getToken();

      print("🔐 Token from AuthService: "
          "${token != null ? token.substring(0, token.length >= 25 ? 25 : token.length) + '...' : 'NULL'}");

      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = "Not logged in. Please log in again.";
          });
        }
        return;
      }

      print("📡 Fetching /api/profile ...");

      final response = await http
          .get(
            Uri.parse('https://gassight.onrender.com/api/profile'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 20));

      print("📡 Status: ${response.statusCode}");
      print("📡 Body: ${response.body}");

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final username = data['username']?.toString() ?? "";
        final fullName = data['full_name']?.toString() ??
            data['fullName']?.toString() ??
            "";
        final email = data['email']?.toString() ?? "";
        final phone =
            data['phone']?.toString() ?? data['contact']?.toString() ?? "";
        final province = data['province']?.toString() ?? "";
        final municipality = data['municipality']?.toString() ?? "";
        final barangay = data['barangay']?.toString() ?? "";

        print("💾 Saving profile to SharedPreferences...");

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("username", username);
        await prefs.setString("full_name", fullName);
        await prefs.setString("email", email);
        await prefs.setString("phone", phone);
        await prefs.setString("province", province);
        await prefs.setString("municipality", municipality);
        await prefs.setString("barangay", barangay);

        setState(() {
          _profile = {
            "username": username,
            "full_name": fullName,
            "email": email,
            "phone": phone,
            "province": province,
            "municipality": municipality,
            "barangay": barangay,
          };
          _loading = false;
        });
      } else if (response.statusCode == 401) {
        print("❌ INVALID/EXPIRED TOKEN — Logging out...");

        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        await const FlutterSecureStorage().deleteAll();

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: const Text("Session Expired"),
              content: const Text("Please log in again."),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                    );
                  },
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
      } else {
        setState(() {
          _error = "Server error: ${response.statusCode}";
          _loading = false;
        });
      }
    } catch (e) {
      print("❌ ERROR: $e");

      if (mounted) {
        setState(() {
          _error = "Error: $e";
          _loading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text("Logout"),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await const FlutterSecureStorage().deleteAll();

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
        title: const Text("My Profile"),
        backgroundColor: const Color(0xFF2C7A2C),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _debugAndLoadProfile,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? _loadingWidget()
          : (_error != null ? _errorWidget() : _profileWidget()),
    );
  }

  Widget _loadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF2C7A2C)),
          SizedBox(height: 12),
          Text("Loading profile..."),
        ],
      ),
    );
  }

  Widget _errorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _debugAndLoadProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C7A2C),
              ),
              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileWidget() {
    final p = _profile;
    final name = p["full_name"] ?? "User";
    final username = p["username"] ?? "unknown";

    return SingleChildScrollView(
      child: Column(
        children: [
          _headerSection(name, username),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _sectionHeader("Account Information", Icons.person),
                _infoCard("Username", p["username"], Icons.account_circle),
                _infoCard("Full Name", p["full_name"], Icons.badge),
                _infoCard("Email", p["email"], Icons.email),
                _infoCard("Phone", p["phone"], Icons.phone),

                const SizedBox(height: 20),
                _sectionHeader("Location Information", Icons.location_on),
                _infoCard("Province", p["province"], Icons.map),
                _infoCard("Municipality", p["municipality"], Icons.location_city),
                _infoCard("Barangay", p["barangay"], Icons.home),

                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  label: const Text("Logout"),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _headerSection(String name, String username) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C7A2C), Color(0xFF1E5A1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white,
            child: Text(
              _getInitials(name),
              style: const TextStyle(
                fontSize: 32,
                color: Color(0xFF2C7A2C),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            "@$username",
            style: TextStyle(color: Colors.white.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(" ");
    if (parts.isEmpty) return "?";
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2C7A2C)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF2C7A2C),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _infoCard(String label, String? value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2C7A2C)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(
                  value != null && value.isNotEmpty ? value : "Not provided",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
