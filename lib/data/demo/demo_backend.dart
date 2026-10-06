import 'dart:async';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/utils/format.dart';
import '../backend.dart';
import '../models.dart';

/// Sample data and a simulated other side, so the whole app can be tried
/// without a server: requests get accepted, the mechanic drives to you,
/// escrow holds and releases money, and AutoLearn answers common questions.
class DemoBackend implements AppBackend {
  DemoBackend() {
    _seed();
  }

  @override
  bool get isDemo => true;

  final _rand = math.Random(7);
  final _userCtrl = StreamController<String?>.broadcast();
  String? _uid;
  Profile? _profile;
  WorkshopProfile? _workshop;

  final _mechanics = <MechanicSummary>[];
  final _reviews = <String, List<Review>>{};
  final _requests = <String, ServiceRequest>{};
  final _requestCtrls = <String, StreamController<ServiceRequest?>>{};
  final _locCtrls = <String, StreamController<MechanicPoint?>>{};
  final _locs = <String, MechanicPoint>{};
  final _routes = <String, List<LatLng>>{};
  final _jobsCtrl = StreamController<List<ServiceRequest>>.broadcast();
  final _reviewed = <String>{};
  final _timers = <Timer>[];

  int _available = 2500000;
  final _txns = <WalletTxn>[];
  PayoutAccount? _payout;
  final _recycling = <RecyclingRequest>[];
  final _learn = <LearnMessage>[];
  int _seq = 0;

  String _id() => 'demo-${++_seq}-${_rand.nextInt(1 << 20)}';
  Future<void> _wait([int ms = 450]) => Future.delayed(Duration(milliseconds: ms));

  void _later(int ms, void Function() f) => _timers.add(Timer(Duration(milliseconds: ms), f));

  // ---- Seed -------------------------------------------------------------------
  void _seed() {
    final data = [
      ('Tunde Auto Works', 'Engines, electrics and batteries. Mobile service across Yaba and Surulere.', ['General repair', 'Engine repair', 'Battery & electrics', 'Diagnostics'], 1500000, 'Herbert Macaulay Way, Yaba', 6.5098, 3.3781, 11, 4.8, 126, 412),
      ('Mama Nkechi Vulcanizer', 'Tyre repair, wheel balancing and puncture fixes, day and night.', ['Tyres & vulcanising'], 300000, 'Ojuelegba Road, Surulere', 6.5033, 3.3640, 18, 4.6, 88, 960),
      ('Sule Brakes & Suspension', 'Brake pads, discs and shocks for Japanese and Korean cars.', ['Brakes', 'General repair'], 1200000, 'Ikorodu Road, Fadeyi', 6.5297, 3.3727, 9, 4.4, 41, 205),
      ('Coolbreeze AC Clinic', 'Car AC regas, compressors and radiators.', ['AC & cooling', 'Diagnostics'], 2000000, 'Adeniran Ogunsanya St, Surulere', 6.4930, 3.3555, 7, 4.9, 64, 230),
      ('Rapid Rescue Towing', '24/7 towing and roadside recovery anywhere in Lagos.', ['Towing'], 3500000, 'Ikorodu Road, Maryland', 6.5710, 3.3667, 6, 4.3, 37, 310),
      ('Kemi Diagnostics Lab', 'OBD scans, check-engine lights and hybrid systems.', ['Diagnostics', 'Battery & electrics', 'Engine repair'], 2500000, 'Allen Avenue, Ikeja', 6.6014, 3.3519, 8, 4.7, 52, 180),
      ('Lekki Lube & Service', 'Oil changes and routine servicing while you wait.', ['Oil change', 'General repair'], 900000, 'Admiralty Way, Lekki Phase 1', 6.4474, 3.4727, 5, 4.2, 29, 150),
      ('Emeka Engines', 'Engine overhauls, timing belts and gearbox work.', ['Engine repair', 'General repair'], 4000000, 'Ogunlana Drive, Surulere', 6.4885, 3.3488, 15, 4.5, 73, 290),
    ];
    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final id = 'mech-$i';
      _mechanics.add(MechanicSummary(
        id: id,
        businessName: d.$1,
        bio: d.$2,
        services: d.$3,
        minPriceKobo: d.$4,
        baseAddress: d.$5,
        lat: d.$6,
        lng: d.$7,
        yearsExperience: d.$8,
        ratingAvg: d.$9,
        ratingCount: d.$10,
        jobsCompleted: d.$11,
        distanceKm: 0,
        withinBudget: true,
      ));
      _reviews[id] = _sampleReviews(i, d.$3.first);
    }
    final now = DateTime.now();
    _txns.addAll([
      WalletTxn(id: _id(), kind: 'topup', amountKobo: 2000000, description: 'Wallet top-up (Paystack)', createdAt: now.subtract(const Duration(days: 3))),
      WalletTxn(id: _id(), kind: 'recycling_payout', amountKobo: 700000, description: 'Recycling payment', createdAt: now.subtract(const Duration(days: 9))),
      WalletTxn(id: _id(), kind: 'escrow_release', amountKobo: -200000, description: 'Paid: Tyres & vulcanising', createdAt: now.subtract(const Duration(days: 12))),
    ]);
    _recycling.add(RecyclingRequest(
      id: _id(),
      itemType: 'lead_acid_battery',
      quantity: 2,
      method: 'pickup',
      pickupAddress: 'Sabo, Yaba, Lagos',
      preferredDate: now.subtract(const Duration(days: 10)),
      estimatedValueKobo: 700000,
      estimatedCo2Kg: 18,
      status: 'paid',
      createdAt: now.subtract(const Duration(days: 11)),
    ));
  }

  List<Review> _sampleReviews(int seed, String service) {
    const texts = [
      ('Chiamaka', 5, 'Came within 20 minutes and fixed it on the spot. Fair price.'),
      ('Ibrahim', 4, 'Good work. Explained what was wrong before touching anything.'),
      ('Folake', 5, 'Very honest. Told me I didn\'t need a new part.'),
      ('Kunle', 4, 'A bit late because of traffic but did a clean job.'),
      ('Ngozi', 5, 'Saved me on Third Mainland Bridge. Thank you!'),
      ('Musa', 3, 'Job was fine, communication could be better.'),
    ];
    final out = <Review>[];
    for (var k = 0; k < 4; k++) {
      final t = texts[(seed + k) % texts.length];
      out.add(Review(id: _id(), rating: t.$2, comment: t.$3, reviewer: t.$1, serviceType: service, createdAt: DateTime.now().subtract(Duration(days: 2 + k * 6 + seed))));
    }
    return out;
  }

  static const _places = [
    ('Herbert Macaulay Way', 'Yaba, Lagos', 6.5146, 3.3760),
    ('University of Lagos', 'Akoka, Yaba, Lagos', 6.5158, 3.3897),
    ('Ojuelegba Bus Stop', 'Surulere, Lagos', 6.5059, 3.3633),
    ('National Stadium', 'Surulere, Lagos', 6.4968, 3.3637),
    ('Allen Avenue', 'Ikeja, Lagos', 6.6014, 3.3519),
    ('Ikeja City Mall', 'Alausa, Ikeja, Lagos', 6.6142, 3.3576),
    ('Third Mainland Bridge', 'Lagos', 6.4990, 3.4010),
    ('Admiralty Way', 'Lekki Phase 1, Lagos', 6.4474, 3.4727),
    ('Adeola Odeku Street', 'Victoria Island, Lagos', 6.4310, 3.4220),
    ('Awolowo Road', 'Ikoyi, Lagos', 6.4467, 3.4310),
    ('Gbagada Expressway', 'Gbagada, Lagos', 6.5537, 3.3880),
    ('Sabo Market', 'Yaba, Lagos', 6.5071, 3.3794),
  ];

  // ---- Auth ---------------------------------------------------------------------
  @override
  String? get currentUserId => _uid;
  @override
  String? get currentEmail => _uid == null ? null : 'demo@autowave.app';
  @override
  Stream<String?> get userChanges => _userCtrl.stream;

  void _signIn(String? name) {
    _uid = 'demo-user';
    _profile = Profile(id: _uid!, fullName: name, email: currentEmail, countryCode: 'NG');
    _userCtrl.add(_uid);
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _wait();
    _signIn('Ada Okafor');
  }

  @override
  Future<bool> signUpWithEmail({required String fullName, required String email, required String password}) async {
    await _wait();
    _signIn(fullName);
    return false;
  }

  @override
  Future<void> resetPassword(String email) => _wait();
  @override
  Future<void> sendPhoneCode(String phoneE164) => _wait(700);

  @override
  Future<void> verifyPhoneCode(String phoneE164, String code) async {
    await _wait();
    if (code.trim().length != 6) throw const AppException('Enter the 6-digit code. In demo mode any 6 digits work.');
    _signIn(null);
    _profile = Profile(id: _uid!, phone: phoneE164, countryCode: 'NG');
  }

  @override
  Future<void> signInWithGoogle() async {
    await _wait();
    _signIn('Ada Okafor');
  }

  @override
  Future<void> signOut() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _uid = null;
    _profile = null;
    _workshop = null;
    _userCtrl.add(null);
  }

  // ---- Profile ------------------------------------------------------------------
  @override
  Future<Profile?> myProfile() async => _profile;

  @override
  Future<void> setRole(UserRole role, {String? fullName, String? phone, String? countryCode}) async {
    await _wait();
    final p = _profile!;
    _profile = Profile(
      id: p.id,
      role: role,
      fullName: (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : (p.fullName ?? (role == UserRole.driver ? 'Ada Okafor' : 'Tunde Bakare')),
      phone: (phone?.isNotEmpty ?? false) ? phone : p.phone,
      countryCode: countryCode ?? p.countryCode,
      email: p.email,
    );
    if (role == UserRole.mechanic) {
      _available = 0;
      _txns.clear();
    }
  }

  @override
  Future<void> updateProfile({required String fullName, required String phone, required String countryCode}) async {
    await _wait();
    final p = _profile!;
    _profile = Profile(id: p.id, role: p.role, fullName: fullName, phone: phone, countryCode: countryCode, email: p.email);
  }

  // ---- Places -------------------------------------------------------------------
  @override
  Future<List<PlaceSuggestion>> placeAutocomplete(String input, {double? lat, double? lng, String? country, String? session}) async {
    await _wait(150);
    final q = input.toLowerCase().trim();
    return _places
        .where((p) => q.isEmpty || '${p.$1} ${p.$2}'.toLowerCase().contains(q) || q.split(' ').any((w) => w.length > 2 && '${p.$1} ${p.$2}'.toLowerCase().contains(w)))
        .take(6)
        .map((p) => PlaceSuggestion(placeId: p.$1, title: p.$1, subtitle: p.$2))
        .toList();
  }

  @override
  Future<Place> placeDetails(PlaceSuggestion s, {String? session}) async {
    final p = _places.firstWhere((p) => p.$1 == s.placeId, orElse: () => _places.first);
    return Place(address: '${p.$1}, ${p.$2}', title: p.$1, lat: p.$3, lng: p.$4);
  }

  // ---- Driver -------------------------------------------------------------------
  @override
  Future<List<MechanicSummary>> searchMechanics({required double lat, required double lng, int? budgetKobo, String? service, double radiusKm = 25}) async {
    await _wait(700);
    final out = <MechanicSummary>[];
    for (final m in _mechanics) {
      final km = haversineKm(lat, lng, m.lat, m.lng);
      if (km > radiusKm) continue;
      if (service != null && service.isNotEmpty && !m.services.contains(service)) continue;
      out.add(MechanicSummary(
        id: m.id,
        businessName: m.businessName,
        bio: m.bio,
        services: m.services,
        minPriceKobo: m.minPriceKobo,
        baseAddress: m.baseAddress,
        lat: m.lat,
        lng: m.lng,
        yearsExperience: m.yearsExperience,
        ratingAvg: m.ratingAvg,
        ratingCount: m.ratingCount,
        jobsCompleted: m.jobsCompleted,
        distanceKm: km,
        withinBudget: budgetKobo == null || m.minPriceKobo <= budgetKobo,
      ));
    }
    out.sort((a, b) {
      if (a.withinBudget != b.withinBudget) return a.withinBudget ? -1 : 1;
      return a.distanceKm.compareTo(b.distanceKm);
    });
    return out;
  }

  @override
  Future<List<Review>> mechanicReviews(String mechanicId) async {
    await _wait(300);
    return _reviews[mechanicId] ?? const [];
  }

  StreamController<ServiceRequest?> _ctrl(String id) => _requestCtrls.putIfAbsent(id, () => StreamController<ServiceRequest?>.broadcast());

  void _put(ServiceRequest r) {
    _requests[r.id] = r;
    _ctrl(r.id).add(r);
    if (_profile?.role == UserRole.mechanic) _emitJobs();
  }

  void _emitJobs() {
    final list = _requests.values.where((r) => r.mechanicId == _uid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _jobsCtrl.add(list);
  }

  @override
  Future<String> createRequest({required String mechanicId, required String serviceType, String? description, required Place place, int? budgetKobo}) async {
    await _wait();
    if (_requests.values.any((r) => r.customerId == _uid && r.isActive)) {
      throw const AppException('You already have a request in progress');
    }
    final m = _mechanics.firstWhere((x) => x.id == mechanicId);
    final id = _id();
    _put(ServiceRequest(
      id: id,
      customerId: _uid!,
      mechanicId: mechanicId,
      serviceType: serviceType,
      description: description,
      pickupAddress: place.address,
      pickupLat: place.lat,
      pickupLng: place.lng,
      budgetKobo: budgetKobo,
      status: RequestStatus.requested,
      paymentStatus: PaymentStatus.unpaid,
      respondBy: DateTime.now().add(const Duration(minutes: 3)),
      createdAt: DateTime.now(),
    ));
    // The simulated mechanic accepts after a few seconds.
    _later(4500, () {
      final r = _requests[id];
      if (r == null || r.status != RequestStatus.requested) return;
      final quote = math.max(m.minPriceKobo, budgetKobo ?? m.minPriceKobo);
      final km = haversineKm(m.lat, m.lng, place.lat, place.lng);
      _put(r.copyWith(status: RequestStatus.accepted, quotedPriceKobo: quote, etaSeconds: roughEtaSeconds(km), distanceMeters: (km * 1350).round()));
      _locs[mechanicId] = MechanicPoint(lat: m.lat, lng: m.lng, updatedAt: DateTime.now());
      _locCtrls[mechanicId]?.add(_locs[mechanicId]);
      _later(5000, () => _driveTo(id, LatLng(m.lat, m.lng)));
    });
    return id;
  }

  /// Moves the simulated mechanic toward the driver along a slightly bent path.
  void _driveTo(String requestId, LatLng from) {
    final r = _requests[requestId];
    if (r == null || r.status != RequestStatus.accepted) return;
    final to = r.pickup;
    final mid = LatLng((from.latitude + to.latitude) / 2 + 0.004, (from.longitude + to.longitude) / 2 - 0.004);
    final path = <LatLng>[];
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      // quadratic Bézier through the bend
      final lat = (1 - t) * (1 - t) * from.latitude + 2 * (1 - t) * t * mid.latitude + t * t * to.latitude;
      final lng = (1 - t) * (1 - t) * from.longitude + 2 * (1 - t) * t * mid.longitude + t * t * to.longitude;
      path.add(LatLng(lat, lng));
    }
    _routes[requestId] = path;
    _put(r.copyWith(status: RequestStatus.enRoute));
    var i = 0;
    late Timer t;
    t = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      final cur = _requests[requestId];
      if (cur == null || cur.status != RequestStatus.enRoute) {
        t.cancel();
        return;
      }
      i++;
      final p = path[math.min(i, steps)];
      _locs[cur.mechanicId] = MechanicPoint(lat: p.latitude, lng: p.longitude, updatedAt: DateTime.now());
      _locCtrls[cur.mechanicId]?.add(_locs[cur.mechanicId]);
      final remainingKm = haversineKm(p.latitude, p.longitude, to.latitude, to.longitude);
      if (i >= steps) {
        t.cancel();
        _put(cur.copyWith(status: RequestStatus.arrived, clearEta: true));
        _maybeStartWork(requestId);
      } else {
        _put(cur.copyWith(etaSeconds: math.max(60, roughEtaSeconds(remainingKm)), distanceMeters: (remainingKm * 1350).round()));
      }
    });
    _timers.add(t);
  }

  void _maybeStartWork(String id) {
    final r = _requests[id];
    if (r == null || r.status != RequestStatus.arrived || r.paymentStatus != PaymentStatus.held) return;
    _later(4000, () {
      final a = _requests[id];
      if (a == null || a.status != RequestStatus.arrived) return;
      _put(a.copyWith(status: RequestStatus.inProgress));
      _later(7000, () {
        final b = _requests[id];
        if (b == null || b.status != RequestStatus.inProgress) return;
        _put(b.copyWith(status: RequestStatus.completed, completedAt: DateTime.now()));
      });
    });
  }

  @override
  Stream<ServiceRequest?> watchRequest(String requestId) async* {
    yield _requests[requestId];
    yield* _ctrl(requestId).stream;
  }

  @override
  Future<ServiceRequest?> activeRequest() async {
    final mine = _requests.values.where((r) => r.customerId == _uid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final r in mine) {
      if (r.isActive) return r;
      if (r.status == RequestStatus.completed && r.paymentStatus == PaymentStatus.held) return r;
    }
    return null;
  }

  @override
  Future<List<ServiceRequest>> myJobs({int limit = 30}) async =>
      (_requests.values.where((r) => r.customerId == _uid || r.mechanicId == _uid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<void> cancelRequest(String requestId, {String? reason}) async {
    await _wait();
    final r = _requests[requestId]!;
    if (!{RequestStatus.requested, RequestStatus.accepted, RequestStatus.enRoute, RequestStatus.arrived}.contains(r.status)) {
      throw const AppException('This job can\'t be cancelled now');
    }
    var pay = r.paymentStatus;
    if (pay == PaymentStatus.held) {
      final payerIsMe = r.customerId == _uid;
      if (payerIsMe) {
        _available += r.quotedPriceKobo!;
        _txn('escrow_refund', r.quotedPriceKobo!, 'Refund: job cancelled');
      }
      pay = PaymentStatus.refunded;
    }
    _put(r.copyWith(status: RequestStatus.cancelled, paymentStatus: pay, clearEta: true, cancelReason: reason));
  }

  @override
  Future<void> expireStale() async {
    for (final r in _requests.values.toList()) {
      if (r.status == RequestStatus.requested && r.respondBy.isBefore(DateTime.now())) _put(r.copyWith(status: RequestStatus.expired));
    }
  }

  @override
  Future<Counterpart> counterpart(String requestId) async {
    final r = _requests[requestId];
    if (r == null) return const Counterpart(name: 'Your mechanic');
    if (r.mechanicId == _uid) return const Counterpart(name: 'Chiamaka Eze', phone: '+234 803 555 0142');
    final m = _mechanics.firstWhere((x) => x.id == r.mechanicId, orElse: () => _mechanics.first);
    final shared = r.status != RequestStatus.requested;
    return Counterpart(name: m.businessName, phone: shared ? '+234 802 555 0187' : null);
  }

  @override
  Stream<MechanicPoint?> watchMechanicLocation(String mechanicId) async* {
    final c = _locCtrls.putIfAbsent(mechanicId, () => StreamController<MechanicPoint?>.broadcast());
    if (_locs[mechanicId] != null) yield _locs[mechanicId];
    yield* c.stream;
  }

  @override
  Future<EtaResult> fetchEta(String requestId, {bool includeRoute = false}) async {
    final r = _requests[requestId];
    if (r == null) return const EtaResult();
    final m = _locs[r.mechanicId];
    List<LatLng>? route;
    if (includeRoute && _routes[requestId] != null && m != null) {
      final path = _routes[requestId]!;
      // remaining part of the path
      var nearest = 0;
      var best = double.infinity;
      for (var i = 0; i < path.length; i++) {
        final d = haversineKm(m.lat, m.lng, path[i].latitude, path[i].longitude);
        if (d < best) {
          best = d;
          nearest = i;
        }
      }
      route = path.sublist(nearest);
    }
    return EtaResult(seconds: r.etaSeconds, meters: r.distanceMeters, route: route, mechanic: m);
  }

  @override
  Future<bool> hasReviewed(String requestId) async => _reviewed.contains(requestId);

  @override
  Future<void> submitReview({required String requestId, required String mechanicId, required int rating, String? comment}) async {
    await _wait();
    _reviewed.add(requestId);
    _reviews[mechanicId]?.insert(0, Review(id: _id(), rating: rating, comment: comment, createdAt: DateTime.now(), reviewer: _profile?.firstName ?? 'You', serviceType: _requests[requestId]?.serviceType));
  }

  // ---- Mechanic -----------------------------------------------------------------
  @override
  Future<WorkshopProfile?> myWorkshop() async => _workshop;

  @override
  Future<void> saveWorkshop(WorkshopProfile w) async {
    await _wait();
    final old = _workshop;
    _workshop = WorkshopProfile(
      businessName: w.businessName,
      bio: w.bio,
      services: w.services,
      minPriceKobo: w.minPriceKobo,
      baseAddress: w.baseAddress,
      baseLat: w.baseLat,
      baseLng: w.baseLng,
      serviceRadiusKm: w.serviceRadiusKm,
      yearsExperience: w.yearsExperience,
      isOnline: old?.isOnline ?? true,
      ratingAvg: old?.ratingAvg ?? 4.7,
      ratingCount: old?.ratingCount ?? 58,
      jobsCompleted: old?.jobsCompleted ?? 214,
    );
  }

  @override
  Future<void> setOnline(bool online) async {
    _workshop = _workshop?.copyWith(isOnline: online);
    if (online) _scheduleIncoming(2500);
  }

  bool _incomingScheduled = false;

  void _scheduleIncoming(int ms) {
    if (_incomingScheduled) return;
    _incomingScheduled = true;
    _later(ms, () {
      _incomingScheduled = false;
      if (_uid == null || _profile?.role != UserRole.mechanic || !(_workshop?.isOnline ?? false)) return;
      if (_requests.values.any((r) => r.mechanicId == _uid && r.isActive)) return;
      final w = _workshop!;
      final jobs = [
        ('Battery & electrics', 'Car won\'t start after the rain. Lights are dim.', 'Sabo Market, Yaba, Lagos', 6.5071, 3.3794, 2000000),
        ('Brakes', 'Squeaking when I brake, getting worse.', 'University of Lagos, Akoka, Yaba', 6.5158, 3.3897, 1500000),
        ('Tyres & vulcanising', 'Flat tyre on the expressway.', 'Ojuelegba Bus Stop, Surulere', 6.5059, 3.3633, 500000),
      ];
      final j = jobs[_seq % jobs.length];
      final id = _id();
      _put(ServiceRequest(
        id: id,
        customerId: 'demo-driver',
        mechanicId: _uid!,
        serviceType: j.$1,
        description: j.$2,
        pickupAddress: j.$3,
        pickupLat: j.$4,
        pickupLng: j.$5,
        budgetKobo: math.max(j.$6, w.minPriceKobo),
        status: RequestStatus.requested,
        paymentStatus: PaymentStatus.unpaid,
        respondBy: DateTime.now().add(const Duration(minutes: 3)),
        createdAt: DateTime.now(),
      ));
    });
  }

  @override
  Stream<List<ServiceRequest>> watchMechanicJobs() async* {
    final list = _requests.values.where((r) => r.mechanicId == _uid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    yield list;
    if (_workshop?.isOnline ?? false) _scheduleIncoming(3000);
    yield* _jobsCtrl.stream;
  }

  @override
  Future<void> respondToRequest(String requestId, {required bool accept, int? quoteKobo, int? etaMinutes}) async {
    await _wait();
    final r = _requests[requestId]!;
    if (!accept) {
      _put(r.copyWith(status: RequestStatus.rejected));
      _scheduleIncoming(8000);
      return;
    }
    if ((quoteKobo ?? 0) <= 0) throw const AppException('Enter your price for this job');
    _put(r.copyWith(status: RequestStatus.accepted, quotedPriceKobo: quoteKobo, etaSeconds: (etaMinutes ?? 10) * 60));
    // The simulated driver pays into escrow.
    _later(3500, () {
      final a = _requests[requestId];
      if (a == null || a.paymentStatus != PaymentStatus.unpaid || a.status == RequestStatus.cancelled) return;
      _put(a.copyWith(paymentStatus: PaymentStatus.held));
    });
  }

  @override
  Future<void> updateJobStatus(String requestId, RequestStatus status) async {
    await _wait(300);
    final r = _requests[requestId]!;
    if (status == RequestStatus.inProgress && r.paymentStatus != PaymentStatus.held) {
      throw const AppException('Wait for the driver to pay into escrow before starting work');
    }
    _put(r.copyWith(
      status: status,
      clearEta: status != RequestStatus.enRoute,
      completedAt: status == RequestStatus.completed ? DateTime.now() : null,
    ));
    if (status == RequestStatus.completed) {
      // The simulated driver confirms and releases the payment.
      _later(4000, () {
        final c = _requests[requestId];
        if (c == null || c.paymentStatus != PaymentStatus.held) return;
        _available += c.quotedPriceKobo!;
        _txn('escrow_release', c.quotedPriceKobo!, 'Payment for ${c.serviceType}');
        _put(c.copyWith(paymentStatus: PaymentStatus.released));
        _scheduleIncoming(9000);
      });
    }
  }

  @override
  Future<void> publishLocation(double lat, double lng, double? heading) async {}

  // ---- Wallet -------------------------------------------------------------------
  void _txn(String kind, int amount, String desc) =>
      _txns.insert(0, WalletTxn(id: _id(), kind: kind, amountKobo: amount, description: desc, createdAt: DateTime.now()));

  @override
  Future<WalletSummary> walletSummary() async {
    await _wait(250);
    var escrow = 0, incoming = 0;
    for (final r in _requests.values) {
      if (r.paymentStatus == PaymentStatus.held || r.paymentStatus == PaymentStatus.disputed) {
        if (r.customerId == _uid) escrow += r.quotedPriceKobo ?? 0;
        if (r.mechanicId == _uid) incoming += r.quotedPriceKobo ?? 0;
      }
    }
    return WalletSummary(availableKobo: _available, inEscrowKobo: escrow, incomingKobo: incoming, allowTestTopups: true);
  }

  @override
  Future<List<WalletTxn>> transactions({int limit = 50}) async => _txns.take(limit).toList();

  @override
  Future<({String url, String reference})> startTopup(int amountKobo) async =>
      throw const AppException('Card payments are simulated in demo mode. Use "Add test money".');

  @override
  Future<String> verifyTopup(String reference) async => 'pending';

  @override
  Future<void> testTopup(int amountKobo) async {
    await _wait();
    _available += amountKobo;
    _txn('test_topup', amountKobo, 'Test money (not real)');
  }

  @override
  Future<void> fundEscrow(String requestId) async {
    await _wait(700);
    final r = _requests[requestId]!;
    final price = r.quotedPriceKobo!;
    if (_available < price) throw const AppException('Not enough money in your wallet');
    _available -= price;
    _txn('escrow_hold', -price, 'Held in escrow: ${r.serviceType}');
    _put(r.copyWith(paymentStatus: PaymentStatus.held));
    _maybeStartWork(requestId);
  }

  @override
  Future<void> releaseEscrow(String requestId) async {
    await _wait(700);
    final r = _requests[requestId]!;
    _put(r.copyWith(paymentStatus: PaymentStatus.released));
    final i = _txns.indexWhere((t) => t.kind == 'escrow_hold' && t.description?.endsWith(r.serviceType) == true);
    if (i >= 0) {
      final t = _txns[i];
      _txns[i] = WalletTxn(id: t.id, kind: 'escrow_release', amountKobo: t.amountKobo, description: 'Paid: ${r.serviceType}', createdAt: t.createdAt);
    }
  }

  @override
  Future<void> disputeEscrow(String requestId, String reason) async {
    await _wait();
    final r = _requests[requestId]!;
    _put(r.copyWith(paymentStatus: PaymentStatus.disputed));
  }

  @override
  Future<List<Bank>> banks() async => const [
        Bank('Access Bank', '044'),
        Bank('First Bank of Nigeria', '011'),
        Bank('Guaranty Trust Bank', '058'),
        Bank('Kuda Bank', '50211'),
        Bank('Moniepoint MFB', '50515'),
        Bank('OPay', '999992'),
        Bank('United Bank for Africa', '033'),
        Bank('Zenith Bank', '057'),
      ];

  @override
  Future<String?> resolveAccount(String accountNumber, String bankCode) async {
    await _wait(600);
    return (_profile?.fullName ?? 'Tunde Bakare').toUpperCase();
  }

  @override
  Future<PayoutAccount?> payoutAccount() async => _payout;

  @override
  Future<void> savePayoutAccount(PayoutAccount a) async {
    await _wait();
    _payout = a;
  }

  @override
  Future<String> withdraw(int amountKobo) async {
    await _wait(800);
    if (_payout == null) throw const AppException('Add your bank account first');
    if (amountKobo < 10000) throw const AppException('The minimum withdrawal is ₦100');
    if (amountKobo > _available) throw const AppException('Not enough money in your wallet');
    _available -= amountKobo;
    _txn('withdrawal', -amountKobo, 'Withdrawal to ${_payout!.bankName}');
    return 'Withdrawal sent. It usually lands within minutes.';
  }

  // ---- Recycling ----------------------------------------------------------------
  static const _rates = [
    RecyclingRate(itemType: 'lead_acid_battery', label: 'Car battery', unit: 'unit', rateKobo: 350000, co2Kg: 9, description: 'Lead-acid starter batteries. Lead and acid are recovered safely.'),
    RecyclingRate(itemType: 'lithium_battery', label: 'Hybrid / EV battery', unit: 'kg', rateKobo: 90000, co2Kg: 4, description: 'Lithium-ion packs and modules. Collected by trained handlers only.'),
    RecyclingRate(itemType: 'tyres', label: 'Tyres', unit: 'unit', rateKobo: 50000, co2Kg: 15, description: 'Worn tyres for crumb rubber and road surfacing.'),
    RecyclingRate(itemType: 'used_oil', label: 'Used engine oil', unit: 'litre', rateKobo: 15000, co2Kg: 3, description: 'Drained engine or gear oil, sealed in a container.'),
    RecyclingRate(itemType: 'scrap_metal', label: 'Scrap metal & parts', unit: 'kg', rateKobo: 25000, co2Kg: 1.5, description: 'Body panels, rims, exhausts, engine blocks.'),
    RecyclingRate(itemType: 'end_of_life_vehicle', label: 'Whole vehicle', unit: 'unit', rateKobo: 15000000, co2Kg: 1500, description: 'Cars that can no longer be repaired. We collect and dismantle.'),
  ];
  static const _centres = [
    RecyclingCentre(id: 'c1', name: 'AutoWave Hub Ikeja', address: 'Obafemi Awolowo Way, Ikeja, Lagos', lat: 6.6018, lng: 3.3515, accepts: ['lead_acid_battery', 'lithium_battery', 'scrap_metal', 'end_of_life_vehicle'], hours: 'Mon–Fri, 9am–5pm'),
    RecyclingCentre(id: 'c2', name: 'AutoWave Hub Lekki', address: 'Admiralty Way, Lekki Phase 1, Lagos', lat: 6.4474, lng: 3.4727, accepts: ['lead_acid_battery', 'tyres', 'used_oil'], hours: 'Mon–Sat, 9am–5pm'),
    RecyclingCentre(id: 'c3', name: 'AutoWave Hub Yaba', address: 'Herbert Macaulay Way, Yaba, Lagos', lat: 6.5146, lng: 3.3760, accepts: ['lead_acid_battery', 'tyres', 'used_oil', 'scrap_metal'], hours: 'Mon–Sat, 8am–6pm'),
  ];

  @override
  Future<List<RecyclingRate>> recyclingRates() async => _rates;
  @override
  Future<List<RecyclingCentre>> recyclingCentres() async => _centres;
  @override
  Future<List<RecyclingRequest>> myRecycling() async {
    await _wait(250);
    return List.of(_recycling);
  }

  @override
  Future<RecyclingImpact> recyclingImpact() async {
    var co2 = 0.0;
    var items = 0;
    for (final r in _recycling) {
      if (r.status == 'collected' || r.status == 'paid') co2 += r.estimatedCo2Kg;
      if (r.status != 'cancelled') items++;
    }
    final paid = _txns.where((t) => t.kind == 'recycling_payout').fold<int>(0, (a, t) => a + t.amountKobo);
    return RecyclingImpact(co2Kg: co2, paidKobo: paid, items: items);
  }

  @override
  Future<void> submitRecycling({
    required String itemType,
    required double quantity,
    String? condition,
    String? notes,
    required String method,
    String? centreId,
    Place? pickup,
    DateTime? preferredDate,
  }) async {
    await _wait(600);
    final rate = _rates.firstWhere((r) => r.itemType == itemType);
    final id = _id();
    _recycling.insert(
      0,
      RecyclingRequest(
        id: id,
        itemType: itemType,
        quantity: quantity,
        method: method,
        pickupAddress: pickup?.address,
        centreName: method == 'dropoff' ? _centres.firstWhere((c) => c.id == centreId).name : null,
        preferredDate: preferredDate,
        estimatedValueKobo: (rate.rateKobo * quantity).round(),
        estimatedCo2Kg: (rate.co2Kg * quantity * 10).round() / 10,
        status: 'submitted',
        createdAt: DateTime.now(),
      ),
    );
    _later(6000, () {
      final i = _recycling.indexWhere((r) => r.id == id);
      if (i < 0 || _recycling[i].status != 'submitted') return;
      final r = _recycling[i];
      _recycling[i] = RecyclingRequest(
        id: r.id,
        itemType: r.itemType,
        quantity: r.quantity,
        method: r.method,
        pickupAddress: r.pickupAddress,
        centreName: r.centreName,
        preferredDate: r.preferredDate,
        estimatedValueKobo: r.estimatedValueKobo,
        estimatedCo2Kg: r.estimatedCo2Kg,
        status: 'scheduled',
        createdAt: r.createdAt,
      );
    });
  }

  @override
  Future<void> cancelRecycling(String id) async {
    await _wait();
    final i = _recycling.indexWhere((r) => r.id == id);
    final r = _recycling[i];
    _recycling[i] = RecyclingRequest(
      id: r.id,
      itemType: r.itemType,
      quantity: r.quantity,
      method: r.method,
      pickupAddress: r.pickupAddress,
      centreName: r.centreName,
      preferredDate: r.preferredDate,
      estimatedValueKobo: r.estimatedValueKobo,
      estimatedCo2Kg: r.estimatedCo2Kg,
      status: 'cancelled',
      createdAt: r.createdAt,
    );
  }

  // ---- AutoLearn ----------------------------------------------------------------
  @override
  Future<List<LearnMessage>> learnHistory() async => List.of(_learn);

  @override
  Future<String> askAutoLearn({required String message, required String level, required String language, String? topic}) async {
    await _wait(1400);
    final q = message.toLowerCase();
    String reply;
    if (q.contains('quiz')) {
      reply = 'Here\'s your question:\n\nWhat does a car battery mainly do in a petrol car?\n\nA) Turns the wheels\nB) Starts the engine and powers the lights when the engine is off\nC) Cools the engine\nD) Stores petrol\n\nReply with A, B, C or D.';
    } else if (RegExp(r'^\s*[abcd]\s*\)?\s*$').hasMatch(q)) {
      reply = q.trim().startsWith('b')
          ? 'Correct! The battery gives the starter motor a big burst of power to turn the engine. Once the engine runs, the alternator takes over and recharges the battery.\n\nTry this: next time you\'re in a car, notice how the headlights dim slightly when the engine starts. That\'s the starter pulling power.'
          : 'Not quite. The answer is B. The battery starts the engine and powers things like lights and radio when the engine is off. Once the engine runs, the alternator recharges it.';
    } else if (q.contains('electric') || q.contains(' ev') || q.contains('ev ') || q.contains('battery') || q.contains('batteries')) {
      reply = 'An electric vehicle stores energy in a big battery made of many small cells, a bit like hundreds of phone batteries working together. The battery sends electricity to a motor, and the motor turns the wheels. There\'s no petrol and no exhaust pipe, so it doesn\'t release smoke on the road.\n\nWhen an EV slows down, the motor can work backwards like a generator and put some energy back into the battery. That\'s called regenerative braking.\n\nTry this: count how many devices at home run on rechargeable batteries. Each one uses the same idea as an EV, just smaller.';
    } else if (q.contains('engine') || q.contains('petrol')) {
      reply = 'A petrol engine is a machine that turns small explosions into movement. Inside each cylinder, a mix of petrol and air is squeezed by a piston, then a spark plug lights it. The burning gas pushes the piston down, and that push turns the crankshaft, which turns the wheels.\n\nThis happens thousands of times a minute, in four steps: suck, squeeze, bang, blow (intake, compression, power, exhaust).\n\nTry this: say "suck, squeeze, bang, blow" while moving your fist up and down. You\'ve just acted out a four-stroke engine.';
    } else if (q.contains('carbon') || q.contains('emission') || q.contains('climate') || q.contains('pollution')) {
      reply = 'When petrol or diesel burns in an engine, it makes carbon dioxide (CO₂) and other gases that come out of the exhaust. CO₂ traps heat in the atmosphere, which warms the planet. Older, poorly maintained vehicles also release soot that harms our lungs, which is why air in busy roads like Ojuelegba can feel heavy.\n\nWays to cut emissions: keep engines serviced, check tyre pressure, avoid idling in traffic, share rides, and over time move to cleaner vehicles.\n\nTry this: stand near a busy road for one minute and count the vehicles with visible smoke. Each one is wasting fuel as well as polluting.';
    } else if (q.contains('career') || q.contains('job') || q.contains('engineer')) {
      reply = 'There are lots of paths into the automotive and green economy:\n- Auto technician: diagnose and repair vehicles\n- EV and battery technician: service electric and hybrid systems\n- Mechanical or electrical engineer: design vehicles and parts\n- Recycling and materials specialist: recover metals from old batteries and cars\n- Software developer: build apps like AutoWave and the computers inside cars\n\nYou can start now with maths, physics and simple projects, like fixing a bicycle or building a small solar circuit.';
    } else {
      reply = 'Good question! In demo mode I can answer topics like engines, batteries and electric vehicles, carbon emissions, careers, or give you a quiz. Once AutoLearn is connected to the server, I can answer anything about science, cars and sustainability, at your level and in your language.';
    }
    if (language != 'English') reply = '($language replies work once AutoLearn is connected. Showing English in demo mode.)\n\n$reply';
    _learn.add(LearnMessage(role: 'user', content: message, createdAt: DateTime.now()));
    _learn.add(LearnMessage(role: 'assistant', content: reply, createdAt: DateTime.now()));
    return reply;
  }

  @override
  Future<void> clearLearnHistory() async => _learn.clear();
}
