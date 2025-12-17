// lib/contact_us_screen.dart

import 'package:flutter/material.dart';

class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Twandikire"),
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Dusobanurire ikibazo cawe. Turagerageza kugufasha vuba bishoboka.",
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            const SizedBox(height: 24),
            TextField(
              maxLines: 8,
              decoration: InputDecoration(
                hintText: "Andika ikibazo cawe hano...",
                border: const OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: theme.colorScheme.secondary),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondary,
                  foregroundColor: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Ubutumwa bwawe bwarungitswe. Urakoze!")),
                  );
                  Navigator.of(context).pop();
                },
                child: const Text("Rungika"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}