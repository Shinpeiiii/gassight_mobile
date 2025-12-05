import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'auth_service.dart';

class OfflineSyncManager {
  static Database? _db;
  final String apiBaseUrl;

  OfflineSyncManager(this.apiBaseUrl);

  Future<void> init() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'reports.db'),
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE reports(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT)',
        );
      },
      version: 1,
    );
  }

  Future<void> saveOffline(Map<String, dynamic> report) async {
    if (_db == null) await init();
    await _db!.insert('reports', {'data': jsonEncode(report)});
  }

  Future<void> syncReports() async {
    if (_db == null) await init();

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) return;

    final token = await AuthService.getValidAccessToken();
    if (token == null) return;

    final unsent = await _db!.query('reports');
    if (unsent.isEmpty) return;

    for (final item in unsent) {
      final report = jsonDecode(item['data'] as String);

      try {
        final res = await http.post(
          Uri.parse('$apiBaseUrl/api/report'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(report),
        );

        if (res.statusCode == 200 || res.statusCode == 201) {
          await _db!.delete(
            'reports',
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        }
      } catch (_) {
        // If error, keep offline report
        continue;
      }
    }
  }
}
