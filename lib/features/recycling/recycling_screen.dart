import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/app_map.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/place_search.dart';
import '../../data/backend.dart';
import '../../data/models.dart';

IconData recyclingIcon(String type) => switch (type) {
      'lead_acid_battery' => Icons.battery_charging_full_rounded,
      'lithium_battery' => Icons.electric_bolt_rounded,
      'tyres' => Icons.tire_repair_rounded,
      'used_oil' => Icons.oil_barrel_rounded,
      'scrap_metal' => Icons.hardware_rounded,
      'end_of_life_vehicle' => Icons.car_crash_rounded,
      _ => Icons.recycling_rounded,
    };

String fmtQty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(1);

class RecyclingScreen extends StatefulWidget {
  const RecyclingScreen({super.key});
  @override
  State<RecyclingScreen> createState() => _RecyclingScreenState();
}

class _RecyclingScreenState extends State<RecyclingScreen> {
  List<RecyclingRate>? _rates;
  List<RecyclingCentre> _centres = const [];
  List<RecyclingRequest> _mine = const [];
  RecyclingImpact? _impact;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([backend.recyclingRates(), backend.recyclingCentres(), backend.myRecycling(), backend.recyclingImpact()]);
      if (!mounted) return;
      setState(() {
        _rates = r[0] as List<RecyclingRate>;
        _centres = r[1] as List<RecyclingCentre>;
        _mine = r[2] as List<RecyclingRequest>;
        _impact = r[3] as RecyclingImpact;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _new(RecyclingRate rate) async {
    final done = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => NewRecyclingScreen(rates: _rates!, centres: _centres, initial: rate)));
    if (done == true) _load();
  }

  Future<void> _cancel(RecyclingRequest r) async {
    try {
      await backend.cancelRecycling(r.id);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rates = _rates;
    return Scaffold(
      appBar: AppBar(title: const Text('Recycle')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (_error != null && rates == null)
              EmptyState(icon: Icons.cloud_off_rounded, title: 'Couldn\'t load recycling', body: friendlyError(_error!), action: OutlinedButton(onPressed: _load, child: const Text('Try again')))
            else if (rates == null)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else ...[
              _impactCard(),
              const SizedBox(height: 24),
              const Text('What do you want to recycle?', style: AppText.h3),
              const SizedBox(height: 4),
              Text('Indicative prices. The final amount is confirmed at collection and paid into your wallet.', style: AppText.small),
              const SizedBox(height: 12),
              for (final r in rates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    onTap: () => _new(r),
                    child: Row(children: [
                      Container(width: 46, height: 46, decoration: BoxDecoration(color: AppColors.goSoft, borderRadius: BorderRadius.circular(14)), child: Icon(recyclingIcon(r.itemType), color: AppColors.go)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.label, style: AppText.title),
                          if (r.description != null) Text(r.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.small),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(formatNaira(r.rateKobo), style: AppText.title.copyWith(color: AppColors.go)),
                        Text('per ${r.unit == 'unit' ? 'item' : r.unit}', style: AppText.small.copyWith(fontSize: 12)),
                      ]),
                    ]),
                  ),
                ),
              if (_mine.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Your requests', style: AppText.h3),
                const SizedBox(height: 6),
                for (final m in _mine) _RequestRow(r: m, rates: rates, onCancel: () => _cancel(m)),
              ],
              if (_centres.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text('Drop-off centres', style: AppText.h3),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 170,
                    child: AppMap(
                      center: LatLng(_centres.map((c) => c.lat).reduce((a, b) => a + b) / _centres.length, _centres.map((c) => c.lng).reduce((a, b) => a + b) / _centres.length),
                      zoom: 10.6,
                      interactive: false,
                      pins: [for (final c in _centres) MapPin(LatLng(c.lat, c.lng), PinKind.centre)],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                for (final c in _centres)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                    child: Row(children: [
                      const Icon(Icons.recycling_rounded, color: AppColors.go),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.name, style: AppText.title.copyWith(fontSize: 15)),
                          Text([c.address, ?c.hours].join(' · '), style: AppText.small),
                        ]),
                      ),
                    ]),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _impactCard() {
    final i = _impact ?? const RecyclingImpact(co2Kg: 0, paidKobo: 0, items: 0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.go, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your impact', style: TextStyle(color: Color(0xFFCFEBDD), fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtQty(i.co2Kg), style: AppText.money.copyWith(color: Colors.white, fontSize: 40)),
          const SizedBox(width: 8),
          const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('kg CO₂ kept out of the air', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _mini('Earned', formatNaira(i.paidKobo)),
          const SizedBox(width: 10),
          _mini('Requests', '${i.items}'),
        ]),
      ]),
    );
  }

  Widget _mini(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Color(0xFFCFEBDD), fontSize: 12, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

class _RequestRow extends StatelessWidget {
  final RecyclingRequest r;
  final List<RecyclingRate> rates;
  final VoidCallback onCancel;
  const _RequestRow({required this.r, required this.rates, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final rate = rates.where((x) => x.itemType == r.itemType).firstOrNull;
    final (String label, Color fg, Color bg) = switch (r.status) {
      'submitted' => ('Received', AppColors.info, AppColors.infoSoft),
      'scheduled' => ('Scheduled', AppColors.ink, AppColors.signalSoft),
      'collected' => ('Collected', AppColors.go, AppColors.goSoft),
      'paid' => ('Paid', AppColors.go, AppColors.goSoft),
      _ => ('Cancelled', AppColors.muted, AppColors.surface),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(children: [
        Icon(recyclingIcon(r.itemType), color: AppColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${fmtQty(r.quantity)} ${rate?.unit == 'unit' ? '×' : rate?.unit ?? ''} ${rate?.label ?? r.itemType}', style: AppText.body.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
            Text(
              [
                r.method == 'pickup' ? 'Pickup' : 'Drop-off at ${r.centreName ?? 'centre'}',
                if (r.preferredDate != null) formatDate(r.preferredDate!),
                '≈ ${formatNaira(r.estimatedValueKobo)}',
              ].join(' · '),
              style: AppText.small,
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Pill(text: label, color: fg, background: bg),
          if (r.status == 'submitted' || r.status == 'scheduled')
            GestureDetector(onTap: onCancel, child: const Padding(padding: EdgeInsets.only(top: 6), child: Text('Cancel', style: TextStyle(color: AppColors.alert, fontWeight: FontWeight.w600, fontSize: 13)))),
        ]),
      ]),
    );
  }
}

class NewRecyclingScreen extends StatefulWidget {
  final List<RecyclingRate> rates;
  final List<RecyclingCentre> centres;
  final RecyclingRate initial;
  const NewRecyclingScreen({super.key, required this.rates, required this.centres, required this.initial});
  @override
  State<NewRecyclingScreen> createState() => _NewRecyclingScreenState();
}

class _NewRecyclingScreenState extends State<NewRecyclingScreen> {
  late RecyclingRate _rate = widget.initial;
  double _qty = 1;
  String _condition = 'Not working';
  String _method = 'pickup';
  Place? _pickup;
  RecyclingCentre? _centre;
  DateTime? _date;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  double get _step => _rate.unit == 'unit' ? 1 : (_rate.unit == 'kg' ? 5 : 1);

  List<RecyclingCentre> get _eligibleCentres => widget.centres.where((c) => c.accepts.isEmpty || c.accepts.contains(_rate.itemType)).toList();

  Future<void> _submit() async {
    if (_method == 'pickup' && _pickup == null) throw const AppException('Add the pickup address.');
    if (_method == 'dropoff' && _centre == null) throw const AppException('Choose a drop-off centre.');
    await backend.submitRecycling(
      itemType: _rate.itemType,
      quantity: _qty,
      condition: _condition,
      notes: _notes.text.trim(),
      method: _method,
      centreId: _centre?.id,
      pickup: _pickup,
      preferredDate: _date,
    );
    if (!mounted) return;
    showSnack(context, _method == 'pickup' ? 'Pickup requested. We\'ll confirm a time.' : 'Drop-off booked. Show this request at the centre.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final value = (_rate.rateKobo * _qty).round();
    final co2 = _rate.co2Kg * _qty;
    final hazardous = _rate.itemType == 'lithium_battery' || _rate.itemType == 'lead_acid_battery' || _rate.itemType == 'used_oil';
    return Scaffold(
      appBar: AppBar(title: const Text('Recycle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
        children: [
          DropdownButtonFormField<RecyclingRate>(
            initialValue: _rate,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Item'),
            items: [for (final r in widget.rates) DropdownMenuItem(value: r, child: Text(r.label))],
            onChanged: (r) => setState(() {
              _rate = r!;
              _qty = r.unit == 'kg' ? 10 : 1;
              if (_centre != null && !_eligibleCentres.contains(_centre)) _centre = null;
            }),
          ),
          const SizedBox(height: 20),
          Text('How many ${_rate.unitLabel}?', style: AppText.title),
          const SizedBox(height: 8),
          Row(children: [
            IconButton.outlined(onPressed: _qty <= _step ? null : () => setState(() => _qty = (_qty - _step).clamp(_step, 10000)), icon: const Icon(Icons.remove_rounded)),
            Expanded(child: Text('${fmtQty(_qty)} ${_rate.unitFor(_qty)}', textAlign: TextAlign.center, style: AppText.h2)),
            IconButton.outlined(onPressed: () => setState(() => _qty += _step), icon: const Icon(Icons.add_rounded)),
          ]),
          if (_rate.unit != 'unit') Center(child: Text('Your best guess is fine. We weigh it at collection.', style: AppText.small)),
          const SizedBox(height: 20),
          const Text('Condition', style: AppText.title),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in const ['Not working', 'Damaged or leaking', 'Still works'])
              ChoiceChip(label: Text(c), selected: _condition == c, onSelected: (_) => setState(() => _condition = c)),
          ]),
          if (hazardous && _condition == 'Damaged or leaking')
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.alertSoft, borderRadius: BorderRadius.circular(12)),
              child: Text('Don\'t touch or move a leaking battery or oil yourself. Keep it outside, away from children and fire. Our team will handle it.',
                  style: AppText.small.copyWith(color: AppColors.alert, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pickup', label: Text('We pick it up'), icon: Icon(Icons.local_shipping_outlined)),
              ButtonSegment(value: 'dropoff', label: Text('I\'ll drop it off'), icon: Icon(Icons.storefront_outlined)),
            ],
            selected: {_method},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _method = s.first),
            style: SegmentedButton.styleFrom(selectedBackgroundColor: AppColors.ink, selectedForegroundColor: Colors.white, backgroundColor: Colors.white, side: const BorderSide(color: AppColors.line)),
          ),
          const SizedBox(height: 12),
          if (_method == 'pickup')
            Panel(
              onTap: () async {
                final p = await pickPlace(context, title: 'Pickup address');
                if (p != null) setState(() => _pickup = p);
              },
              child: Row(children: [
                const Icon(Icons.place_rounded),
                const SizedBox(width: 12),
                Expanded(child: Text(_pickup?.address ?? 'Add pickup address', style: AppText.title.copyWith(color: _pickup == null ? AppColors.info : AppColors.ink))),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ]),
            )
          else if (_eligibleCentres.isEmpty)
            Text('No centre accepts this item yet. Choose pickup instead.', style: AppText.body.copyWith(color: AppColors.alert))
          else
            RadioGroup<RecyclingCentre>(
              groupValue: _centre,
              onChanged: (v) => setState(() => _centre = v),
              child: Column(children: [
                for (final c in _eligibleCentres)
                  RadioListTile<RecyclingCentre>(
                    value: c,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.go,
                    title: Text(c.name, style: AppText.title.copyWith(fontSize: 15)),
                    subtitle: Text([c.address, ?c.hours].join(' · ')),
                  ),
              ]),
            ),
          const SizedBox(height: 12),
          Panel(
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), initialDate: _date ?? now.add(const Duration(days: 1)));
              if (d != null) setState(() => _date = d);
            },
            child: Row(children: [
              const Icon(Icons.event_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text(_date == null ? 'Preferred date (optional)' : formatDate(_date!), style: AppText.title.copyWith(color: _date == null ? AppColors.info : AppColors.ink))),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLines: 2, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Notes for the collector (optional)')),
        ],
      ),
      bottomSheet: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Estimated payment', style: AppText.small)),
              Text(formatNaira(value), style: AppText.h3.copyWith(color: AppColors.go, fontFamily: AppText.display, fontWeight: FontWeight.w800)),
            ]),
            Row(children: [
              Expanded(child: Text('CO₂ kept out of the air', style: AppText.small)),
              Text('≈ ${fmtQty(co2)} kg', style: AppText.small.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            BusyButton(label: _method == 'pickup' ? 'Request pickup' : 'Book drop-off', background: AppColors.go, onPressed: _submit),
          ]),
        ),
      ),
    );
  }
}
