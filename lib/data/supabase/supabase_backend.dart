import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/utils/format.dart';
import '../backend.dart';
import '../models.dart';

class SupabaseBackend implements AppBackend {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  bool get isDemo => false;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw const AppException('Please sign in again.');
    return id;
  }

  /// Calls an Edge Function and turns its {"error": "..."} replies into [AppException]s.
  Future<Map<String, dynamic>> _fn(String name, Map<String, dynamic> body) async {
    try {
      final res = await _db.functions.invoke(name, body: body);
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return const {};
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map && d['error'] is String ? d['error'] as String : null;
      if (e.status == 404 && msg == null) {
        throw const AppException('This feature\'s server function isn\'t deployed yet.');
      }
      throw AppException(msg ?? 'The server couldn\'t complete that. Try again.');
    }
  }

  Future<T> _rpc<T>(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _db.rpc(fn, params: params) as T;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == 'PGRST205') {
        throw const AppException('The server isn\'t set up yet. Run the database migration in Supabase.');
      }
      throw AppException(e.message);
    }
  }

  // ---- Auth -----------------------------------------------------------------
  @override
  String? get currentUserId => _db.auth.currentUser?.id;
  @override
  String? get currentEmail => _db.auth.currentUser?.email;

  @override
  Stream<String?> get userChanges => _db.auth.onAuthStateChange.map((s) => s.session?.user.id);

  @override
  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _db.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw AppException(friendlyError(e.message));
    }
  }

  @override
  Future<bool> signUpWithEmail({required String fullName, required String email, required String password}) async {
    try {
      final res = await _db.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim()},
        emailRedirectTo: kIsWeb ? null : Env.authRedirect,
      );
      return res.session == null;
    } on AuthException catch (e) {
      throw AppException(e.message);
    }
  }

  @override
  Future<void> resetPassword(String email) async {
    await _db.auth.resetPasswordForEmail(email.trim(), redirectTo: kIsWeb ? null : Env.authRedirect);
  }

  @override
  Future<void> sendPhoneCode(String phoneE164) async {
    try {
      await _db.auth.signInWithOtp(phone: phoneE164);
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('provider') || e.message.toLowerCase().contains('disabled')) {
        throw const AppException('Phone sign-in isn\'t switched on yet. Use email or Google for now.');
      }
      throw AppException(e.message);
    }
  }

  @override
  Future<void> verifyPhoneCode(String phoneE164, String code) async {
    try {
      await _db.auth.verifyOTP(phone: phoneE164, token: code.trim(), type: OtpType.sms);
    } on AuthException catch (e) {
      throw AppException(e.message.contains('expired') || e.message.contains('invalid')
          ? 'That code is wrong or has expired. Request a new one.'
          : e.message);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    await _db.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : Env.authRedirect,
      authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  @override
  Future<void> signOut() => _db.auth.signOut();

  // ---- Profile --------------------------------------------------------------
  @override
  Future<Profile?> myProfile() async {
    final id = currentUserId;
    if (id == null) return null;
    try {
      final row = await _db.from('profiles').select().eq('id', id).maybeSingle();
      if (row == null) return Profile(id: id, email: currentEmail);
      return Profile.fromMap(row, email: currentEmail);
    } on PostgrestException catch (e) {
      throw AppException(friendlyError(e));
    }
  }

  @override
  Future<void> setRole(UserRole role, {String? fullName, String? phone, String? countryCode}) =>
      _rpc('set_my_role', {'p_role': role.name, 'p_full_name': fullName, 'p_phone': phone, 'p_country_code': countryCode});

  @override
  Future<void> updateProfile({required String fullName, required String phone, required String countryCode}) =>
      _rpc('update_my_profile', {'p_full_name': fullName, 'p_phone': phone, 'p_country_code': countryCode});

  // ---- Places ---------------------------------------------------------------
  @override
  Future<List<PlaceSuggestion>> placeAutocomplete(String input, {double? lat, double? lng, String? country, String? session}) async {
    final r = await _fn('places', {
      'action': 'autocomplete',
      'input': input,
      'lat': ?lat,
      'lng': ?lng,
      'country': ?country,
      'session': ?session,
    });
    return ((r['predictions'] as List?) ?? const [])
        .map((p) => PlaceSuggestion(placeId: p['placeId'] as String, title: p['title'] as String, subtitle: (p['subtitle'] as String?) ?? ''))
        .toList();
  }

  @override
  Future<Place> placeDetails(PlaceSuggestion s, {String? session}) async {
    final r = await _fn('places', {'action': 'details', 'placeId': s.placeId, 'session': ?session});
    return Place(
      address: (r['address'] as String?) ?? s.title,
      title: s.title,
      lat: (r['lat'] as num).toDouble(),
      lng: (r['lng'] as num).toDouble(),
    );
  }

  // ---- Driver ---------------------------------------------------------------
  @override
  Future<List<MechanicSummary>> searchMechanics({required double lat, required double lng, int? budgetKobo, String? service, double radiusKm = 25}) async {
    final rows = await _rpc<List>('search_mechanics', {
      'p_lat': lat,
      'p_lng': lng,
      'p_budget_kobo': budgetKobo,
      'p_service': service,
      'p_radius_km': radiusKm,
    });
    return rows.map((r) => MechanicSummary.fromMap(Map<String, dynamic>.from(r as Map))).toList();
  }

  @override
  Future<List<Review>> mechanicReviews(String mechanicId) async {
    final rows = await _rpc<List>('mechanic_reviews', {'p_mechanic_id': mechanicId, 'p_limit': 30});
    return rows.map((r) => Review.fromMap(Map<String, dynamic>.from(r as Map))).toList();
  }

  @override
  Future<String> createRequest({required String mechanicId, required String serviceType, String? description, required Place place, int? budgetKobo}) async {
    final id = await _rpc<String>('create_request', {
      'p_mechanic_id': mechanicId,
      'p_service_type': serviceType,
      'p_description': description,
      'p_pickup_address': place.address,
      'p_pickup_lat': place.lat,
      'p_pickup_lng': place.lng,
      'p_budget_kobo': budgetKobo,
    });
    return id;
  }

  @override
  Stream<ServiceRequest?> watchRequest(String requestId) => _db
      .from('service_requests')
      .stream(primaryKey: ['id'])
      .eq('id', requestId)
      .map((rows) => rows.isEmpty ? null : ServiceRequest.fromMap(rows.first));

  @override
  Future<ServiceRequest?> activeRequest() async {
    final rows = await _db
        .from('service_requests')
        .select()
        .eq('customer_id', _uid)
        .inFilter('status', ['requested', 'accepted', 'en_route', 'arrived', 'in_progress', 'completed'])
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    final r = ServiceRequest.fromMap(rows.first);
    // A completed job stays "active" until the driver releases (or disputes) the payment.
    if (r.status == RequestStatus.completed && r.paymentStatus != PaymentStatus.held) return null;
    if (r.status == RequestStatus.requested && r.respondBy.isBefore(DateTime.now())) return null;
    return r;
  }

  @override
  Future<List<ServiceRequest>> myJobs({int limit = 30}) async {
    final rows = await _db
        .from('service_requests')
        .select()
        .or('customer_id.eq.$_uid,mechanic_id.eq.$_uid')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(ServiceRequest.fromMap).toList();
  }

  @override
  Future<void> cancelRequest(String requestId, {String? reason}) =>
      _rpc('cancel_request', {'p_request_id': requestId, 'p_reason': reason});

  @override
  Future<void> expireStale() => _rpc('expire_stale_requests');

  @override
  Future<Counterpart> counterpart(String requestId) async {
    final rows = await _rpc<List>('request_counterpart', {'p_request_id': requestId});
    if (rows.isEmpty) return const Counterpart(name: 'Your mechanic');
    final m = Map<String, dynamic>.from(rows.first as Map);
    final name = (m['display_name'] as String?)?.trim();
    return Counterpart(name: (name == null || name.isEmpty) ? 'Your mechanic' : name, phone: m['phone'] as String?);
  }

  @override
  Stream<MechanicPoint?> watchMechanicLocation(String mechanicId) => _db
      .from('mechanic_locations')
      .stream(primaryKey: ['mechanic_id'])
      .eq('mechanic_id', mechanicId)
      .map((rows) => rows.isEmpty
          ? null
          : MechanicPoint(
              lat: (rows.first['latitude'] as num).toDouble(),
              lng: (rows.first['longitude'] as num).toDouble(),
              updatedAt: DateTime.tryParse(rows.first['updated_at'] as String? ?? '')?.toLocal(),
            ));

  @override
  Future<EtaResult> fetchEta(String requestId, {bool includeRoute = false}) async {
    final m = await _fn('eta', {'requestId': requestId, 'includeRoute': includeRoute});
    final mech = m['mechanic'];
    return EtaResult(
      seconds: (m['seconds'] as num?)?.toInt(),
      meters: (m['meters'] as num?)?.toInt(),
      route: m['route'] is String ? decodePolyline(m['route'] as String) : null,
      mechanic: mech is Map
          ? MechanicPoint(lat: (mech['lat'] as num).toDouble(), lng: (mech['lng'] as num).toDouble())
          : null,
    );
  }

  @override
  Future<bool> hasReviewed(String requestId) async {
    final rows = await _db.from('reviews').select('id').eq('request_id', requestId).limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<void> submitReview({required String requestId, required String mechanicId, required int rating, String? comment}) async {
    try {
      await _db.from('reviews').insert({
        'request_id': requestId,
        'customer_id': _uid,
        'mechanic_id': mechanicId,
        'rating': rating,
        'comment': (comment == null || comment.trim().isEmpty) ? null : comment.trim(),
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw const AppException('You already reviewed this job.');
      throw AppException(e.message);
    }
  }

  // ---- Mechanic -------------------------------------------------------------
  @override
  Future<WorkshopProfile?> myWorkshop() async {
    final row = await _db.from('mechanic_profiles').select().eq('id', _uid).maybeSingle();
    return row == null ? null : WorkshopProfile.fromMap(row);
  }

  @override
  Future<void> saveWorkshop(WorkshopProfile w) => _rpc('save_mechanic_profile', {
        'p_business_name': w.businessName,
        'p_bio': w.bio,
        'p_services': w.services,
        'p_min_price_kobo': w.minPriceKobo,
        'p_base_address': w.baseAddress,
        'p_base_lat': w.baseLat,
        'p_base_lng': w.baseLng,
        'p_service_radius_km': w.serviceRadiusKm,
        'p_years_experience': w.yearsExperience,
      });

  @override
  Future<void> setOnline(bool online) => _rpc('set_online', {'p_online': online});

  @override
  Stream<List<ServiceRequest>> watchMechanicJobs() => _db
      .from('service_requests')
      .stream(primaryKey: ['id'])
      .eq('mechanic_id', _uid)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.map(ServiceRequest.fromMap).toList());

  @override
  Future<void> respondToRequest(String requestId, {required bool accept, int? quoteKobo, int? etaMinutes}) =>
      _rpc('respond_to_request', {
        'p_request_id': requestId,
        'p_accept': accept,
        'p_quote_kobo': quoteKobo,
        'p_eta_minutes': etaMinutes,
      });

  @override
  Future<void> updateJobStatus(String requestId, RequestStatus status) =>
      _rpc('update_job_status', {'p_request_id': requestId, 'p_status': requestStatusToDb(status)});

  @override
  Future<void> publishLocation(double lat, double lng, double? heading) async {
    await _db.from('mechanic_locations').upsert({
      'mechanic_id': _uid,
      'latitude': lat,
      'longitude': lng,
      'heading': heading,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // ---- Wallet ---------------------------------------------------------------
  @override
  Future<WalletSummary> walletSummary() async {
    final rows = await _rpc<List>('wallet_summary');
    return rows.isEmpty
        ? const WalletSummary(availableKobo: 0, inEscrowKobo: 0, incomingKobo: 0, allowTestTopups: false)
        : WalletSummary.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Future<List<WalletTxn>> transactions({int limit = 50}) async {
    final rows = await _db.from('wallet_transactions').select().eq('user_id', _uid).order('created_at', ascending: false).limit(limit);
    return rows.map(WalletTxn.fromMap).toList();
  }

  @override
  Future<({String url, String reference})> startTopup(int amountKobo) async {
    final r = await _fn('paystack-init', {'amountKobo': amountKobo});
    return (url: r['authorizationUrl'] as String, reference: r['reference'] as String);
  }

  @override
  Future<String> verifyTopup(String reference) async {
    final r = await _fn('paystack-verify', {'reference': reference});
    return (r['status'] as String?) ?? 'pending';
  }

  @override
  Future<void> testTopup(int amountKobo) => _rpc('test_topup', {'p_amount_kobo': amountKobo});

  @override
  Future<void> fundEscrow(String requestId) => _rpc('fund_escrow', {'p_request_id': requestId});

  @override
  Future<void> releaseEscrow(String requestId) => _rpc('release_escrow', {'p_request_id': requestId});

  @override
  Future<void> disputeEscrow(String requestId, String reason) =>
      _rpc('dispute_escrow', {'p_request_id': requestId, 'p_reason': reason});

  @override
  Future<List<Bank>> banks() async {
    final r = await _fn('paystack-payout', {'action': 'banks'});
    return ((r['banks'] as List?) ?? const []).map((b) => Bank(b['name'] as String, b['code'] as String)).toList();
  }

  @override
  Future<String?> resolveAccount(String accountNumber, String bankCode) async {
    final r = await _fn('paystack-payout', {'action': 'resolve', 'accountNumber': accountNumber, 'bankCode': bankCode});
    return r['accountName'] as String?;
  }

  @override
  Future<PayoutAccount?> payoutAccount() async {
    final row = await _db.from('payout_accounts').select().eq('user_id', _uid).maybeSingle();
    if (row == null) return null;
    return PayoutAccount(
      bankName: row['bank_name'] as String,
      bankCode: row['bank_code'] as String,
      accountNumber: row['account_number'] as String,
      accountName: row['account_name'] as String?,
    );
  }

  @override
  Future<void> savePayoutAccount(PayoutAccount a) => _rpc('save_payout_account', {
        'p_bank_name': a.bankName,
        'p_bank_code': a.bankCode,
        'p_account_number': a.accountNumber,
        'p_account_name': a.accountName,
      });

  @override
  Future<String> withdraw(int amountKobo) async {
    final id = await _rpc<String>('request_withdrawal', {'p_amount_kobo': amountKobo});
    try {
      final r = await _fn('paystack-payout', {'action': 'send', 'withdrawalId': id});
      if (r['status'] == 'failed') return 'The bank transfer failed, so the money is back in your wallet.';
      return 'Withdrawal sent. It usually lands within minutes.';
    } on AppException {
      // Payouts not connected yet: the request stays pending for manual processing.
      return 'Withdrawal requested. We\'ll pay it to your bank shortly.';
    }
  }

  // ---- Recycling ------------------------------------------------------------
  @override
  Future<List<RecyclingRate>> recyclingRates() async {
    final rows = await _db.from('recycling_rates').select().order('sort_order');
    return rows.map(RecyclingRate.fromMap).toList();
  }

  @override
  Future<List<RecyclingCentre>> recyclingCentres() async {
    final rows = await _db.from('recycling_centres').select().order('name');
    return rows.map(RecyclingCentre.fromMap).toList();
  }

  @override
  Future<List<RecyclingRequest>> myRecycling() async {
    final rows = await _db
        .from('recycling_requests')
        .select('*, recycling_centres(name)')
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map(RecyclingRequest.fromMap).toList();
  }

  @override
  Future<RecyclingImpact> recyclingImpact() async {
    final rows = await _rpc<List>('my_recycling_impact');
    if (rows.isEmpty) return const RecyclingImpact(co2Kg: 0, paidKobo: 0, items: 0);
    final m = Map<String, dynamic>.from(rows.first as Map);
    return RecyclingImpact(
      co2Kg: (m['total_co2_kg'] as num?)?.toDouble() ?? 0,
      paidKobo: (m['total_paid_kobo'] as num?)?.toInt() ?? 0,
      items: (m['items'] as num?)?.toInt() ?? 0,
    );
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
  }) =>
      _rpc('submit_recycling', {
        'p_item_type': itemType,
        'p_quantity': quantity,
        'p_condition': condition,
        'p_notes': notes,
        'p_method': method,
        'p_centre_id': centreId,
        'p_pickup_address': pickup?.address,
        'p_pickup_lat': pickup?.lat,
        'p_pickup_lng': pickup?.lng,
        'p_preferred_date': preferredDate?.toIso8601String().substring(0, 10),
      });

  @override
  Future<void> cancelRecycling(String id) => _rpc('cancel_recycling', {'p_id': id});

  // ---- AutoLearn ------------------------------------------------------------
  @override
  Future<List<LearnMessage>> learnHistory() async {
    final rows = await _db.from('learn_messages').select('role, content, created_at').eq('user_id', _uid).order('created_at').limit(200);
    return rows
        .map((r) => LearnMessage(role: r['role'] as String, content: r['content'] as String, createdAt: DateTime.parse(r['created_at'] as String).toLocal()))
        .toList();
  }

  @override
  Future<String> askAutoLearn({required String message, required String level, required String language, String? topic}) async {
    final r = await _fn('autolearn', {'message': message, 'level': level, 'language': language, 'topic': ?topic});
    return (r['reply'] as String?) ?? '';
  }

  @override
  Future<void> clearLearnHistory() async {
    await _db.from('learn_messages').delete().eq('user_id', _uid);
  }
}

/// Decodes Google's encoded polyline format into map coordinates.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    var shift = 0, result = 0, b = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

// Keeps the import used when the fallback ETA is computed on the client.
int fallbackEta(double fromLat, double fromLng, double toLat, double toLng) =>
    roughEtaSeconds(haversineKm(fromLat, fromLng, toLat, toLng));
