import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Timer? _pollingTimer;
  static bool _initialized = false;

  static const String _lastCheckKey = 'last_notification_check';
  static const String _notificationCountKey = 'notification_count';
  static const String _userLatKey = 'user_lat';
  static const String _userLngKey = 'user_lng';

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _requestPermission();
      await _initializeLocalNotifications();
      startPolling();
      _initialized = true;
      print('✅ Notification service initialized');
    } catch (e) {
      print('❌ Error initializing notifications: $e');
    }
  }

  static Future<void> saveUserLocation(double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_userLatKey, lat);
    await prefs.setDouble(_userLngKey, lng);
    print('📍 User location saved: $lat, $lng');
  }

  static Future<Map<String, double>?> getUserLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_userLatKey);
    final lng = prefs.getDouble(_userLngKey);
    
    if (lat == null || lng == null) return null;
    
    return {'lat': lat, 'lng': lng};
  }

  static double calculateDistance(
    double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    
    final c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }

  static double _toRadians(double degree) {
    return degree * (math.pi / 180);
  }

  static Future<void> _requestPermission() async {
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }

    final iosPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    if (iosPlugin != null) {
      await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  static Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  static void startPolling() {
    stopPolling();
    checkForNewNotifications();

    _pollingTimer = Timer.periodic(
      const Duration(minutes: 5),
      (timer) => checkForNewNotifications(),
    );

    print('📡 Notification polling started (every 5 minutes)');
  }

  static void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  static Future<void> checkForNewNotifications() async {
    try {
      final isLoggedIn = await AuthService.isLoggedIn();
      if (!isLoggedIn) {
        print('⚠️ User not logged in, skipping notification check');
        return;
      }

      final settings = await getSettings();
      if (settings['enabled'] == false) {
        print('⚠️ Notifications disabled in settings');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getString(_lastCheckKey);
      
      final profile = await AuthService.getUserProfile();
      final userProvince = profile['province'];
      final userMunicipality = profile['municipality'];
      final userLocation = await getUserLocation();
      
      if (userProvince == null) {
        print('⚠️ User location not set');
        return;
      }

      print('🔍 Checking for new reports in $userMunicipality, $userProvince');

      String query = '';
      
      if (settings['use_distance_filter'] == true && userLocation != null) {
        query = 'province=$userProvince';
      } else if (settings['same_municipality_only'] == true) {
        query = 'province=$userProvince&municipality=$userMunicipality';
      } else {
        query = 'province=$userProvince';
      }

      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/api/reports?$query'),
      );

      if (response.statusCode != 200) {
        print('❌ Failed to fetch reports: ${response.statusCode}');
        return;
      }

      List<dynamic> reports = jsonDecode(response.body);
      
      if (settings['use_distance_filter'] == true && userLocation != null) {
        final maxDistance = settings['max_distance_km'] ?? 10.0;
        reports = reports.where((report) {
          if (report['lat'] == null || report['lng'] == null) return false;
          
          final distance = calculateDistance(
            userLocation['lat']!,
            userLocation['lng']!,
            report['lat'],
            report['lng'],
          );
          
          return distance <= maxDistance;
        }).toList();
        
        print('📍 Filtered to ${reports.length} reports within $maxDistance km');
      }
      
      final DateTime lastCheckTime = lastCheck != null
          ? DateTime.parse(lastCheck)
          : DateTime.now().subtract(const Duration(hours: 1));

      final newReports = reports.where((report) {
        try {
          final reportDate = DateTime.parse(report['date']);
          final isNew = reportDate.isAfter(lastCheckTime);
          
          final severity = report['severity']?.toString().toLowerCase() ?? '';
          if (severity == 'critical' && settings['notify_critical'] != true) return false;
          if (severity == 'high' && settings['notify_high'] != true) return false;
          if (severity == 'moderate' && settings['notify_moderate'] != true) return false;
          if (severity == 'low' && settings['notify_low'] != true) return false;
          if (severity == 'pending' && settings['notify_pending'] != true) return false;
          
          return isNew;
        } catch (e) {
          return false;
        }
      }).toList();

      print('🔬 Found ${newReports.length} new reports');

      int notificationCount = 0;
      for (final report in newReports) {
        double? distance;
        if (userLocation != null && report['lat'] != null && report['lng'] != null) {
          distance = calculateDistance(
            userLocation['lat']!,
            userLocation['lng']!,
            report['lat'],
            report['lng'],
          );
        }
        
        await _showReportNotification(report, distance);
        notificationCount++;
      }

      await prefs.setString(_lastCheckKey, DateTime.now().toIso8601String());
      
      if (notificationCount > 0) {
        final currentCount = prefs.getInt(_notificationCountKey) ?? 0;
        await prefs.setInt(_notificationCountKey, currentCount + notificationCount);
      }

    } catch (e) {
      print('❌ Error checking notifications: $e');
    }
  }

  static Future<void> _showReportNotification(
    Map<String, dynamic> report,
    double? distance,
  ) async {
    final severity = report['severity'] ?? 'Pending';
    final type = report['infestation_type'] ?? 'Unknown';
    final location = '${report['barangay']}, ${report['municipality']}';

    String title = '⚠️ $severity Alert Nearby!';
    String body = 'New $type infestation reported in $location';
    
    if (distance != null) {
      if (distance < 1) {
        body += ' (${(distance * 1000).toStringAsFixed(0)}m away)';
      } else {
        body += ' (${distance.toStringAsFixed(1)}km away)';
      }
    }

    print('🔔 Showing notification: $title');

    await _showLocalNotification(
      title: title,
      body: body,
      payload: jsonEncode({
        'type': 'report',
        'report_id': report['id'],
        'severity': severity,
        'distance': distance,
      }),
      importance: _getImportanceFromSeverity(severity),
    );
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    Importance importance = Importance.high,
  }) async {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'gassight_alerts',
      'Infestation Alerts',
      channelDescription: 'Notifications about nearby pest infestations',
      importance: importance,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecond,
      title,
      body,
      platformDetails,
      payload: payload,
    );
  }

  static Importance _getImportanceFromSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Importance.max;
      case 'high':
        return Importance.high;
      case 'moderate':
        return Importance.defaultImportance;
      case 'low':
        return Importance.low;
      default:
        return Importance.defaultImportance;
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    print('📱 Notification tapped: ${response.payload}');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        print('Report ID: ${data['report_id']}');
        if (data['distance'] != null) {
          print('Distance: ${data['distance']}km');
        }
      } catch (e) {
        print('Error parsing notification payload: $e');
      }
    }
  }

  static Future<List<Map<String, dynamic>>> getStoredNotifications() async {
    try {
      final profile = await AuthService.getUserProfile();
      final userProvince = profile['province'];
      final userMunicipality = profile['municipality'];
      final userLocation = await getUserLocation();
      
      if (userProvince == null) return [];

      final settings = await getSettings();
      
      String query = 'province=$userProvince';
      if (settings['same_municipality_only'] == true && userMunicipality != null) {
        query += '&municipality=$userMunicipality';
      }

      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/api/reports?$query'),
      );

      if (response.statusCode != 200) return [];

      List<dynamic> reports = jsonDecode(response.body);
      
      if (settings['use_distance_filter'] == true && userLocation != null) {
        final maxDistance = settings['max_distance_km'] ?? 10.0;
        reports = reports.where((report) {
          if (report['lat'] == null || report['lng'] == null) return false;
          
          final distance = calculateDistance(
            userLocation['lat']!,
            userLocation['lng']!,
            report['lat'],
            report['lng'],
          );
          
          return distance <= maxDistance;
        }).toList();
      }
      
      final notifications = reports.take(50).map((report) {
        double? distance;
        if (userLocation != null && report['lat'] != null && report['lng'] != null) {
          distance = calculateDistance(
            userLocation['lat']!,
            userLocation['lng']!,
            report['lat'],
            report['lng'],
          );
        }
        
        String distanceText = '';
        if (distance != null) {
          if (distance < 1) {
            distanceText = ' • ${(distance * 1000).toStringAsFixed(0)}m away';
          } else {
            distanceText = ' • ${distance.toStringAsFixed(1)}km away';
          }
        }
        
        return {
          'id': report['id'],
          'title': '⚠️ ${report['severity']} Alert',
          'message': 'New ${report['infestation_type']} infestation reported in ${report['barangay']}, ${report['municipality']}$distanceText',
          'severity': report['severity'],
          'date': report['date'],
          'location': '${report['barangay']}, ${report['municipality']}, ${report['province']}',
          'report_id': report['id'],
          'is_same_municipality': report['municipality'] == userMunicipality,
          'distance_km': distance,
        };
      }).toList();

      return await filterNotificationsBySettings(notifications);

    } catch (e) {
      print('Error getting notifications: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> filterNotificationsBySettings(
    List<Map<String, dynamic>> notifications,
  ) async {
    final settings = await getSettings();

    return notifications.where((notification) {
      final severity = notification['severity']?.toString().toLowerCase() ?? '';
      
      if (severity == 'critical' && settings['notify_critical'] != true) return false;
      if (severity == 'high' && settings['notify_high'] != true) return false;
      if (severity == 'moderate' && settings['notify_moderate'] != true) return false;
      if (severity == 'low' && settings['notify_low'] != true) return false;
      if (severity == 'pending' && settings['notify_pending'] != true) return false;

      return true;
    }).toList();
  }

  static Future<int> getUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_notificationCountKey) ?? 0;
  }

  static Future<void> clearUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notificationCountKey, 0);
  }

  static Future<void> markAsRead(int notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_notificationCountKey) ?? 0;
    if (count > 0) {
      await prefs.setInt(_notificationCountKey, count - 1);
    }
  }

  static Future<void> showTestNotification() async {
    await _showLocalNotification(
      title: '🧪 Test Notification',
      body: 'This is a test notification from GASsight. If you see this, notifications are working!',
      payload: jsonEncode({'type': 'test'}),
    );
  }

  static Color getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.deepOrange;
      case 'moderate':
        return Colors.orange;
      case 'low':
        return Colors.green;
      case 'pending':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  static IconData getSeverityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Icons.error;
      case 'high':
        return Icons.warning_amber;
      case 'moderate':
        return Icons.info;
      case 'low':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      default:
        return Icons.notifications;
    }
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'enabled': prefs.getBool('notifications_enabled') ?? true,
      'notify_critical': prefs.getBool('notify_critical') ?? true,
      'notify_high': prefs.getBool('notify_high') ?? true,
      'notify_moderate': prefs.getBool('notify_moderate') ?? true,
      'notify_low': prefs.getBool('notify_low') ?? false,
      'notify_pending': prefs.getBool('notify_pending') ?? false,
      'same_municipality_only': prefs.getBool('same_municipality_only') ?? false,
      'same_province_only': prefs.getBool('same_province_only') ?? false,
      'use_distance_filter': prefs.getBool('use_distance_filter') ?? true,
      'max_distance_km': prefs.getDouble('max_distance_km') ?? 10.0,
      'polling_interval_minutes': prefs.getInt('polling_interval_minutes') ?? 5,
    };
  }

  static Future<void> updateSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool('notifications_enabled', settings['enabled'] ?? true);
    await prefs.setBool('notify_critical', settings['notify_critical'] ?? true);
    await prefs.setBool('notify_high', settings['notify_high'] ?? true);
    await prefs.setBool('notify_moderate', settings['notify_moderate'] ?? true);
    await prefs.setBool('notify_low', settings['notify_low'] ?? false);
    await prefs.setBool('notify_pending', settings['notify_pending'] ?? false);
    await prefs.setBool('same_municipality_only', settings['same_municipality_only'] ?? false);
    await prefs.setBool('same_province_only', settings['same_province_only'] ?? false);
    await prefs.setBool('use_distance_filter', settings['use_distance_filter'] ?? true);
    await prefs.setDouble('max_distance_km', settings['max_distance_km'] ?? 10.0);
    await prefs.setInt('polling_interval_minutes', settings['polling_interval_minutes'] ?? 5);

    print('✅ Notification settings updated');

    stopPolling();
    if (settings['enabled'] == true) {
      startPolling();
    }
  }
}