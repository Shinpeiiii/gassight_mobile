import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> notifications = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadNotifications();
  }

  Future<void> loadNotifications() async {
    setState(() => loading = true);

    final jwt = await AuthService.getValidAccessToken();
    if (jwt == null) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Session expired. Please log in again."),
        ),
      );
      return;
    }

    try {
      final response = await http.get(
        Uri.parse("${AuthService.baseUrl}/api/notifications"),
        headers: {"Authorization": "Bearer $jwt"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          notifications = jsonDecode(response.body);
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to load notifications."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadNotifications,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
              ? const Center(child: Text("No notifications yet"))
              : ListView.builder(
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final n = notifications[index] as Map<String, dynamic>;
                    final severity = n["severity"]?.toString() ?? "";
                    final createdAt = (n["created_at"] ?? "").toString();

                    return ListTile(
                      leading: Icon(
                        Icons.warning_rounded,
                        color: (severity == "High" ||
                                severity == "Critical")
                            ? Colors.red
                            : Colors.orange,
                      ),
                      title: Text(n["title"] ?? "Alert"),
                      subtitle: Text(n["body"] ?? ""),
                      trailing: Text(
                        createdAt.isNotEmpty && createdAt.length >= 10
                            ? createdAt.substring(0, 10)
                            : "",
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
    );
  }
}
