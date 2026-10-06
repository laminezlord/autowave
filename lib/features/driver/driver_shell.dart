import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/place_search.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../learn/autolearn_screen.dart';
import '../profile/profile_screen.dart';
import '../recycling/recycling_screen.dart';
import '../wallet/wallet_screen.dart';
import 'mechanic_results_screen.dart';
import 'request_tracking_screen.dart';

class DriverShell extends StatefulWidget {
  final Profile profile;
  const DriverShell({super.key, required this.profile});
  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _tab = 0;
  final _walletKey = GlobalKey<WalletScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const DemoRibbon(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                DriverHomeScreen(profile: widget.profile, onOpenTab: (i) => setState(() => _tab = i)),
                WalletScreen(key: _walletKey, role: UserRole.driver),
                const RecyclingScreen(),
                const AutoLearnScreen(),
                ProfileScreen(profile: widget.profile),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) _walletKey.currentState?.refresh();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Find help'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.recycling_rounded), label: 'Recycle'),
          NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school_rounded), label: 'AutoLearn'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

/// The driver dashboard: an address search bar. Once an address is chosen,
/// the "Search for mechanics" button appears with service and budget options.
class DriverHomeScreen extends StatefulWidget {
  final Profile profile;
  final ValueChanged<int> onOpenTab;
  const DriverHomeScreen({super.key, required this.profile, required this.onOpenTab});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  Place? _place;
  String? _service;
  int? _budget = 1500000;
  ServiceRequest? _active;
  Timer? _poll;

  static const _budgets = <int?>[500000, 1000000, 1500000, 2500000, 5000000, null];

  @override
  void initState() {
    super.initState();
    _loadActive();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _loadActive());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadActive() async {
    try {
      final a = await backend.activeRequest();
      if (mounted) setState(() => _active = a);
    } catch (_) {}
  }

  Future<void> _pick() async {
    final p = await pickPlace(context, title: 'Where\'s the car?', near: _place);
    if (p != null) setState(() => _place = p);
  }

  Future<void> _search() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MechanicResultsScreen(place: _place!, budgetKobo: _budget, service: _service)),
    );
    _loadActive();
  }

  Future<void> _customBudget() async {
    final ctrl = TextEditingController();
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your budget'),
        content: TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₦ ', hintText: '12,000')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, parseNairaToKobo(ctrl.text)), child: const Text('Set budget')),
        ],
      ),
    );
    if (v != null && v > 0) setState(() => _budget = v);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadActive,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_active != null) ...[_activeBanner(_active!), const SizedBox(height: 20)],
                if (_place != null) ..._searchOptions() else ..._idle(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: AppColors.ink,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hi ${widget.profile.firstName}', style: const TextStyle(color: Color(0xFFC5CCD3), fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              const Text('Where\'s the car?', style: TextStyle(fontFamily: AppText.display, fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
              const SizedBox(height: 18),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _pick,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                    child: Row(
                      children: [
                        Icon(_place == null ? Icons.search_rounded : Icons.place_rounded, color: AppColors.ink),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _place?.address ?? 'Enter your address',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, fontWeight: _place == null ? FontWeight.w500 : FontWeight.w700, color: _place == null ? AppColors.muted : AppColors.ink),
                          ),
                        ),
                        if (_place != null)
                          GestureDetector(
                            onTap: () => setState(() => _place = null),
                            child: const Icon(Icons.close_rounded, color: AppColors.muted, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: List.generate(6, (i) => Container(width: 22, height: 4, margin: const EdgeInsets.only(right: 9), decoration: BoxDecoration(color: AppColors.signal, borderRadius: BorderRadius.circular(2))))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeBanner(ServiceRequest r) {
    final label = switch (r.status) {
      RequestStatus.requested => 'Waiting for the mechanic to respond',
      RequestStatus.accepted => r.paymentStatus == PaymentStatus.unpaid ? 'Accepted. Pay into escrow to lock it in' : 'Mechanic accepted your request',
      RequestStatus.enRoute => 'Your mechanic is on the way${r.etaSeconds != null ? ' · ${formatEta(r.etaSeconds)}' : ''}',
      RequestStatus.arrived => 'Your mechanic has arrived',
      RequestStatus.inProgress => 'Work in progress',
      RequestStatus.completed => 'Job done. Confirm to release payment',
      _ => 'Request in progress',
    };
    return Material(
      color: AppColors.signal,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => RequestTrackingScreen(requestId: r.id)));
          _loadActive();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.directions_car_filled_rounded, color: AppColors.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppText.title),
                const SizedBox(height: 2),
                Text('${r.serviceType} · tap to open', style: AppText.small.copyWith(color: AppColors.body)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.ink),
          ]),
        ),
      ),
    );
  }

  List<Widget> _idle() => [
        Text('Also on AutoWave', style: AppText.small.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _shortcut(Icons.recycling_rounded, AppColors.goSoft, AppColors.go, 'Recycle car parts', 'Old battery, tyres or engine oil? Get paid and keep them out of the gutter.', () => widget.onOpenTab(2)),
        const SizedBox(height: 10),
        _shortcut(Icons.school_rounded, AppColors.infoSoft, AppColors.info, 'Ask AutoLearn', 'Why is my engine light on? How do EV batteries work? Ask anything.', () => widget.onOpenTab(3)),
        const SizedBox(height: 10),
        _shortcut(Icons.verified_user_rounded, AppColors.signalSoft, AppColors.ink, 'How escrow protects you', 'You pay into AutoWave. The mechanic gets paid only when you confirm the job is done.', () => widget.onOpenTab(1)),
      ];

  Widget _shortcut(IconData icon, Color bg, Color fg, String title, String body, VoidCallback onTap) {
    return Panel(
      onTap: onTap,
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: fg)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppText.title),
            const SizedBox(height: 2),
            Text(body, style: AppText.small),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _searchOptions() => [
        const Text('What do you need?', style: AppText.h3),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(label: const Text('Not sure'), selected: _service == null, onSelected: (_) => setState(() => _service = null)),
            for (final s in kServiceTypes.skip(1))
              ChoiceChip(label: Text(s), selected: _service == s, onSelected: (_) => setState(() => _service = s)),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Your budget', style: AppText.h3),
        const SizedBox(height: 4),
        Text('We show mechanics within your budget first.', style: AppText.small),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in _budgets)
              ChoiceChip(label: Text(b == null ? 'Any price' : 'Up to ${formatNairaShort(b)}'), selected: _budget == b, onSelected: (_) => setState(() => _budget = b)),
            ChoiceChip(
              label: Text(_budget != null && !_budgets.contains(_budget) ? 'Up to ${formatNaira(_budget!)}' : 'Other amount'),
              selected: _budget != null && !_budgets.contains(_budget),
              onSelected: (_) => _customBudget(),
            ),
          ],
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.signal, foregroundColor: AppColors.ink, minimumSize: const Size.fromHeight(58)),
          onPressed: _active != null && _active!.status != RequestStatus.completed ? null : _search,
          icon: const Icon(Icons.manage_search_rounded),
          label: const Text('Search for mechanics'),
        ),
        if (_active != null && _active!.status != RequestStatus.completed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Finish or cancel your current request to search again.', textAlign: TextAlign.center, style: AppText.small),
          ),
      ];
}
