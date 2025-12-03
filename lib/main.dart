import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'user_dashboard.dart';
import 'app_lock_screen.dart';
import 'services/app_lock_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notifications
  await NotificationService.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GASsight',
      navigatorObservers: [LifecycleObserver()],
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF2C7A2C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2C7A2C),
          primary: const Color(0xFF2C7A2C),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// Splash screen to check login status
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    // Wait a bit for splash effect
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    // Check if user is logged in
    final token = await AuthService.getValidAccessToken();

    if (!mounted) return;

    if (token != null) {
      // User is logged in, go to dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UserDashboard()),
      );
    } else {
      // User not logged in, go to login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C7A2C),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.eco,
                size: 60,
                color: Color(0xFF2C7A2C),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              "GASsight",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Golden Apple Snail Monitoring",
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}

// Lifecycle observer for app lock
class LifecycleObserver extends NavigatorObserver with WidgetsBindingObserver {
  LifecycleObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final hasPin = await AppLockService.hasPin();
      if (!hasPin) return;

      navigator?.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const AppLockScreen(),
        ),
      );
    }
  }
}