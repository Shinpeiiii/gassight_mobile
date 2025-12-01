import 'package:flutter/material.dart';
import 'services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loading = true);

    // Check for new notifications first
    await NotificationService.checkForNewNotifications();

    // Get stored notifications
    final notifications = await NotificationService.getStoredNotifications();
    
    // Filter by user settings
    final filteredNotifications = 
        await NotificationService.filterNotificationsBySettings(notifications);

    // Get unread count
    final count = await NotificationService.getUnreadCount();

    if (!mounted) return;

    setState(() {
      _notifications = filteredNotifications;
      _unreadCount = count;
      _loading = false;
    });
  }

  Future<void> _markAsRead(int index) async {
    final notification = _notifications[index];
    await NotificationService.markAsRead(notification['id']);
    
    if (!mounted) return;
    
    setState(() {
      if (_unreadCount > 0) _unreadCount--;
    });
  }

  Future<void> _clearAll() async {
    await NotificationService.clearUnreadCount();
    if (!mounted) return;
    
    setState(() => _unreadCount = 0);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ All notifications cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: const Color(0xFF2C7A2C),
        actions: [
          // Unread badge
          if (_unreadCount > 0)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_unreadCount new',
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
            ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
            tooltip: "Refresh",
          ),
          // Clear all
          if (_unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearAll,
              tooltip: "Clear All",
            ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              ).then((_) => _loadNotifications());
            },
            tooltip: "Settings",
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await NotificationService.showTestNotification();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🧪 Test notification sent!')),
          );
        },
        backgroundColor: const Color(0xFF2C7A2C),
        icon: const Icon(Icons.science),
        label: const Text('Test'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF2C7A2C)),
            SizedBox(height: 16),
            Text('Loading notifications...'),
          ],
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_off,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              "No notifications yet",
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              "You'll be notified about nearby infestations",
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: const Color(0xFF2C7A2C),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          return _buildNotificationCard(notification, index);
        },
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification, int index) {
    final severity = notification['severity'] ?? 'Info';
    final color = NotificationService.getSeverityColor(severity);
    final icon = NotificationService.getSeverityIcon(severity);
    final isSameMunicipality = notification['is_same_municipality'] ?? false;

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
        onTap: () {
          _markAsRead(index);
          _showNotificationDetails(notification);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification['title'] ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notification['date'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSameMunicipality)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'NEARBY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Message
              Text(
                notification['message'] ?? '',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 12),

              // Location
              Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      notification['location'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationDetails(Map<String, dynamic> notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              NotificationService.getSeverityIcon(
                  notification['severity'] ?? 'Info'),
              color: NotificationService.getSeverityColor(
                  notification['severity'] ?? 'Info'),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Alert Details')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notification['title'] ?? '',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                notification['message'] ?? '',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              _detailRow('Location', notification['location']),
              _detailRow('Severity', notification['severity']),
              _detailRow('Date', notification['date']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? 'N/A',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// NOTIFICATION SETTINGS SCREEN
// =====================================================================
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  Map<String, dynamic> _settings = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);

    final settings = await NotificationService.getSettings();

    if (!mounted) return;

    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    await NotificationService.updateSettings(_settings);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Settings saved successfully')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notification Settings'),
          backgroundColor: const Color(0xFF2C7A2C),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF2C7A2C)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: const Color(0xFF2C7A2C),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Enable/Disable
          _buildCard(
            child: SwitchListTile(
              title: const Text('Enable Notifications'),
              subtitle: const Text('Receive alerts about nearby infestations'),
              value: _settings['enabled'] ?? true,
              activeColor: const Color(0xFF2C7A2C),
              onChanged: (value) {
                setState(() => _settings['enabled'] = value);
              },
            ),
          ),

          const SizedBox(height: 16),

          // Severity Preferences
          _buildCard(
            title: 'Alert Severity Levels',
            children: [
              _buildCheckbox(
                'Critical',
                _settings['notify_critical'] ?? true,
                (value) => setState(() => _settings['notify_critical'] = value),
                Colors.red,
              ),
              _buildCheckbox(
                'High',
                _settings['notify_high'] ?? true,
                (value) => setState(() => _settings['notify_high'] = value),
                Colors.deepOrange,
              ),
              _buildCheckbox(
                'Moderate',
                _settings['notify_moderate'] ?? true,
                (value) => setState(() => _settings['notify_moderate'] = value),
                Colors.orange,
              ),
              _buildCheckbox(
                'Low',
                _settings['notify_low'] ?? false,
                (value) => setState(() => _settings['notify_low'] = value),
                Colors.green,
              ),
              _buildCheckbox(
                'Pending',
                _settings['notify_pending'] ?? false,
                (value) => setState(() => _settings['notify_pending'] = value),
                Colors.grey,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Location Filters
          _buildCard(
            title: 'Location Filters',
            children: [
              RadioListTile(
                title: const Text('Same Municipality (Recommended)'),
                subtitle: const Text('Get alerts from your municipality'),
                value: 'municipality',
                groupValue: _getLocationFilter(),
                activeColor: const Color(0xFF2C7A2C),
                onChanged: (value) => _setLocationFilter('municipality'),
              ),
              RadioListTile(
                title: const Text('Same Province'),
                subtitle: const Text('Get alerts from entire province'),
                value: 'province',
                groupValue: _getLocationFilter(),
                activeColor: const Color(0xFF2C7A2C),
                onChanged: (value) => _setLocationFilter('province'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard({String? title, Widget? child, List<Widget>? children}) {
    return Container(
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
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7A2C),
                ),
              ),
            ),
          if (child != null) child,
          if (children != null) ...children,
        ],
      ),
    );
  }

  Widget _buildCheckbox(
      String label, bool value, Function(bool) onChanged, Color color) {
    return CheckboxListTile(
      title: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
      value: value,
      activeColor: const Color(0xFF2C7A2C),
      onChanged: (value) => onChanged(value ?? false),
    );
  }

  String _getLocationFilter() {
    if (_settings['same_municipality_only'] == true) return 'municipality';
    if (_settings['same_province_only'] == true) return 'province';
    return 'municipality';
  }

  void _setLocationFilter(String filter) {
    setState(() {
      _settings['same_municipality_only'] = filter == 'municipality';
      _settings['same_province_only'] = filter == 'province';
    });
  }
}