import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../auth/countries.dart';
import '../auth/role_screens.dart';

class ProfileScreen extends StatefulWidget {
  final Profile profile;
  const ProfileScreen({super.key, required this.profile});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<ServiceRequest>? _jobs;

  bool get _mechanic => widget.profile.role == UserRole.mechanic;

  @override
  void initState() {
    super.initState();
    if (!_mechanic) {
      backend.myJobs(limit: 15).then((j) {
        if (mounted) setState(() => _jobs = j);
      }).catchError((_) {});
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _EditProfileScreen(profile: widget.profile)));
    if (saved == true) refreshSession();
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await backend.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final name = (p.fullName ?? '').trim().isEmpty ? 'Your profile' : p.fullName!;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(children: [
            InitialsAvatar(name: name, size: 60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: AppText.h2),
                const SizedBox(height: 4),
                Text([if (p.phone != null) p.phone!, if (p.email != null) p.email!].join(' · '), style: AppText.small),
                const SizedBox(height: 6),
                Pill(text: _mechanic ? 'Mechanic' : 'Driver', color: AppColors.ink, background: AppColors.signalSoft),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          _tile(Icons.person_outline_rounded, 'Name and phone', _edit),
          if (_mechanic)
            _tile(Icons.storefront_outlined, 'Workshop details', () async {
              final w = await backend.myWorkshop();
              if (!context.mounted) return;
              await Navigator.push(context, MaterialPageRoute(builder: (_) => WorkshopSetupScreen(existing: w)));
            }),
          _tile(Icons.help_outline_rounded, 'Help and safety', () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Help and safety'),
                  content: const Text(
                      'In danger on the road? Move to a safe spot, switch on your hazard lights and call 112.\n\nFor a problem with a job or payment, use "Report a problem" on the job. Your payment stays in escrow while we look into it.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                ),
              )),
          _tile(Icons.logout_rounded, 'Sign out', _signOut, color: AppColors.alert),
          if (!_mechanic && (_jobs ?? const []).isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Your jobs', style: AppText.h3),
            const SizedBox(height: 4),
            for (final j in _jobs!)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(j.serviceType, style: AppText.body.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
                      Text(formatDateTime(j.createdAt), style: AppText.small),
                    ]),
                  ),
                  if (j.quotedPriceKobo != null) Text(formatNaira(j.quotedPriceKobo!), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  Text(_statusLabel(j.status), style: AppText.small),
                ]),
              ),
          ],
          const SizedBox(height: 24),
          Center(child: Text('AutoWave${Env.demo ? ' · demo mode' : ''}', style: AppText.small)),
        ],
      ),
    );
  }

  String _statusLabel(RequestStatus s) => switch (s) {
        RequestStatus.completed => 'Done',
        RequestStatus.cancelled => 'Cancelled',
        RequestStatus.rejected => 'Declined',
        RequestStatus.expired => 'No response',
        _ => 'In progress',
      };

  Widget _tile(IconData icon, String title, VoidCallback onTap, {Color color = AppColors.ink}) => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(icon, color: color),
          title: Text(title, style: AppText.title.copyWith(color: color, fontSize: 15)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          onTap: onTap,
        ),
      );
}

class _EditProfileScreen extends StatefulWidget {
  final Profile profile;
  const _EditProfileScreen({required this.profile});
  @override
  State<_EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<_EditProfileScreen> {
  late final _name = TextEditingController(text: widget.profile.fullName ?? '');
  late Country _country = countryByCode(widget.profile.countryCode ?? Env.defaultCountry);
  late final _phone = TextEditingController(text: _national(widget.profile.phone));

  String _national(String? e164) {
    if (e164 == null) return '';
    final d = e164.replaceAll(RegExp(r'\D'), '');
    return d.startsWith(_country.dial) ? '0${d.substring(_country.dial.length)}' : d;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) throw const AppException('Enter your name.');
    if (!_country.looksValid(_phone.text)) throw const AppException('Check the phone number.');
    await backend.updateProfile(fullName: _name.text.trim(), phone: _country.toE164(_phone.text), countryCode: _country.code);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Name and phone')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 12),
          PhoneField(country: _country, onCountry: (c) => setState(() => _country = c), controller: _phone),
          const SizedBox(height: 24),
          BusyButton(label: 'Save', onPressed: _save),
        ],
      ),
    );
  }
}
