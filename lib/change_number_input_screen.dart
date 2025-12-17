import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:provider/provider.dart'; // Provider
import 'package:jembe_talk/language_provider.dart'; // LanguageProvider
import 'package:jembe_talk/change_number_verify_screen.dart';
import 'package:jembe_talk/custom_page_route.dart';

class ChangeNumberInputScreen extends StatefulWidget {
  const ChangeNumberInputScreen({super.key});

  @override
  State<ChangeNumberInputScreen> createState() => _ChangeNumberInputScreenState();
}

class _ChangeNumberInputScreenState extends State<ChangeNumberInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _oldNumberController = TextEditingController();
  final TextEditingController _newNumberController = TextEditingController();

  String _newCountryCode = '+257';

  @override
  void dispose() {
    _oldNumberController.dispose();
    _newNumberController.dispose();
    super.dispose();
  }

  void _proceedToNextStep() {
    if (_formKey.currentState!.validate()) {
      final newNumber = _newCountryCode + _newNumberController.text.trim();
      
      Navigator.push(
        context,
        SlideRightPageRoute(
          page: ChangeNumberVerifyScreen(phoneNumber: newNumber),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context); // Provider

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(lang.t('chg_num_input_title')), // "Shiramwo nimero nshasha"
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 1,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          children: [
            const Center(
              child: Icon(Icons.screen_rotation_outlined, size: 60, color: Colors.tealAccent),
            ),
            const SizedBox(height: 20),

            _buildPhoneNumberInput(
              context: context,
              controller: _oldNumberController,
              labelText: lang.t('chg_num_label_old'), // "Nimero ya kera"
              lang: lang,
            ),
            const SizedBox(height: 24),

            _buildPhoneNumberInput(
              context: context,
              controller: _newNumberController,
              labelText: lang.t('chg_num_label_new'), // "Nimero nshasha"
              onCountryChanged: (country) => _newCountryCode = country.dialCode!,
              lang: lang,
            ),
            const SizedBox(height: 40),

            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _proceedToNextStep,
                child: Text(lang.t('btn_confirm'), style: const TextStyle(fontSize: 16)), // "EMEZA"
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneNumberInput({
    required BuildContext context,
    required TextEditingController controller,
    required String labelText,
    required LanguageProvider lang,
    void Function(CountryCode)? onCountryChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labelText, style: TextStyle(color: theme.colorScheme.secondary, fontSize: 14)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            prefixIcon: CountryCodePicker(
              onChanged: onCountryChanged,
              initialSelection: 'BI',
              favorite: const ['+257','BI'],
              showCountryOnly: false,
              showOnlyCountryWhenClosed: false,
              alignLeft: false,
              textStyle: TextStyle(color: theme.textTheme.bodyLarge?.color),
            ),
            hintText: lang.t('chg_num_hint'), // "7X XXX XXX"
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.colorScheme.secondary),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return lang.t('chg_num_error_empty'); // "Utegerezwa kuzuza aha hantu."
            }
            if (value.length < 8) {
              return lang.t('chg_num_error_length'); // "Nimero igaragara nkaho ituzuye."
            }
            return null;
          },
        ),
      ],
    );
  }
}