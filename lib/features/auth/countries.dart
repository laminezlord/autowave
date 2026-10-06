import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class Country {
  final String code; // ISO 3166-1 alpha-2
  final String name;
  final String dial; // without +
  final int nationalLength; // typical digits after the country code (for a light check)
  const Country(this.code, this.name, this.dial, this.nationalLength);

  String get flag => String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 65));

  /// "0803 123 4567" -> "+2348031234567"
  String toE164(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith(dial) && digits.length > nationalLength) digits = digits.substring(dial.length);
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '+$dial$digits';
  }

  bool looksValid(String input) {
    final e = toE164(input);
    final national = e.length - 1 - dial.length;
    return national >= nationalLength - 1 && national <= nationalLength + 1;
  }
}

/// African countries first (AutoWave's markets), then a few others.
const kCountries = <Country>[
  Country('NG', 'Nigeria', '234', 10),
  Country('GH', 'Ghana', '233', 9),
  Country('KE', 'Kenya', '254', 9),
  Country('ZA', 'South Africa', '27', 9),
  Country('EG', 'Egypt', '20', 10),
  Country('MA', 'Morocco', '212', 9),
  Country('CI', "Côte d'Ivoire", '225', 10),
  Country('SN', 'Senegal', '221', 9),
  Country('CM', 'Cameroon', '237', 9),
  Country('BJ', 'Benin', '229', 10),
  Country('TG', 'Togo', '228', 8),
  Country('RW', 'Rwanda', '250', 9),
  Country('UG', 'Uganda', '256', 9),
  Country('TZ', 'Tanzania', '255', 9),
  Country('ET', 'Ethiopia', '251', 9),
  Country('ZM', 'Zambia', '260', 9),
  Country('ZW', 'Zimbabwe', '263', 9),
  Country('BW', 'Botswana', '267', 8),
  Country('AO', 'Angola', '244', 9),
  Country('DZ', 'Algeria', '213', 9),
  Country('TN', 'Tunisia', '216', 8),
  Country('LR', 'Liberia', '231', 9),
  Country('SL', 'Sierra Leone', '232', 8),
  Country('GM', 'Gambia', '220', 7),
  Country('GB', 'United Kingdom', '44', 10),
  Country('US', 'United States', '1', 10),
  Country('CA', 'Canada', '1', 10),
  Country('AE', 'United Arab Emirates', '971', 9),
  Country('DE', 'Germany', '49', 11),
  Country('FR', 'France', '33', 9),
  Country('CN', 'China', '86', 11),
  Country('IN', 'India', '91', 10),
];

Country countryByCode(String? code) =>
    kCountries.firstWhere((c) => c.code == (code ?? '').toUpperCase(), orElse: () => kCountries.first);

/// Bottom sheet with a searchable country list.
Future<Country?> pickCountry(BuildContext context) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CountrySheet(),
  );
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet();
  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = kCountries
        .where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q.toLowerCase()) || c.dial.contains(_q.replaceAll('+', '')))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'Search country or code', prefixIcon: Icon(Icons.search_rounded), fillColor: AppColors.surface),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: Text('+${c.dial}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone field with the country button on the left.
class PhoneField extends StatelessWidget {
  final Country country;
  final ValueChanged<Country> onCountry;
  final TextEditingController controller;
  final bool autofocus;
  final String? hint;

  const PhoneField({super.key, required this.country, required this.onCountry, required this.controller, this.autofocus = false, this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final c = await pickCountry(context);
              if (c != null) onCountry(c);
            },
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: Row(
                children: [
                  Text(country.flag, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 6),
                  Text('+${country.dial}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const Icon(Icons.expand_more_rounded, size: 20, color: AppColors.muted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: 0.5),
            decoration: InputDecoration(hintText: hint ?? (country.code == 'NG' ? '0803 123 4567' : 'Phone number')),
          ),
        ),
      ],
    );
  }
}
