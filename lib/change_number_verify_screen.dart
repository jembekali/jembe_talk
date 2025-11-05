// Code ya: JEMBE TALK APP
// Dosiye: lib/change_number_verify_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';

class ChangeNumberVerifyScreen extends StatefulWidget {
  final String phoneNumber;
  const ChangeNumberVerifyScreen({super.key, required this.phoneNumber});

  @override
  State<ChangeNumberVerifyScreen> createState() => _ChangeNumberVerifyScreenState();
}

class _ChangeNumberVerifyScreenState extends State<ChangeNumberVerifyScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _isVerifying = false;
  int _resendTimer = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _sendOTP();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        if (mounted) setState(() => _resendTimer--);
      } else {
        _timer?.cancel();
      }
    });
  }

  Future<void> _sendOTP() async {
    debugPrint("Kurungika OTP kuri ${widget.phoneNumber}...");
  }

  Future<void> _resendOTP() async {
    if (_resendTimer == 0) {
      if (mounted) setState(() => _resendTimer = 60);
      _startResendTimer();
      await _sendOTP();
    }
  }

  Future<void> _verifyOTP() async {
    if (_pinController.text.length != 6) return;
    if (mounted) setState(() => _isVerifying = true);
    await Future.delayed(const Duration(seconds: 2));
    if (_pinController.text == "123456") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nimero yahinduwe neza!"), backgroundColor: Colors.green));
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code wanditse si yo."), backgroundColor: Colors.redAccent));
    }
    if (mounted) setState(() => _isVerifying = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultPinTheme = PinTheme(width: 56, height: 60, textStyle: const TextStyle(fontSize: 22, color: Colors.white), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.transparent)));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Emeza nimero"), backgroundColor: theme.appBarTheme.backgroundColor),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                // <<--- DORE IGIKOSOWE --->>
                "Twakurunikiye code y'ibiharuro 6 kuri nimero:",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: theme.textTheme.bodyMedium?.color),
              ),
              const SizedBox(height: 8),
              Text(widget.phoneNumber, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 32),
              Pinput(length: 6, controller: _pinController, defaultPinTheme: defaultPinTheme, focusedPinTheme: defaultPinTheme.copyWith(decoration: defaultPinTheme.decoration!.copyWith(border: Border.all(color: theme.colorScheme.secondary))), onCompleted: (pin) => _verifyOTP()),
              const SizedBox(height: 32),
              _isVerifying ? const CircularProgressIndicator() : SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _verifyOTP, child: const Text("EMEZA"))),
              const SizedBox(height: 24),
              TextButton(onPressed: _resendOTP, child: Text(_resendTimer > 0 ? "Subira urungike code mu ($_resendTimer)" : "Subira urungike code", style: TextStyle(color: _resendTimer > 0 ? Colors.grey : theme.colorScheme.secondary))),
            ],
          ),
        ),
      ),
    );
  }
}