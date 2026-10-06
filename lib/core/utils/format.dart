import 'dart:math' as math;

import 'package:intl/intl.dart';

final _naira = NumberFormat.currency(locale: 'en', symbol: '₦', decimalDigits: 0);
final _nairaKobo = NumberFormat.currency(locale: 'en', symbol: '₦', decimalDigits: 2);

/// ₦18,000 (kobo shown only when there is some).
String formatNaira(int kobo) => kobo % 100 == 0 ? _naira.format(kobo / 100) : _nairaKobo.format(kobo / 100);

/// "₦18k" for compact chips.
String formatNairaShort(int kobo) {
  final n = kobo / 100;
  if (n >= 1000000) return '₦${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}m';
  if (n >= 1000) return '₦${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
  return '₦${n.toStringAsFixed(0)}';
}

/// Parses "18,000" or "18000.50" (naira) into kobo.
int? parseNairaToKobo(String text) {
  final clean = text.replaceAll(RegExp(r'[^0-9.]'), '');
  if (clean.isEmpty) return null;
  final v = double.tryParse(clean);
  if (v == null) return null;
  return (v * 100).round();
}

/// "8 min", "1 h 5 min", "Less than a minute".
String formatEta(int? seconds) {
  if (seconds == null) return '—';
  final mins = (seconds / 60).round();
  if (mins < 1) return 'Less than a minute';
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String formatDistance(num? meters) {
  if (meters == null) return '';
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String formatKm(double km) => km < 1 ? '${(km * 1000).round()} m away' : '${km.toStringAsFixed(1)} km away';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat('d MMM yyyy').format(t);
}

String formatDate(DateTime t) => DateFormat('EEE d MMM').format(t);
String formatDateTime(DateTime t) => DateFormat('d MMM, h:mm a').format(t);

/// Straight-line distance in km.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Rough city-traffic estimate when the live routing service isn't reachable.
int roughEtaSeconds(double km) => math.max(60, (km * 1.35 / 22 * 3600).round());
