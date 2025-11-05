// Code ya: JEMBE TALK APP
// Dosiye: lib/change_number_input_screen.dart

import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
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

  // TWAKUYEHO '_oldCountryCode'
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
      
      // Hano tuzohuza n'ibikorwa vya Firebase vyo gusuzuma ko nimero ya kera ibaho koko
      // Ariko ubu, turabandanya gusa
      
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
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Shiramwo nimero nshasha"),
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
              labelText: "Nimero ya kera",
              // TWAKUYEHO 'onCountryChanged' KUKO TUTAYIKENEye
            ),
            const SizedBox(height: 24),

            _buildPhoneNumberInput(
              context: context,
              controller: _newNumberController,
              labelText: "Nimero nshasha",
              onCountryChanged: (country) => _newCountryCode = country.dialCode!,
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
                child: const Text("EMEZA", style: TextStyle(fontSize: 16)),
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
    void Function(CountryCode)? onCountryChanged, // Ubu ntabwo itegetswe
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
            hintText: '7X XXX XXX',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.colorScheme.secondary),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Utegerezwa kuzuza aha hantu.';
            }
            if (value.length < 8) {
              return 'Nimero igaragara nkaho ituzuye.';
            }
            return null;
          },
        ),
      ],
    );
  }
}