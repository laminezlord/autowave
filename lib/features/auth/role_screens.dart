import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/place_search.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import 'countries.dart';

class RoleSelectScreen extends StatefulWidget {
  final Profile profile;
  const RoleSelectScreen({super.key, required this.profile});
  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  UserRole? _role;
  late final _name = TextEditingController(text: widget.profile.fullName ?? '');
  final _phone = TextEditingController();
  late Country _country = countryByCode(widget.profile.countryCode ?? Env.defaultCountry);

  bool get _needsPhone => (widget.profile.phone ?? '').isEmpty;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_role == null) throw const AppException('Choose how you\'ll use AutoWave.');
    if (_name.text.trim().length < 2) throw const AppException('Enter your name.');
    String? phone;
    if (_needsPhone) {
      if (!_country.looksValid(_phone.text)) throw const AppException('Add a phone number so you can be reached on a job.');
      phone = _country.toE164(_phone.text);
    }
    await backend.setRole(_role!, fullName: _name.text.trim(), phone: phone, countryCode: _country.code);
    refreshSession();
  }

  Widget _choice(UserRole role, IconData icon, String title, String body) {
    final on = _role == role;
    return Panel(
      onTap: () => setState(() => _role = role),
      color: on ? AppColors.ink : Colors.white,
      borderColor: on ? AppColors.ink : AppColors.line,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: on ? AppColors.signal : AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: AppColors.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.title.copyWith(color: on ? Colors.white : AppColors.ink)),
              const SizedBox(height: 3),
              Text(body, style: AppText.small.copyWith(color: on ? const Color(0xFFC5CCD3) : AppColors.muted)),
            ]),
          ),
          Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: on ? AppColors.signal : AppColors.line),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: [TextButton(onPressed: backend.signOut, child: const Text('Sign out'))]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            const Text('How will you use AutoWave?', style: AppText.h1),
            const SizedBox(height: 8),
            Text('You can\'t switch later without contacting support.', style: AppText.body.copyWith(color: AppColors.muted)),
            const SizedBox(height: 24),
            _choice(UserRole.driver, Icons.directions_car_filled_rounded, 'I drive', 'Find mechanics, track them to you, pay safely, recycle and learn.'),
            const SizedBox(height: 12),
            _choice(UserRole.mechanic, Icons.build_rounded, 'I\'m a mechanic', 'Get job requests near your workshop and get paid through escrow.'),
            const SizedBox(height: 28),
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name')),
            if (_needsPhone) ...[
              const SizedBox(height: 12),
              PhoneField(country: _country, onCountry: (c) => setState(() => _country = c), controller: _phone),
            ],
            const SizedBox(height: 24),
            BusyButton(label: 'Continue', onPressed: _continue),
          ],
        ),
      ),
    );
  }
}

/// Mechanic's workshop details. Used once at sign-up and again from Profile.
class WorkshopSetupScreen extends StatefulWidget {
  final bool firstTime;
  final WorkshopProfile? existing;
  const WorkshopSetupScreen({super.key, this.firstTime = false, this.existing});
  @override
  State<WorkshopSetupScreen> createState() => _WorkshopSetupScreenState();
}

class _WorkshopSetupScreenState extends State<WorkshopSetupScreen> {
  late final _business = TextEditingController(text: widget.existing?.businessName ?? '');
  late final _bio = TextEditingController(text: widget.existing?.bio ?? '');
  late final _price = TextEditingController(text: widget.existing == null ? '' : (widget.existing!.minPriceKobo ~/ 100).toString());
  late final _years = TextEditingController(text: widget.existing == null ? '' : widget.existing!.yearsExperience.toString());
  late final Set<String> _services = {...?widget.existing?.services};
  late double _radius = (widget.existing?.serviceRadiusKm ?? 15).toDouble();
  late Place? _place = widget.existing == null
      ? null
      : Place(address: widget.existing!.baseAddress, title: widget.existing!.baseAddress, lat: widget.existing!.baseLat, lng: widget.existing!.baseLng);

  @override
  void dispose() {
    _business.dispose();
    _bio.dispose();
    _price.dispose();
    _years.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_business.text.trim().length < 2) throw const AppException('Add your business name.');
    if (_services.isEmpty) throw const AppException('Pick at least one service you offer.');
    final price = parseNairaToKobo(_price.text);
    if (price == null || price < 10000) throw const AppException('Set your starting price (at least ₦100).');
    if (_place == null) throw const AppException('Add your workshop location.');
    await backend.saveWorkshop(WorkshopProfile(
      businessName: _business.text.trim(),
      bio: _bio.text.trim(),
      services: _services.toList(),
      minPriceKobo: price,
      baseAddress: _place!.address,
      baseLat: _place!.lat,
      baseLng: _place!.lng,
      serviceRadiusKm: _radius.round(),
      yearsExperience: int.tryParse(_years.text.trim()) ?? 0,
    ));
    if (!mounted) return;
    if (widget.firstTime) {
      refreshSession();
    } else {
      showSnack(context, 'Workshop saved');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstTime ? '' : 'Workshop details'),
        actions: [if (widget.firstTime) TextButton(onPressed: backend.signOut, child: const Text('Sign out'))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            if (widget.firstTime) ...[
              const Text('Set up your workshop', style: AppText.h1),
              const SizedBox(height: 8),
              Text('Drivers see this when they search. Clear details get more requests.', style: AppText.body.copyWith(color: AppColors.muted)),
              const SizedBox(height: 24),
            ],
            TextField(controller: _business, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Business name', hintText: 'e.g. Tunde Auto Works')),
            const SizedBox(height: 20),
            const Text('Services you offer', style: AppText.title),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in kServiceTypes)
                  FilterChip(
                    label: Text(s),
                    selected: _services.contains(s),
                    onSelected: (v) => setState(() => v ? _services.add(s) : _services.remove(s)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Starting price', prefixText: '₦ ', helperText: 'Lowest you charge', helperMaxLines: 2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(controller: _years, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Years working', helperText: ' ')),
              ),
            ]),
            const SizedBox(height: 16),
            Panel(
              onTap: () async {
                final p = await pickPlace(context, title: 'Workshop location', hint: 'Where are you based?');
                if (p != null) setState(() => _place = p);
              },
              child: Row(children: [
                const Icon(Icons.storefront_rounded, color: AppColors.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Workshop location', style: AppText.small),
                    const SizedBox(height: 2),
                    Text(_place?.address ?? 'Search for your address', style: AppText.title.copyWith(color: _place == null ? AppColors.info : AppColors.ink)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ]),
            ),
            const SizedBox(height: 20),
            Text('I\'ll travel up to ${_radius.round()} km', style: AppText.title),
            Slider(value: _radius, min: 2, max: 50, divisions: 48, activeColor: AppColors.ink, onChanged: (v) => setState(() => _radius = v)),
            const SizedBox(height: 8),
            TextField(
              controller: _bio,
              maxLines: 3,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'About your workshop (optional)', hintText: 'What you\'re best at, brands you know, hours'),
            ),
            const SizedBox(height: 12),
            BusyButton(label: widget.firstTime ? 'Start getting jobs' : 'Save changes', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
