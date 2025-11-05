// Code ya: JEMBE TALK APP
// Dosiye: lib/report_display_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // TWONGEYEMWO IYI DOSIYE NGO DUKOPORE
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReportDisplayScreen extends StatelessWidget {
  final Map<String, dynamic> reportData;
  const ReportDisplayScreen({super.key, required this.reportData});

  // Ubu buryo buhindura amakuru yacu ubutumwa bwo gukoporora
  String _generateReportText(Map<String, dynamic> formattedData) {
    var report = "RAPORO YA KONTE YANJE KURI JEMBE TALK\n";
    report += "--------------------------------------\n\n";
    formattedData.forEach((key, value) {
      report += "${key.toUpperCase()}:\n$value\n\n";
    });
    return report;
  }

  // Igikorwa co gukoporora
  void _copyReportToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Raporo yakoporowe neza!"), backgroundColor: Colors.green),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final formattedData = {
      "Izina rya porofili": reportData['email'],
      "Amajambo akuranga": reportData['about'],
      "Nimero ya Terefone": reportData['phoneNumber'],
      "Igihe watanguruyeko gukoresha Jembe Talk": _formatTimestamp(reportData['createdAt']),
    };

    return Scaffold(
      appBar: AppBar(title: const Text("Raporo ya Konte Yawe")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: formattedData.entries.map((entry) {
          return _buildReportRow(context, title: entry.key, value: entry.value?.toString());
        }).toList(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final reportText = _generateReportText(formattedData);
          _copyReportToClipboard(context, reportText);
        },
        label: const Text("Koporora Raporo"),
        icon: const Icon(Icons.copy_all_outlined),
      ),
    );
  }

  Widget _buildReportRow(BuildContext context, {required String title, String? value}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: TextStyle(color: theme.colorScheme.secondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value ?? "Nta makuru", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 16)),
          const SizedBox(height: 8),
          Divider(color: theme.dividerColor.withAlpha(60)),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "Ntibizwi";
    try {
      final dt = (timestamp as Timestamp).toDate();
      return DateFormat.yMMMMd('fr_BI').add_Hm().format(dt);
    } catch (e) {
      return "Ntibiboneka";
    }
  }
}