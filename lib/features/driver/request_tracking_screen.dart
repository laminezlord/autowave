import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_map.dart';
import '../../core/widgets/common.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../wallet/wallet_screen.dart';

/// Everything the driver sees after sending a request:
/// waiting -> accepted (pay into escrow) -> live map with ETA -> arrived ->
/// working -> done (release payment, rate the mechanic).
class RequestTrackingScreen extends StatefulWidget {
  final String requestId;
  const RequestTrackingScreen({super.key, required this.requestId});
  @override
  State<RequestTrackingScreen> createState() => _RequestTrackingScreenState();
}

class _RequestTrackingScreenState extends State<RequestTrackingScreen> {
  final _map = MapController();
  ServiceRequest? _req;
  MechanicPoint? _mech;
  List<LatLng>? _route;
  int? _etaSec;
  int? _etaMeters;
  Counterpart? _who;

  StreamSubscription<ServiceRequest?>? _reqSub;
  StreamSubscription<MechanicPoint?>? _mechSub;
  Timer? _etaTimer;
  Timer? _tick;
  bool _mapReady = false;
  bool _notFound = false;
  bool _expireCalled = false;
  bool _reviewPrompted = false;
  bool _reviewed = false;
  String? _subscribedMechanic;

  @override
  void initState() {
    super.initState();
    _reqSub = backend.watchRequest(widget.requestId).listen(_onRequest, onError: (_) {
      if (mounted && _req == null) setState(() => _notFound = true);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = _req;
      if (!mounted || r == null || r.status != RequestStatus.requested) return;
      if (!_expireCalled && r.respondBy.isBefore(DateTime.now())) {
        _expireCalled = true;
        backend.expireStale().catchError((_) {});
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _reqSub?.cancel();
    _mechSub?.cancel();
    _etaTimer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  // ---- Data -------------------------------------------------------------------
  void _onRequest(ServiceRequest? r) {
    if (!mounted) return;
    if (r == null) {
      setState(() => _notFound = true);
      return;
    }
    final prev = _req;
    setState(() {
      _req = r;
      if (r.etaSeconds != null) _etaSec = r.etaSeconds;
      if (r.distanceMeters != null) _etaMeters = r.distanceMeters;
    });
    if (prev?.status != r.status) _onStatusChanged(r);
    if (prev?.paymentStatus != r.paymentStatus && r.paymentStatus == PaymentStatus.released) _maybePromptReview();
  }

  void _onStatusChanged(ServiceRequest r) {
    final live = r.status == RequestStatus.accepted || r.status == RequestStatus.enRoute || r.status == RequestStatus.arrived;
    if (r.status != RequestStatus.requested) _loadCounterpart();

    if (live && _subscribedMechanic != r.mechanicId) {
      _subscribedMechanic = r.mechanicId;
      _mechSub?.cancel();
      _mechSub = backend.watchMechanicLocation(r.mechanicId).listen((p) {
        if (p == null || !mounted) return;
        setState(() => _mech = p);
        _fitCamera();
      }, onError: (_) {});
    }
    if (!live) {
      _mechSub?.cancel();
      _mechSub = null;
      _subscribedMechanic = null;
    }
    if (r.status == RequestStatus.enRoute) {
      _startEtaPolling();
    } else {
      _etaTimer?.cancel();
      _etaTimer = null;
      if (r.status != RequestStatus.accepted) _route = null;
    }
    if (r.status == RequestStatus.completed && r.paymentStatus == PaymentStatus.released) _maybePromptReview();
  }

  Future<void> _loadCounterpart() async {
    try {
      final c = await backend.counterpart(widget.requestId);
      if (mounted) setState(() => _who = c);
    } catch (_) {}
  }

  void _startEtaPolling() {
    if (_etaTimer != null) return;
    _refreshEta(includeRoute: true);
    _etaTimer = Timer.periodic(Duration(seconds: backend.isDemo ? 5 : 30), (_) => _refreshEta(includeRoute: _route == null || backend.isDemo));
  }

  Future<void> _refreshEta({required bool includeRoute}) async {
    try {
      final e = await backend.fetchEta(widget.requestId, includeRoute: includeRoute);
      if (!mounted) return;
      setState(() {
        _etaSec = e.seconds ?? _etaSec;
        _etaMeters = e.meters ?? _etaMeters;
        if (e.route != null && e.route!.isNotEmpty) _route = e.route;
        _mech ??= e.mechanic;
      });
      _fitCamera();
    } catch (_) {
      // Server ETA unavailable: estimate from straight-line distance.
      final r = _req, m = _mech;
      if (r != null && m != null && mounted) {
        final km = haversineKm(m.lat, m.lng, r.pickupLat, r.pickupLng);
        setState(() {
          _etaSec = roughEtaSeconds(km);
          _etaMeters = (km * 1000).round();
        });
      }
    }
  }

  void _fitCamera() {
    final r = _req;
    if (!_mapReady || r == null) return;
    final m = _mech;
    try {
      if (m == null) {
        _map.move(r.pickup, 15);
        return;
      }
      final sw = LatLng(math.min(m.lat, r.pickupLat), math.min(m.lng, r.pickupLng));
      final ne = LatLng(math.max(m.lat, r.pickupLat), math.max(m.lng, r.pickupLng));
      if (sw == ne) {
        _map.move(r.pickup, 16);
      } else {
        _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds(sw, ne), padding: const EdgeInsets.fromLTRB(60, 90, 60, 60), maxZoom: 16));
      }
    } catch (_) {}
  }

  // ---- Actions ----------------------------------------------------------------
  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text(_req?.paymentStatus == PaymentStatus.held
            ? 'The mechanic will be told, and your payment goes straight back to your wallet.'
            : 'The mechanic will be told.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppColors.alert), child: const Text('Cancel request')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await backend.cancelRequest(widget.requestId);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pay() async {
    final r = _req!;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _PayEscrowSheet(amountKobo: r.quotedPriceKobo!, mechanicName: _who?.name ?? 'your mechanic'),
    );
    if (ok != true || !mounted) return;
    try {
      await backend.fundEscrow(r.id);
      if (mounted) showSnack(context, '${formatNaira(r.quotedPriceKobo!)} is now held safely in escrow');
    } catch (e) {
      if (!mounted) return;
      if (friendlyError(e).contains('Not enough')) {
        final summary = await backend.walletSummary();
        if (!mounted) return;
        final added = await showTopUpSheet(context, summary, suggestedKobo: math.max(r.quotedPriceKobo! - summary.availableKobo, 10000));
        if (added == true && mounted) _pay();
      } else {
        showError(context, e);
      }
    }
  }

  Future<void> _release() async {
    final r = _req!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Release ${formatNaira(r.quotedPriceKobo!)}?'),
        content: Text('Only do this if ${_who?.name ?? 'the mechanic'} has finished the job and you\'re happy with it. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Release payment')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await backend.releaseEscrow(r.id);
      if (mounted) showSnack(context, 'Payment released. Thank you!');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _dispute() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report a problem'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Your payment stays on hold while AutoWave reviews what happened.'),
          const SizedBox(height: 12),
          TextField(controller: ctrl, maxLines: 3, autofocus: true, decoration: const InputDecoration(hintText: 'What went wrong?')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), style: TextButton.styleFrom(foregroundColor: AppColors.alert), child: const Text('Report')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      await backend.disputeEscrow(widget.requestId, reason);
      if (mounted) showSnack(context, 'Reported. We\'ll contact you within 24 hours.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _maybePromptReview() async {
    if (_reviewPrompted) return;
    _reviewPrompted = true;
    try {
      if (await backend.hasReviewed(widget.requestId)) {
        if (mounted) setState(() => _reviewed = true);
        return;
      }
    } catch (_) {}
    if (mounted) _openReview();
  }

  Future<void> _openReview() async {
    final r = _req;
    if (r == null) return;
    final res = await showModalBottomSheet<({int rating, String comment})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(mechanicName: _who?.name ?? 'your mechanic'),
    );
    if (res == null || !mounted) return;
    try {
      await backend.submitReview(requestId: r.id, mechanicId: r.mechanicId, rating: res.rating, comment: res.comment);
      if (mounted) setState(() => _reviewed = true);
      if (mounted) showSnack(context, 'Thanks for your review!');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _call() {
    final p = _who?.phone;
    if (p != null) launchUrl(Uri(scheme: 'tel', path: p.replaceAll(' ', '')));
  }

  // ---- Build ----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return _simple(Icons.search_off_rounded, 'Request not found', 'This request is no longer available.', 'Back to home');
    }
    final r = _req;
    if (r == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));

    switch (r.status) {
      case RequestStatus.requested:
        return _waiting(r);
      case RequestStatus.rejected:
        return _simple(Icons.sentiment_dissatisfied_rounded, 'Mechanic unavailable', 'This mechanic can\'t take your request right now. Try another one nearby.', 'Find another mechanic');
      case RequestStatus.expired:
        return _simple(Icons.timer_off_rounded, 'No response', 'The mechanic didn\'t respond in time. Try another one nearby.', 'Find another mechanic');
      case RequestStatus.cancelled:
        return _simple(Icons.cancel_outlined, 'Request cancelled',
            r.paymentStatus == PaymentStatus.refunded ? 'Your payment has been returned to your wallet.' : (r.cancelReason ?? 'This request was cancelled.'), 'Back to home');
      default:
        return _tracking(r);
    }
  }

  Widget _simple(IconData icon, String title, String body, String action) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: EmptyState(
          icon: icon,
          title: title,
          body: body,
          action: ElevatedButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: Text(action)),
        ),
      ),
    );
  }

  Widget _waiting(ServiceRequest r) {
    final left = r.respondBy.difference(DateTime.now()).inSeconds;
    final text = left > 0 ? '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}' : 'Checking…';
    return Scaffold(
      appBar: AppBar(title: const Text('Your request')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 5, color: AppColors.signal, backgroundColor: AppColors.line)),
              const SizedBox(height: 28),
              const Text('Waiting for the mechanic', style: AppText.h2),
              const SizedBox(height: 8),
              Text('They\'ll accept and send you a price.', style: AppText.body.copyWith(color: AppColors.muted)),
              const SizedBox(height: 18),
              Text(text, style: AppText.money),
              const SizedBox(height: 28),
              Panel(
                child: Row(children: [
                  const Icon(Icons.place_rounded, color: AppColors.ink),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.serviceType, style: AppText.title),
                      const SizedBox(height: 3),
                      Text(r.pickupAddress, style: AppText.small),
                    ]),
                  ),
                ]),
              ),
              const Spacer(),
              OutlinedButton(onPressed: _cancel, child: const Text('Cancel request')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tracking(ServiceRequest r) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AppMap(
              controller: _map,
              center: r.pickup,
              zoom: 15,
              route: r.status == RequestStatus.enRoute ? _route : null,
              pins: [
                MapPin(r.pickup, PinKind.you),
                if (_mech != null && (r.status == RequestStatus.accepted || r.status == RequestStatus.enRoute || r.status == RequestStatus.arrived))
                  MapPin(_mech!.latLng, PinKind.mechanic),
              ],
              onReady: () {
                _mapReady = true;
                _fitCamera();
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
              ),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _statusCard(r)),
        ],
      ),
    );
  }

  Widget _statusCard(ServiceRequest r) {
    final paid = r.paymentStatus == PaymentStatus.held;
    final headline = switch (r.status) {
      RequestStatus.accepted => 'Request accepted',
      RequestStatus.enRoute => 'On the way to you',
      RequestStatus.arrived => paid ? 'Your mechanic has arrived' : 'Arrived. Pay to let work start',
      RequestStatus.inProgress => 'Work in progress',
      RequestStatus.completed => 'Job complete',
      _ => '',
    };
    final showEta = r.status == RequestStatus.accepted || r.status == RequestStatus.enRoute;
    final canCancel = r.status == RequestStatus.accepted || r.status == RequestStatus.enRoute || r.status == RequestStatus.arrived;
    final price = r.quotedPriceKobo;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(headline, style: AppText.small.copyWith(color: AppColors.info, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (showEta)
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(formatEta(_etaSec ?? r.etaSeconds), style: AppText.money),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        [r.status == RequestStatus.accepted ? 'their estimate' : 'away', if ((_etaMeters ?? r.distanceMeters) != null) formatDistance(_etaMeters ?? r.distanceMeters)].join(' · '),
                        style: AppText.small,
                      ),
                    ),
                  ),
                ])
              else
                Text(r.serviceType, style: AppText.h2),
              const SizedBox(height: 16),
              Row(children: [
                InitialsAvatar(name: _who?.name ?? 'M', size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_who?.name ?? 'Your mechanic', style: AppText.title),
                    Text(r.serviceType, style: AppText.small),
                  ]),
                ),
                if (_who?.phone != null && r.status != RequestStatus.completed)
                  IconButton.filled(
                    onPressed: _call,
                    style: IconButton.styleFrom(backgroundColor: AppColors.goSoft, foregroundColor: AppColors.go),
                    icon: const Icon(Icons.call_rounded),
                    tooltip: 'Call ${_who!.phone}',
                  ),
              ]),
              if (price != null) ...[const SizedBox(height: 16), _paymentBlock(r, price)],
              if (_mech == null && r.status == RequestStatus.enRoute) ...[
                const SizedBox(height: 10),
                Text('Finding your mechanic on the map…', style: AppText.small),
              ],
              if (r.status == RequestStatus.completed && r.paymentStatus == PaymentStatus.released) ...[
                const SizedBox(height: 14),
                ElevatedButton(onPressed: _reviewed ? null : _openReview, child: Text(_reviewed ? 'Thanks for your review' : 'Rate your mechanic')),
                TextButton(onPressed: () => Navigator.of(context).popUntil((x) => x.isFirst), child: const Text('Back to home')),
              ],
              if (canCancel) ...[
                const SizedBox(height: 10),
                TextButton(onPressed: _cancel, style: TextButton.styleFrom(foregroundColor: AppColors.alert), child: const Text('Cancel request')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The escrow step: pay -> held -> release (or dispute).
  Widget _paymentBlock(ServiceRequest r, int price) {
    switch (r.paymentStatus) {
      case PaymentStatus.unpaid:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.signalSoft, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(child: Text('Mechanic\'s price', style: AppText.title)),
              Text(formatNaira(price), style: AppText.h3.copyWith(fontFamily: AppText.display, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            Text('Pay into escrow so work can start. The mechanic only gets the money after you confirm the job is done.', style: AppText.small.copyWith(color: AppColors.body)),
            const SizedBox(height: 12),
            ElevatedButton.icon(onPressed: _pay, icon: const Icon(Icons.lock_rounded, size: 18), label: Text('Pay ${formatNaira(price)} securely')),
          ]),
        );
      case PaymentStatus.held:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.goSoft, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.verified_user_rounded, color: AppColors.go),
              const SizedBox(width: 10),
              Expanded(child: Text('${formatNaira(price)} held in escrow', style: AppText.title.copyWith(color: AppColors.go))),
            ]),
            const SizedBox(height: 4),
            Text(
              r.status == RequestStatus.completed
                  ? 'Happy with the work? Release the payment to your mechanic.'
                  : 'The mechanic can see it\'s paid, but can\'t take it until you confirm the job is done.',
              style: AppText.small.copyWith(color: AppColors.body),
            ),
            if (r.status == RequestStatus.completed) ...[
              const SizedBox(height: 12),
              BusyButton(label: 'Confirm job and release ${formatNaira(price)}', background: AppColors.go, onPressed: _release),
              TextButton(onPressed: _dispute, style: TextButton.styleFrom(foregroundColor: AppColors.alert), child: const Text('Report a problem')),
            ],
          ]),
        );
      case PaymentStatus.released:
        return KeyValueRow('Paid to mechanic', formatNaira(price), strong: true);
      case PaymentStatus.refunded:
        return KeyValueRow('Refunded to your wallet', formatNaira(price), strong: true);
      case PaymentStatus.disputed:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.alertSoft, borderRadius: BorderRadius.circular(16)),
          child: Text('${formatNaira(price)} is on hold while we review your report. We\'ll contact you within 24 hours.', style: AppText.body.copyWith(color: AppColors.alert)),
        );
    }
  }
}

class _PayEscrowSheet extends StatelessWidget {
  final int amountKobo;
  final String mechanicName;
  const _PayEscrowSheet({required this.amountKobo, required this.mechanicName});

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: AppColors.go),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: AppText.body)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Pay ${formatNaira(amountKobo)} into escrow', style: AppText.h2),
        const SizedBox(height: 14),
        step(Icons.account_balance_wallet_rounded, 'The money leaves your AutoWave wallet now.'),
        step(Icons.lock_rounded, 'AutoWave holds it. $mechanicName sees it\'s paid but can\'t take it yet.'),
        step(Icons.check_circle_rounded, 'When the job is done, you confirm and it\'s released.'),
        step(Icons.undo_rounded, 'If the job is cancelled before work starts, you get it all back.'),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pay into escrow')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
      ]),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  final String mechanicName;
  const _ReviewSheet({required this.mechanicName});
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 0;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('How was ${widget.mechanicName}?', style: AppText.h2),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final on = _rating > i;
            return IconButton(
              onPressed: () => setState(() => _rating = i + 1),
              iconSize: 42,
              icon: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.star),
            );
          }),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _comment,
          maxLines: 3,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Tell other drivers about the service (optional)', fillColor: AppColors.surface),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _rating == 0 ? null : () => Navigator.pop(context, (rating: _rating, comment: _comment.text)),
          child: const Text('Submit review'),
        ),
      ]),
    );
  }
}
