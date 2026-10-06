import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../env.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Full-screen address search. Pops with the chosen [Place].
Future<Place?> pickPlace(BuildContext context, {String title = 'Where are you?', String hint = 'Street, area or landmark', Place? near}) {
  return Navigator.of(context).push<Place>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PlaceSearchPage(title: title, hint: hint, near: near),
  ));
}

class _PlaceSearchPage extends StatefulWidget {
  final String title;
  final String hint;
  final Place? near;
  const _PlaceSearchPage({required this.title, required this.hint, this.near});

  @override
  State<_PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<_PlaceSearchPage> {
  final _ctrl = TextEditingController();
  final _session = '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';
  Timer? _debounce;
  List<PlaceSuggestion> _results = const [];
  bool _loading = false;
  bool _locating = false;
  String? _error;
  int _query = 0;

  @override
  void initState() {
    super.initState();
    if (backend.isDemo) _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(v));
  }

  Future<void> _search(String v) async {
    final q = ++_query;
    if (v.trim().length < 2 && !backend.isDemo) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await backend.placeAutocomplete(v, lat: widget.near?.lat, lng: widget.near?.lng, country: Env.defaultCountry, session: _session);
      if (!mounted || q != _query) return;
      setState(() {
        _results = r;
        _error = null;
      });
    } catch (e) {
      if (!mounted || q != _query) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && q == _query) setState(() => _loading = false);
    }
  }

  Future<void> _choose(PlaceSuggestion s) async {
    setState(() => _loading = true);
    try {
      final p = await backend.placeDetails(s, session: _session);
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _useMyLocation() async {
    if (backend.isDemo) {
      Navigator.pop(context, const Place(address: 'Sabo, Yaba, Lagos (current location)', title: 'Current location', lat: 6.5071, lng: 3.3794));
      return;
    }
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw const AppException('Turn on location (GPS) and try again.');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw const AppException('Allow location access to use where you are now.');
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      if (!mounted) return;
      final label = 'Current location (${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})';
      Navigator.pop(context, Place(address: label, title: 'Current location', lat: pos.latitude, lng: pos.longitude));
    } catch (e) {
      if (mounted) showError(context, e is TimeoutException ? const AppException('Couldn\'t get a GPS fix. Type your address instead.') : e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(widget.title),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: widget.hint,
                fillColor: AppColors.surface,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
              ),
            ),
          ),
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.infoSoft, borderRadius: BorderRadius.circular(12)),
              child: _locating
                  ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info))
                  : const Icon(Icons.my_location_rounded, color: AppColors.info),
            ),
            title: const Text('Use my current location', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Best when you\'re with the car'),
            onTap: _locating ? null : _useMyLocation,
          ),
          const Divider(indent: 16, endIndent: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: AppColors.alert)),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, _) => const Divider(indent: 72),
              itemBuilder: (_, i) {
                final s = _results[i];
                return ListTile(
                  leading: const SizedBox(width: 40, child: Icon(Icons.place_outlined, color: AppColors.muted)),
                  title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: s.subtitle.isEmpty ? null : Text(s.subtitle),
                  onTap: () => _choose(s),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
