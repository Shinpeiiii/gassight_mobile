import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();
  String _error = "";

  Future<void> _savePin() async {
    if (_pin.text.length != 4) {
      setState(() => _error = "PIN must be 4 digits");
      return;
    }
    if (_pin.text != _confirmPin.text) {
      setState(() => _error = "PINs do not match");
      return;
    }

    await AppLockService.savePin(_pin.text);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Set App PIN")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _pin,
              maxLength: 4,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Enter PIN"),
            ),
            TextField(
              controller: _confirmPin,
              maxLength: 4,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Confirm PIN"),
            ),
            if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _savePin,
              child: const Text("Save"),
            )
          ],
        ),
      ),
    );
  }
}
