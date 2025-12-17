import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // <<< PROVIDER
import 'package:jembe_talk/language_provider.dart'; // <<< LANGUAGE PROVIDER

class ReportDisplayScreen extends StatelessWidget {
  final Map<String, dynamic> reportData;
  const ReportDisplayScreen({super.key, required this.reportData});

  // Ubu buryo buhindura amakuru yacu ubutumwa bwo gukoporora
  String _generateReportText(Map<String, dynamic> formattedData, String header) {
    var report = "$header\n";
    report += "--------------------------------------\n\n";
    formattedData.forEach((key, value) {
      report += "${key.toUpperCase()}:\n$value\n\n";
    });
    return report;
  }

  void _copyReportToClipboard(BuildContext context, String text, String successMessage) {
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage), backgroundColor: Colors.green),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context); // PROVIDER

    // Duhinduye formattedData kugira ikoreshe amagambo y'indimi
    final formattedData = {
      lang.t('label_name'): reportData['displayName'] ?? reportData['email'] ?? lang.t('unknown'),
      lang.t('label_about'): reportData['about'] ?? lang.t('no_data'),
      lang.t('label_phone'): reportData['phoneNumber'] ?? lang.t('no_data'),
      lang.t('label_join_date'): _formatTimestamp(reportData['createdAt'], lang.currentLanguage),
    };

    return Scaffold(
      appBar: AppBar(title: Text(lang.t('report_title'))), // "Raporo ya Konte Yawe"
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: formattedData.entries.map((entry) {
          return _buildReportRow(context, title: entry.key, value: entry.value?.toString());
        }).toList(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final reportText = _generateReportText(formattedData, lang.t('report_header'));
          _copyReportToClipboard(context, reportText, lang.t('report_copied'));
        },
        label: Text(lang.t('report_btn_copy')), // "Koporora Raporo"
        icon: const Icon(Icons.copy_all_outlined),
      ),
    );
  }

  Widget _buildReportRow(BuildContext context, {required String title, String? value}) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: TextStyle(color: theme.colorScheme.secondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value ?? lang.t('no_data'), style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 16)),
          const SizedBox(height: 8),
          Divider(color: theme.dividerColor.withAlpha(60)),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp, String langCode) {
    if (timestamp == null) return "Ntibizwi";
    try {
      final dt = (timestamp as Timestamp).toDate();
      // Koresha langCode kugira italiki ijyane n'ururimi
      return DateFormat.yMMMMd(langCode).add_Hm().format(dt);
    } catch (e) {
      return "Ntibiboneka";
    }
  }
}