// lib/online_contacts_screen.dart

import 'package:flutter/material.dart';

class OnlineContactsScreen extends StatefulWidget {
  const OnlineContactsScreen({super.key});

  @override
  State<OnlineContactsScreen> createState() => _OnlineContactsScreenState();
}

class _OnlineContactsScreenState extends State<OnlineContactsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Abari ku murongo"),
      ),
      body: const Center(
        // Tuzoshira urutonde rw'abantu hano mu nyuma
        child: Text("Iyi paji iriko irategurwa."),
      ),
    );
  }
}