import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_map.dart';
import '../../core/widgets/common.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../learn/autolearn_screen.dart';
import '../profile/profile_screen.dart';
import '../wallet/wallet_screen.dart';

class MechanicShell extends StatefulWidget {
  final Profile profile;
  const MechanicShell({super.key, required this.profile});
  @override
  State<MechanicShell> createState() => _MechanicShellState();
}

class _MechanicShellState extends State<MechanicShell> {
  int _tab = 0;
  final _walletKey = GlobalKey<WalletScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        const DemoRibbon(),
        Expanded(
          child: IndexedStack(index: _tab, children: [
            MechanicDashboardScreen(profile: widget.profile),
            WalletScreen(key: _walletKey, role: UserRole.mechanic),
            const AutoLearnScreen(),
            ProfileScreen(profile: widget.profile),
          ]),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) _walletKey.currentState?.refresh();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.handyman_outlined), selectedIcon: Icon(Icons.handyman_rounded), label: 'Jobs'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school_rounded), label: 'AutoLearn'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

class MechanicDashboardScreen extends StatefulWidget {
  final Profile profile;
  const MechanicDashboardScreen({super.key, required this.profile});
  @override
  State<MechanicDashboardScreen> createState() => _MechanicDashboardScreenState();
}

class _MechanicDashboardScreenState extends State<MechanicDashboardScreen> {
  WorkshopProfile? _w;
  List<ServiceRequest>? _jobs;
  StreamSubscription<List<ServiceRequest>>? _sub;
  Timer? _tick;
  final _seenIncoming = <String>{};

  @override
  void initState() {
    super.initState();
    backend.myWorkshop().then((w) {
      if (mounted) setState(() => _w = w);
    });
    _listen();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_jobs ?? const []).any((j) => j.status == RequestStatus.requested)) setState(() {});
    });
  }

  void _listen() {
    _sub?.cancel();
    _sub = backend.watchMechanicJobs().listen((rows) {
      if (!mounted) return;
      final fresh = rows.where((r) => r.status == RequestStatus.requested && !_seenIncoming.contains(r.id)).toList();
      setState(() => _jobs = rows);
      for (final r in fresh) {
        _seenIncoming.add(r.id);
        showSnack(context, 'New request: ${r.serviceType}');
      }
      LocationPublisher.instance.sync(rows);
    }, onError: (e) {
      if (mounted) showError(context, e);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    LocationPublisher.instance.stop();
    super.dispose();
  }

  Future<void> _toggleOnline(bool v) async {
    final old = _w;
    setState(() => _w = _w?.copyWith(isOnline: v));
    try {
      await backend.setOnline(v);
      if (mounted) showSnack(context, v ? 'You\'re online. Drivers nearby can find you.' : 'You\'re offline. You won\'t get new requests.');
    } catch (e) {
      if (mounted) {
        setState(() => _w = old);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    final incoming = (jobs ?? const <ServiceRequest>[]).where((j) => j.status == RequestStatus.requested && j.respondBy.isAfter(DateTime.now())).toList();
    final active = (jobs ?? const <ServiceRequest>[])
        .where((j) => j.isActive && j.status != RequestStatus.requested || (j.status == RequestStatus.completed && j.paymentStatus == PaymentStatus.held))
        .toList();
    final history = (jobs ?? const <ServiceRequest>[]).where((j) => !incoming.contains(j) && !active.contains(j) && j.status != RequestStatus.requested).take(10).toList();

    return RefreshIndicator(
      onRefresh: () async => _listen(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (jobs == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else ...[
                if (incoming.isNotEmpty) ...[
                  Text(incoming.length == 1 ? 'New request' : '${incoming.length} new requests', style: AppText.h3),
                  const SizedBox(height: 10),
                  for (final j in incoming) Padding(padding: const EdgeInsets.only(bottom: 12), child: _IncomingCard(job: j, workshop: _w)),
                ],
                if (active.isNotEmpty) ...[
                  const Text('Current job', style: AppText.h3),
                  const SizedBox(height: 10),
                  for (final j in active) Padding(padding: const EdgeInsets.only(bottom: 12), child: _ActiveJobCard(job: j)),
                ],
                if (incoming.isEmpty && active.isEmpty)
                  EmptyState(
                    icon: (_w?.isOnline ?? true) ? Icons.notifications_active_outlined : Icons.do_not_disturb_on_outlined,
                    title: (_w?.isOnline ?? true) ? 'Waiting for requests' : 'You\'re offline',
                    body: (_w?.isOnline ?? true)
                        ? 'Keep the app open. New requests from drivers within ${_w?.serviceRadiusKm ?? 15} km show up here.'
                        : 'Go online to receive requests from drivers near your workshop.',
                  ),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Recent', style: AppText.h3),
                  const SizedBox(height: 4),
                  for (final j in history) _HistoryRow(job: j),
                ],
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final w = _w;
    final online = w?.isOnline ?? false;
    return Container(
      color: AppColors.ink,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w?.businessName ?? 'Your workshop', style: const TextStyle(fontFamily: AppText.display, fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.4)),
            const SizedBox(height: 4),
            Text(
              w == null ? '' : '${w.ratingCount == 0 ? 'No reviews yet' : '★ ${w.ratingAvg.toStringAsFixed(1)} from ${w.ratingCount} reviews'} · ${w.jobsCompleted} jobs done',
              style: const TextStyle(color: Color(0xFFC5CCD3), fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              decoration: BoxDecoration(color: online ? AppColors.go : const Color(0xFF223140), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Icon(online ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(online ? 'Online: taking requests' : 'Offline', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                Switch(
                  value: online,
                  onChanged: w == null ? null : _toggleOnline,
                  trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF0B5A40) : const Color(0xFF3B4A59)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  final ServiceRequest job;
  final WorkshopProfile? workshop;
  const _IncomingCard({required this.job, this.workshop});

  Future<void> _accept(BuildContext context) async {
    final res = await showModalBottomSheet<({int quote, int eta})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AcceptSheet(job: job, minPrice: workshop?.minPriceKobo, distanceKm: _km),
    );
    if (res == null) return;
    try {
      await backend.respondToRequest(job.id, accept: true, quoteKobo: res.quote, etaMinutes: res.eta);
      if (context.mounted) showSnack(context, 'Accepted. Waiting for the driver to pay into escrow.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _reject(BuildContext context) async {
    try {
      await backend.respondToRequest(job.id, accept: false);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  double? get _km => workshop == null ? null : haversineKm(workshop!.baseLat, workshop!.baseLng, job.pickupLat, job.pickupLng);

  @override
  Widget build(BuildContext context) {
    final left = job.respondBy.difference(DateTime.now()).inSeconds.clamp(0, 9999);
    final total = 180;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.signal, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: LinearProgressIndicator(value: left / total, minHeight: 5, color: AppColors.signal, backgroundColor: AppColors.signalSoft),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(job.serviceType, style: AppText.h3)),
              Text('${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')} to respond', style: AppText.small.copyWith(color: AppColors.alert, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            if ((job.description ?? '').isNotEmpty) ...[
              Text('"${job.description}"', style: AppText.body.copyWith(color: AppColors.ink)),
              const SizedBox(height: 8),
            ],
            Row(children: [
              const Icon(Icons.place_outlined, size: 18, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(job.pickupAddress, style: AppText.small)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              if (_km != null) ...[
                const Icon(Icons.route_rounded, size: 18, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(formatKm(_km!), style: AppText.small),
                const SizedBox(width: 14),
              ],
              if (job.budgetKobo != null) ...[
                const Icon(Icons.payments_outlined, size: 18, color: AppColors.muted),
                const SizedBox(width: 6),
                Text('Budget ${formatNaira(job.budgetKobo!)}', style: AppText.small.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700)),
              ],
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _reject(context), child: const Text('Decline'))),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.signal, foregroundColor: AppColors.ink, minimumSize: const Size.fromHeight(50)),
                  onPressed: () => _accept(context),
                  child: const Text('Accept'),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Matches the limit in respond_to_request() on the server.
const kMaxQuoteKobo = 500000000; // ₦5,000,000

class _AcceptSheet extends StatefulWidget {
  final ServiceRequest job;
  final int? minPrice;
  final double? distanceKm;
  const _AcceptSheet({required this.job, this.minPrice, this.distanceKm});
  @override
  State<_AcceptSheet> createState() => _AcceptSheetState();
}

class _AcceptSheetState extends State<_AcceptSheet> {
  late final _price = TextEditingController(text: (((widget.job.budgetKobo ?? widget.minPrice ?? 0)) ~/ 100).toString())
    // Pre-selected so typing replaces the suggested price instead of appending to it.
    ..selection = TextSelection(baseOffset: 0, extentOffset: (((widget.job.budgetKobo ?? widget.minPrice ?? 0)) ~/ 100).toString().length);
  late int _eta = widget.distanceKm == null ? 20 : ((roughEtaSeconds(widget.distanceKm!) / 60 / 5).ceil() * 5).clamp(5, 90);

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final etas = {5, 10, 15, 20, 30, 45, 60, _eta}.toList()..sort();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Accept this job', style: AppText.h2),
        const SizedBox(height: 4),
        Text('The driver pays this into escrow. You get it when they confirm the job is done.', style: AppText.small),
        const SizedBox(height: 18),
        TextField(
          controller: _price,
          autofocus: true,
          keyboardType: TextInputType.number,
          onTap: () => _price.selection = TextSelection(baseOffset: 0, extentOffset: _price.text.length),
          style: AppText.h2,
          decoration: InputDecoration(
            labelText: 'Your price',
            prefixText: '₦ ',
            helperText: widget.job.budgetKobo == null ? null : 'Driver\'s budget: ${formatNaira(widget.job.budgetKobo!)}',
          ),
        ),
        const SizedBox(height: 18),
        const Text('How soon can you get there?', style: AppText.title),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in etas) ChoiceChip(label: Text('$e min'), selected: _eta == e, onSelected: (_) => setState(() => _eta = e)),
        ]),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            final k = parseNairaToKobo(_price.text);
            if (k == null || k < 10000) {
              showSnack(context, 'Enter your price (at least ₦100).');
              return;
            }
            if (k > kMaxQuoteKobo) {
              showSnack(context, 'That price looks too high. The most you can quote is ${formatNaira(kMaxQuoteKobo)}.');
              return;
            }
            Navigator.pop(context, (quote: k, eta: _eta));
          },
          child: const Text('Accept and send price'),
        ),
      ]),
    );
  }
}

class _ActiveJobCard extends StatefulWidget {
  final ServiceRequest job;
  const _ActiveJobCard({required this.job});
  @override
  State<_ActiveJobCard> createState() => _ActiveJobCardState();
}

class _ActiveJobCardState extends State<_ActiveJobCard> {
  Counterpart? _driver;

  @override
  void initState() {
    super.initState();
    backend.counterpart(widget.job.id).then((c) {
      if (mounted) setState(() => _driver = c);
    }).catchError((_) {});
  }

  Future<void> _move(RequestStatus s) async {
    if (s == RequestStatus.enRoute) {
      final ok = await LocationPublisher.instance.ensurePermission();
      if (!ok && mounted) showSnack(context, 'Allow location so the driver can see you coming.');
    }
    await backend.updateJobStatus(widget.job.id, s);
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this job?'),
        content: const Text('The driver is told straight away and gets any payment back. Cancelling often can lower your ranking.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep job')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppColors.alert), child: const Text('Cancel job')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await backend.cancelRequest(widget.job.id, reason: 'Cancelled by the mechanic');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _navigate() {
    final j = widget.job;
    launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${j.pickupLat},${j.pickupLng}&travelmode=driving'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    final paid = j.paymentStatus == PaymentStatus.held;
    final (String? label, RequestStatus? next) = switch (j.status) {
      RequestStatus.accepted => ('Start trip', RequestStatus.enRoute),
      RequestStatus.enRoute => ('I\'ve arrived', RequestStatus.arrived),
      RequestStatus.arrived => ('Start work', RequestStatus.inProgress),
      RequestStatus.inProgress => ('Mark job complete', RequestStatus.completed),
      _ => (null, null),
    };
    final stage = switch (j.status) {
      RequestStatus.accepted => 'Accepted',
      RequestStatus.enRoute => 'On your way · sharing location',
      RequestStatus.arrived => 'At the car',
      RequestStatus.inProgress => 'Working',
      RequestStatus.completed => 'Done · waiting for the driver to confirm',
      _ => '',
    };
    final blockedByPayment = j.status == RequestStatus.arrived && !paid;

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 130,
          child: AppMap(center: j.pickup, zoom: 14.5, interactive: false, pins: [MapPin(j.pickup, PinKind.you)]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(stage, style: AppText.small.copyWith(color: AppColors.info, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(j.serviceType, style: AppText.h3),
            const SizedBox(height: 2),
            Text(j.pickupAddress, style: AppText.small),
            const SizedBox(height: 12),
            Row(children: [
              InitialsAvatar(name: _driver?.name ?? 'D', size: 40, background: AppColors.infoSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_driver?.name ?? 'Driver', style: AppText.title),
                  if (_driver?.phone != null) Text(_driver!.phone!, style: AppText.small),
                ]),
              ),
              if (_driver?.phone != null)
                IconButton.filled(
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: _driver!.phone!.replaceAll(' ', ''))),
                  style: IconButton.styleFrom(backgroundColor: AppColors.goSoft, foregroundColor: AppColors.go),
                  icon: const Icon(Icons.call_rounded),
                ),
              const SizedBox(width: 6),
              if (j.status == RequestStatus.accepted || j.status == RequestStatus.enRoute)
                IconButton.filled(
                  onPressed: _navigate,
                  style: IconButton.styleFrom(backgroundColor: AppColors.infoSoft, foregroundColor: AppColors.info),
                  icon: const Icon(Icons.navigation_rounded),
                  tooltip: 'Directions',
                ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: paid ? AppColors.goSoft : AppColors.signalSoft, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(paid ? Icons.verified_user_rounded : Icons.hourglass_top_rounded, size: 20, color: paid ? AppColors.go : AppColors.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    paid ? '${formatNaira(j.quotedPriceKobo ?? 0)} secured in escrow' : 'Waiting for the driver to pay ${formatNaira(j.quotedPriceKobo ?? 0)}',
                    style: AppText.body.copyWith(color: paid ? AppColors.go : AppColors.ink, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
            if (label != null) ...[
              const SizedBox(height: 12),
              BusyButton(
                label: blockedByPayment ? 'Start work (waiting for payment)' : label,
                background: next == RequestStatus.completed ? AppColors.go : null,
                onPressed: blockedByPayment ? null : () => _move(next!),
              ),
            ],
            if (j.status == RequestStatus.accepted || j.status == RequestStatus.enRoute || j.status == RequestStatus.arrived)
              TextButton(onPressed: _cancel, style: TextButton.styleFrom(foregroundColor: AppColors.alert), child: const Text('Cancel job')),
          ]),
        ),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final ServiceRequest job;
  const _HistoryRow({required this.job});

  @override
  Widget build(BuildContext context) {
    final (String text, Color color) = switch (job.status) {
      RequestStatus.completed => (job.paymentStatus == PaymentStatus.released ? 'Paid' : job.paymentStatus == PaymentStatus.disputed ? 'Disputed' : 'Done', AppColors.go),
      RequestStatus.rejected => ('Declined', AppColors.muted),
      RequestStatus.expired => ('Missed', AppColors.alert),
      RequestStatus.cancelled => ('Cancelled', AppColors.muted),
      _ => ('', AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(job.serviceType, style: AppText.body.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
            Text(formatDateTime(job.createdAt), style: AppText.small),
          ]),
        ),
        if (job.quotedPriceKobo != null && job.status == RequestStatus.completed)
          Padding(padding: const EdgeInsets.only(right: 10), child: Text(formatNaira(job.quotedPriceKobo!), style: const TextStyle(fontWeight: FontWeight.w800))),
        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

/// Shares the mechanic's live position with the driver, but ONLY while a job is
/// "en route". Starts on "Start trip", stops on arrival, cancellation or finish.
class LocationPublisher {
  LocationPublisher._();
  static final LocationPublisher instance = LocationPublisher._();

  StreamSubscription<Position>? _sub;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool get isRunning => _sub != null;

  Future<bool> ensurePermission() async {
    if (backend.isDemo) return true;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p != LocationPermission.denied && p != LocationPermission.deniedForever;
  }

  Future<void> sync(List<ServiceRequest> jobs) async {
    if (backend.isDemo) return;
    final needs = jobs.any((j) => j.status == RequestStatus.enRoute);
    if (needs && !isRunning) {
      await start();
    } else if (!needs && isRunning) {
      await stop();
    }
  }

  Future<void> start() async {
    if (isRunning || !await ensurePermission()) return;
    final LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'AutoWave',
          notificationText: 'Sharing your location with the driver',
          enableWakeLock: true,
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    }
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition, onError: (_) {});
    try {
      await _send(await Geolocator.getCurrentPosition(locationSettings: settings));
    } catch (_) {}
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _onPosition(Position p) async {
    if (DateTime.now().difference(_lastSent) < const Duration(seconds: 4)) return;
    await _send(p);
  }

  Future<void> _send(Position p) async {
    _lastSent = DateTime.now();
    try {
      await backend.publishLocation(p.latitude, p.longitude, p.heading >= 0 ? p.heading : null);
    } catch (_) {}
  }
}

// Keeps latlong2 import used for map pins on this screen.
LatLng latLngOf(ServiceRequest r) => r.pickup;
