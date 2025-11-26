import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _pinController = TextEditingController();
  String _error = "";

  @override
  void initState() {
    super.initState();
    _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    if (await AppLockService.biometricAvailable()) {
      final ok = await AppLockService.biometricAuthenticate();
      if (ok && mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _unlock() async {
    if (await AppLockService.verifyPin(_pinController.text.trim())) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = "Incorrect PIN");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C7A2C),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Unlock App",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: "Enter PIN",
                  ),
                ),
                if (_error.isNotEmpty)
                  Text(_error, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _unlock,
                  child: const Text("Unlock"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
