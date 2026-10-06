import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_map.dart';
import '../../core/widgets/common.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import 'request_tracking_screen.dart';

class MechanicResultsScreen extends StatefulWidget {
  final Place place;
  final int? budgetKobo;
  final String? service;
  const MechanicResultsScreen({super.key, required this.place, this.budgetKobo, this.service});
  @override
  State<MechanicResultsScreen> createState() => _MechanicResultsScreenState();
}

class _MechanicResultsScreenState extends State<MechanicResultsScreen> {
  List<MechanicSummary>? _list;
  Object? _error;
  double _radius = 15;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _list = null;
      _error = null;
    });
    try {
      final r = await backend.searchMechanics(lat: widget.place.lat, lng: widget.place.lng, budgetKobo: widget.budgetKobo, service: widget.service, radiusKm: _radius);
      if (mounted) setState(() => _list = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final inBudget = list?.where((m) => m.withinBudget).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.service ?? 'Mechanics near you'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.place.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SizedBox(
              height: 190,
              child: AppMap(
                center: widget.place.latLng,
                zoom: 12.6,
                interactive: false,
                pins: [
                  MapPin(widget.place.latLng, PinKind.you),
                  for (final m in list ?? const <MechanicSummary>[]) MapPin(LatLng(m.lat, m.lng), PinKind.workshop),
                ],
              ),
            ),
            if (_error != null)
              EmptyState(icon: Icons.wifi_off_rounded, title: 'Search didn\'t work', body: friendlyError(_error!), action: OutlinedButton(onPressed: _load, child: const Text('Try again')))
            else if (list == null)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else if (list.isEmpty)
              EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No mechanics online nearby',
                body: 'Nobody within ${_radius.round()} km is available right now. Search a wider area or try again in a few minutes.',
                action: _radius < 50
                    ? ElevatedButton(
                        onPressed: () {
                          _radius = 50;
                          _load();
                        },
                        child: const Text('Search up to 50 km'))
                    : null,
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Text(
                  widget.budgetKobo == null
                      ? '${list.length} available near you'
                      : '$inBudget of ${list.length} within ${formatNaira(widget.budgetKobo!)}',
                  style: AppText.h3,
                ),
              ),
              for (final m in list)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _MechanicCard(
                    m: m,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => MechanicDetailScreen(mechanic: m, place: widget.place, budgetKobo: widget.budgetKobo, service: widget.service)),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MechanicCard extends StatelessWidget {
  final MechanicSummary m;
  final VoidCallback onTap;
  const _MechanicCard({required this.m, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(name: m.businessName, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.businessName, style: AppText.title),
                  const SizedBox(height: 4),
                  RatingInline(avg: m.ratingAvg, count: m.ratingCount),
                  const SizedBox(height: 4),
                  Text('${formatKm(m.distanceKm)} · ${m.jobsCompleted} jobs done', style: AppText.small),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('from', style: AppText.small.copyWith(fontSize: 12)),
                Text(formatNaira(m.minPriceKobo), style: AppText.title.copyWith(fontFamily: AppText.display, fontWeight: FontWeight.w800)),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(m.services.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small.copyWith(color: AppColors.body)),
              ),
              if (!m.withinBudget) const Pill(text: 'Above budget', color: AppColors.alert, background: AppColors.alertSoft),
            ],
          ),
        ],
      ),
    );
  }
}

class MechanicDetailScreen extends StatefulWidget {
  final MechanicSummary mechanic;
  final Place place;
  final int? budgetKobo;
  final String? service;
  const MechanicDetailScreen({super.key, required this.mechanic, required this.place, this.budgetKobo, this.service});
  @override
  State<MechanicDetailScreen> createState() => _MechanicDetailScreenState();
}

class _MechanicDetailScreenState extends State<MechanicDetailScreen> {
  List<Review>? _reviews;

  @override
  void initState() {
    super.initState();
    backend.mechanicReviews(widget.mechanic.id).then((r) {
      if (mounted) setState(() => _reviews = r);
    }).catchError((_) {
      if (mounted) setState(() => _reviews = const []);
    });
  }

  Future<void> _request() async {
    final m = widget.mechanic;
    final result = await showModalBottomSheet<({String service, String note})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RequestSheet(mechanic: m, initialService: widget.service ?? (m.services.isNotEmpty ? m.services.first : 'General repair'), budgetKobo: widget.budgetKobo),
    );
    if (result == null || !mounted) return;
    try {
      final id = await backend.createRequest(
        mechanicId: m.id,
        serviceType: result.service,
        description: result.note,
        place: widget.place,
        budgetKobo: widget.budgetKobo,
      );
      if (!mounted) return;
      final nav = Navigator.of(context);
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(builder: (_) => RequestTrackingScreen(requestId: id)));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mechanic;
    final reviews = _reviews;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        children: [
          Row(children: [
            InitialsAvatar(name: m.businessName, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.businessName, style: AppText.h2),
                const SizedBox(height: 6),
                Text(m.baseAddress, style: AppText.small),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(children: [
              _stat(m.ratingCount == 0 ? 'New' : m.ratingAvg.toStringAsFixed(1), m.ratingCount == 0 ? 'no reviews yet' : '${m.ratingCount} reviews', star: m.ratingCount > 0),
              _divider(),
              _stat('${m.jobsCompleted}', 'jobs done'),
              _divider(),
              _stat('${m.yearsExperience} yrs', 'experience'),
              _divider(),
              _stat(m.distanceKm < 1 ? '${(m.distanceKm * 1000).round()} m' : '${m.distanceKm.toStringAsFixed(1)} km', 'away'),
            ]),
          ),
          if ((m.bio ?? '').isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(m.bio!, style: AppText.body),
          ],
          const SizedBox(height: 20),
          const Text('Services', style: AppText.h3),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in m.services) Pill(text: s, color: AppColors.ink, background: Colors.white, icon: Icons.check_rounded),
          ]),
          const SizedBox(height: 28),
          Row(children: [
            const Expanded(child: Text('Reviews', style: AppText.h3)),
            if (m.ratingCount > 0) Stars(rating: m.ratingAvg, size: 18),
          ]),
          const SizedBox(height: 8),
          if (reviews == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (reviews.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('No reviews yet. Be the first after your job.', style: AppText.body.copyWith(color: AppColors.muted)))
          else
            for (final r in reviews)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(r.reviewer, style: AppText.title.copyWith(fontSize: 15)),
                    const SizedBox(width: 8),
                    Stars(rating: r.rating.toDouble(), size: 14),
                    const Spacer(),
                    Text(timeAgo(r.createdAt), style: AppText.small),
                  ]),
                  if (r.serviceType != null) Text(r.serviceType!, style: AppText.small),
                  if ((r.comment ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text(r.comment!, style: AppText.body)],
                ]),
              ),
        ],
      ),
      bottomSheet: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Starts from', style: AppText.small),
              Text(formatNaira(m.minPriceKobo), style: AppText.h3.copyWith(fontFamily: AppText.display, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.signal, foregroundColor: AppColors.ink),
                onPressed: _request,
                child: const Text('Request this mechanic'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String value, String label, {bool star = false}) => Expanded(
        child: Column(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (star) const Icon(Icons.star_rounded, size: 18, color: AppColors.star),
            Text(value, style: AppText.title.copyWith(fontSize: 17)),
          ]),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: AppText.small.copyWith(fontSize: 12)),
        ]),
      );

  Widget _divider() => Container(width: 1, height: 34, color: AppColors.line);
}

class _RequestSheet extends StatefulWidget {
  final MechanicSummary mechanic;
  final String initialService;
  final int? budgetKobo;
  const _RequestSheet({required this.mechanic, required this.initialService, this.budgetKobo});
  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  late String _service = widget.mechanic.services.contains(widget.initialService) ? widget.initialService : widget.mechanic.services.first;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Request ${widget.mechanic.businessName}', style: AppText.h2),
            const SizedBox(height: 6),
            Text('They have 3 minutes to accept and send you a price. You don\'t pay anything yet.', style: AppText.body.copyWith(color: AppColors.muted)),
            const SizedBox(height: 18),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in widget.mechanic.services) ChoiceChip(label: Text(s), selected: _service == s, onSelected: (_) => setState(() => _service = s)),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What\'s wrong? (optional)',
                hintText: 'e.g. Car won\'t start, clicking sound. Parked by the blue gate.',
                fillColor: AppColors.surface,
              ),
            ),
            if (widget.budgetKobo != null) ...[
              const SizedBox(height: 4),
              Text('Your budget of ${formatNaira(widget.budgetKobo!)} will be shared with the mechanic.', style: AppText.small),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.signal, foregroundColor: AppColors.ink),
              onPressed: () => Navigator.pop(context, (service: _service, note: _note.text.trim())),
              child: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
  }
}
