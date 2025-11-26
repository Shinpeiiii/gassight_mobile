import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'app_lock_screen.dart';
import 'services/app_lock_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const LoginScreen(),
    );
  }
}

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
