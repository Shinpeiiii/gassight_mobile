import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = "https://gassight.onrender.com";

  // Local storage keys
  static const _tokenKey = "jwt_token";
  static const _usernameKey = "username";
  static const _fullNameKey = "full_name";
  static const _emailKey = "email";
  static const _phoneKey = "phone";
  static const _provinceKey = "province";
  static const _municipalityKey = "municipality";
  static const _barangayKey = "barangay";

  /// ==================================================
  /// LOGIN — FIXED ENDPOINT + BETTER JSON VALIDATION
  /// ==================================================
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      );

      // Validate JSON
      Map<String, dynamic> data = {};
      final contentType = response.headers["content-type"] ?? "";

      if (contentType.contains("application/json")) {
        try {
          data = jsonDecode(response.body);
        } catch (_) {
          return {"ok": false, "error": "Invalid JSON response from server."};
        }
      } else {
        return {
          "ok": false,
          "error": "Server returned non-JSON response. Code ${response.statusCode}."
        };
      }

      // Success
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_tokenKey, "dummy_token"); // Your backend has no JWT yet
        await prefs.setString(_usernameKey, username);

        // Store profile (if backend sends)
        if (data["profile"] != null) {
          final p = data["profile"];
          await prefs.setString(_fullNameKey, p["full_name"] ?? "");
          await prefs.setString(_emailKey, p["email"] ?? "");
          await prefs.setString(_phoneKey, p["phone"] ?? "");
          await prefs.setString(_provinceKey, p["province"] ?? "");
          await prefs.setString(_municipalityKey, p["municipality"] ?? "");
          await prefs.setString(_barangayKey, p["barangay"] ?? "");
        }

        return {"ok": true};
      }

      return {"ok": false, "error": data["error"] ?? "Login failed."};
    } catch (e) {
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// ==================================================
  /// SIGNUP — FIXED ENDPOINT `/signup`
  /// ==================================================
  static Future<Map<String, dynamic>> signup(
    String username,
    String password,
    String fullName,
    String email,
    String phone,
    String province,
    String municipality,
    String barangay,
  ) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/signup"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
          "fullName": fullName,      // <-- matches your backend
          "email": email,
          "contact": phone,
          "address": "$province, $municipality, $barangay",
          "province": province,
          "municipality": municipality,
          "barangay": barangay,
        }),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();

        // Save local data
        await prefs.setString(_usernameKey, username);
        await prefs.setString(_fullNameKey, fullName);
        await prefs.setString(_emailKey, email);
        await prefs.setString(_phoneKey, phone);
        await prefs.setString(_provinceKey, province);
        await prefs.setString(_municipalityKey, municipality);
        await prefs.setString(_barangayKey, barangay);

        // Backend does not send token → using placeholder
        await prefs.setString(_tokenKey, "dummy_token");

        return {"ok": true};
      }

      return {
        "ok": false,
        "error": data["error"] ?? "Signup failed. Code ${response.statusCode}"
      };
    } catch (e) {
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// LOGOUT
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// GET STORED TOKEN
  static Future<String?> getValidAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// GET LOCAL PROFILE
  static Future<Map<String, String?>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      "username": prefs.getString(_usernameKey),
      "full_name": prefs.getString(_fullNameKey),
      "email": prefs.getString(_emailKey),
      "phone": prefs.getString(_phoneKey),
      "province": prefs.getString(_provinceKey),
      "municipality": prefs.getString(_municipalityKey),
      "barangay": prefs.getString(_barangayKey),
    };
  }
}
