import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
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
    _loadProfile();
    _debugCheckStorage();
  }

  Future<void> _debugCheckStorage() async {
    final profile = await AuthService.getUserProfile();
    print("🔍 DEBUG - Profile in storage: $profile");
    final token = await AuthService.getValidAccessToken();
    print("🔍 DEBUG - Has valid token: ${token != null}");
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // First, try to get locally stored profile
      final localProfile = await AuthService.getUserProfile();
      
      if (localProfile['username'] != null) {
        // Use local data immediately
        setState(() {
          _profile = localProfile;
          _loading = false;
        });
        print("✅ Loaded profile from local storage");
      }

      // Then try to fetch fresh data from API
      final token = await AuthService.getValidAccessToken();
      
      if (token == null) {
        // If no token and no local profile, show error
        if (localProfile['username'] == null) {
          if (mounted) {
            setState(() {
              _loading = false;
              _error = "Not logged in";
            });
          }
        }
        return;
      }

      print("🔑 Token obtained, fetching fresh profile...");

      // Fetch profile from API
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/api/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      print("📡 API Response Status: ${response.statusCode}");

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        setState(() {
          _profile = {
            'username': data['username']?.toString(),
            'full_name': data['full_name']?.toString() ?? data['fullName']?.toString(),
            'email': data['email']?.toString(),
            'phone': data['phone']?.toString() ?? data['contact']?.toString(),
            'province': data['province']?.toString(),
            'municipality': data['municipality']?.toString(),
            'barangay': data['barangay']?.toString(),
          };
          _loading = false;
        });

        print("✅ Profile updated from API: $_profile");
      } else if (localProfile['username'] != null) {
        // If API fails but we have local data, keep using it
        print("⚠️ API returned ${response.statusCode}, using local profile");
        setState(() {
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = "Failed to load profile (Status: ${response.statusCode})";
        });
      }
    } catch (e) {
      print("❌ Error loading profile: $e");
      
      // If we already have local profile data, keep using it
      if (_profile['username'] != null) {
        print("⚠️ Using cached profile data due to network error");
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = "Network error. Please try again.";
          });
        }
      }
    }
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
        title: const Text("My Profile"),
        backgroundColor: const Color(0xFF2C7A2C),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProfile,
            tooltip: "Refresh",
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: "Logout",
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF2C7A2C)),
                  SizedBox(height: 16),
                  Text("Loading profile..."),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, 
                        size: 64, 
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadProfile,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Retry"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C7A2C),
                        ),
                      ),
                    ],
                  ),
                )
              : _buildProfileContent(),
    );
  }

  Widget _buildProfileContent() {
    final p = _profile;
    final name = p["full_name"] ?? p["username"] ?? "User";
    final username = p["username"] ?? "N/A";

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header with gradient background
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2C7A2C), Color(0xFF1E5A1E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            child: Column(
              children: [
                // Avatar with initial
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(name),
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C7A2C),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Name
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                // Username
                Text(
                  "@$username",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),

          // Profile Information Cards
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Account Information Section
                _sectionHeader("Account Information", Icons.person),
                const SizedBox(height: 12),
                _infoCard("Username", p["username"], Icons.account_circle),
                _infoCard("Full Name", p["full_name"], Icons.badge),
                _infoCard("Email", p["email"], Icons.email),
                _infoCard("Phone", p["phone"], Icons.phone),

                const SizedBox(height: 24),

                // Location Information Section
                _sectionHeader("Location Information", Icons.location_on),
                const SizedBox(height: 12),
                _infoCard("Province", p["province"], Icons.map),
                _infoCard("Municipality", p["municipality"], Icons.location_city),
                _infoCard("Barangay", p["barangay"], Icons.home),

                const SizedBox(height: 30),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text("Back"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: const Color(0xFF2C7A2C),
                          side: const BorderSide(color: Color(0xFF2C7A2C)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text("Logout"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.red,
                        ),
                      ),
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

  String _getInitials(String name) {
    if (name.isEmpty || name == "User" || name == "N/A") return "?";
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  Widget _sectionHeader(String title, IconData icon) {
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

  Widget _infoCard(String label, String? value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 10),
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2C7A2C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF2C7A2C),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value != null && value.isNotEmpty ? value : "Not provided",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: value != null && value.isNotEmpty 
                        ? Colors.black87 
                        : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}