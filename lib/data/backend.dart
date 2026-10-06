import 'models.dart';

/// Everything the screens need from the server. Two implementations:
///  - [SupabaseBackend]: the real thing.
///  - [DemoBackend]: in-memory sample data with a simulated mechanic/driver,
///    used with --dart-define=DEMO=true.
abstract class AppBackend {
  bool get isDemo;

  // ---- Auth -----------------------------------------------------------------
  String? get currentUserId;
  String? get currentEmail;
  Stream<String?> get userChanges;
  Future<void> signInWithEmail(String email, String password);

  /// Returns true when the user must confirm their email before signing in.
  Future<bool> signUpWithEmail({required String fullName, required String email, required String password});
  Future<void> resetPassword(String email);
  Future<void> sendPhoneCode(String phoneE164);
  Future<void> verifyPhoneCode(String phoneE164, String code);
  Future<void> signInWithGoogle();
  Future<void> signOut();

  // ---- Profile --------------------------------------------------------------
  Future<Profile?> myProfile();
  Future<void> setRole(UserRole role, {String? fullName, String? phone, String? countryCode});
  Future<void> updateProfile({required String fullName, required String phone, required String countryCode});

  // ---- Places ---------------------------------------------------------------
  Future<List<PlaceSuggestion>> placeAutocomplete(String input, {double? lat, double? lng, String? country, String? session});
  Future<Place> placeDetails(PlaceSuggestion s, {String? session});

  // ---- Driver: search + requests --------------------------------------------
  Future<List<MechanicSummary>> searchMechanics({required double lat, required double lng, int? budgetKobo, String? service, double radiusKm = 25});
  Future<List<Review>> mechanicReviews(String mechanicId);
  Future<String> createRequest({
    required String mechanicId,
    required String serviceType,
    String? description,
    required Place place,
    int? budgetKobo,
  });
  Stream<ServiceRequest?> watchRequest(String requestId);
  Future<ServiceRequest?> activeRequest();
  Future<List<ServiceRequest>> myJobs({int limit = 30});
  Future<void> cancelRequest(String requestId, {String? reason});
  Future<void> expireStale();
  Future<Counterpart> counterpart(String requestId);
  Stream<MechanicPoint?> watchMechanicLocation(String mechanicId);
  Future<EtaResult> fetchEta(String requestId, {bool includeRoute = false});
  Future<bool> hasReviewed(String requestId);
  Future<void> submitReview({required String requestId, required String mechanicId, required int rating, String? comment});

  // ---- Mechanic -------------------------------------------------------------
  Future<WorkshopProfile?> myWorkshop();
  Future<void> saveWorkshop(WorkshopProfile w);
  Future<void> setOnline(bool online);
  Stream<List<ServiceRequest>> watchMechanicJobs();
  Future<void> respondToRequest(String requestId, {required bool accept, int? quoteKobo, int? etaMinutes});
  Future<void> updateJobStatus(String requestId, RequestStatus status);
  Future<void> publishLocation(double lat, double lng, double? heading);

  // ---- Wallet + escrow ------------------------------------------------------
  Future<WalletSummary> walletSummary();
  Future<List<WalletTxn>> transactions({int limit = 50});
  Future<({String url, String reference})> startTopup(int amountKobo);
  Future<String> verifyTopup(String reference);
  Future<void> testTopup(int amountKobo);
  Future<void> fundEscrow(String requestId);
  Future<void> releaseEscrow(String requestId);
  Future<void> disputeEscrow(String requestId, String reason);
  Future<List<Bank>> banks();
  Future<String?> resolveAccount(String accountNumber, String bankCode);
  Future<PayoutAccount?> payoutAccount();
  Future<void> savePayoutAccount(PayoutAccount a);

  /// Returns a short status message for the user.
  Future<String> withdraw(int amountKobo);

  // ---- Recycling ------------------------------------------------------------
  Future<List<RecyclingRate>> recyclingRates();
  Future<List<RecyclingCentre>> recyclingCentres();
  Future<List<RecyclingRequest>> myRecycling();
  Future<RecyclingImpact> recyclingImpact();
  Future<void> submitRecycling({
    required String itemType,
    required double quantity,
    String? condition,
    String? notes,
    required String method,
    String? centreId,
    Place? pickup,
    DateTime? preferredDate,
  });
  Future<void> cancelRecycling(String id);

  // ---- AutoLearn ------------------------------------------------------------
  Future<List<LearnMessage>> learnHistory();
  Future<String> askAutoLearn({required String message, required String level, required String language, String? topic});
  Future<void> clearLearnHistory();
}

late AppBackend backend;

/// An error whose message is already written for the user.
class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}

/// Turns server errors into a sentence for the user.
String friendlyError(Object e) {
  if (e is AppException) return e.message;
  final s = e.toString();
  final m = RegExp(r'message: ([^,}]+)').firstMatch(s) ?? RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(s);
  var msg = m?.group(1)?.trim() ?? s.replaceFirst(RegExp(r'^\w*Exception:?\s*'), '');
  if (msg.contains('SocketException') || msg.contains('Failed host lookup') || msg.contains('ClientException')) {
    return 'No internet connection. Check your data and try again.';
  }
  if (msg.contains('Invalid login credentials')) return 'That email and password don\'t match.';
  if (msg.contains('Email not confirmed')) return 'Confirm your email first. We sent you a link.';
  if (msg.contains('PGRST') || msg.contains('schema cache')) {
    return 'The server isn\'t set up yet. Run the database migration in Supabase.';
  }
  if (msg.length > 160) msg = '${msg.substring(0, 157)}…';
  return msg.isEmpty ? 'Something went wrong. Try again.' : msg;
}
