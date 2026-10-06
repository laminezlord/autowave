import 'package:latlong2/latlong.dart';

double _d(Object? v) => (v as num).toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
int? _in(Object? v) => (v as num?)?.toInt();
DateTime _t(Object? v) => DateTime.parse(v as String).toLocal();
DateTime? _tn(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

enum UserRole { driver, mechanic }

UserRole? roleFromDb(String? s) => switch (s) {
      'driver' => UserRole.driver,
      'mechanic' => UserRole.mechanic,
      _ => null,
    };

class Profile {
  final String id;
  final UserRole? role;
  final String? fullName;
  final String? phone;
  final String? countryCode;
  final String? email;

  const Profile({required this.id, this.role, this.fullName, this.phone, this.countryCode, this.email});

  String get firstName {
    final n = (fullName ?? '').trim();
    return n.isEmpty ? 'there' : n.split(' ').first;
  }

  factory Profile.fromMap(Map<String, dynamic> m, {String? email}) => Profile(
        id: m['id'] as String,
        role: roleFromDb(m['role'] as String?),
        fullName: m['full_name'] as String?,
        phone: m['phone'] as String?,
        countryCode: m['country_code'] as String?,
        email: email,
      );
}

/// A place the driver picked in the search bar.
class Place {
  final String address;
  final String title;
  final double lat;
  final double lng;

  const Place({required this.address, required this.title, required this.lat, required this.lng});

  LatLng get latLng => LatLng(lat, lng);
}

class PlaceSuggestion {
  final String placeId;
  final String title;
  final String subtitle;
  const PlaceSuggestion({required this.placeId, required this.title, required this.subtitle});
}

const kServiceTypes = <String>[
  'General repair',
  'Engine repair',
  'Battery & electrics',
  'Brakes',
  'Tyres & vulcanising',
  'Towing',
  'AC & cooling',
  'Diagnostics',
  'Oil change',
];

class MechanicSummary {
  final String id;
  final String businessName;
  final String? bio;
  final List<String> services;
  final int minPriceKobo;
  final String baseAddress;
  final double lat;
  final double lng;
  final int yearsExperience;
  final double ratingAvg;
  final int ratingCount;
  final int jobsCompleted;
  final double distanceKm;
  final bool withinBudget;

  const MechanicSummary({
    required this.id,
    required this.businessName,
    this.bio,
    required this.services,
    required this.minPriceKobo,
    required this.baseAddress,
    required this.lat,
    required this.lng,
    required this.yearsExperience,
    required this.ratingAvg,
    required this.ratingCount,
    required this.jobsCompleted,
    required this.distanceKm,
    required this.withinBudget,
  });

  factory MechanicSummary.fromMap(Map<String, dynamic> m) => MechanicSummary(
        id: m['id'] as String,
        businessName: m['business_name'] as String,
        bio: m['bio'] as String?,
        services: ((m['services'] as List?) ?? const []).map((e) => e.toString()).toList(),
        minPriceKobo: _i(m['min_price_kobo']),
        baseAddress: (m['base_address'] as String?) ?? '',
        lat: _d(m['base_lat']),
        lng: _d(m['base_lng']),
        yearsExperience: _i(m['years_experience']),
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: _i(m['rating_count']),
        jobsCompleted: _i(m['jobs_completed']),
        distanceKm: (m['distance_km'] as num?)?.toDouble() ?? 0,
        withinBudget: (m['within_budget'] as bool?) ?? true,
      );
}

class Review {
  final String id;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String reviewer;
  final String? serviceType;

  const Review({required this.id, required this.rating, this.comment, required this.createdAt, required this.reviewer, this.serviceType});

  factory Review.fromMap(Map<String, dynamic> m) => Review(
        id: m['id'] as String,
        rating: _i(m['rating']),
        comment: m['comment'] as String?,
        createdAt: _t(m['created_at']),
        reviewer: (m['reviewer'] as String?) ?? 'Driver',
        serviceType: m['service_type'] as String?,
      );
}

/// The mechanic's own workshop profile (onboarding / settings).
class WorkshopProfile {
  final String businessName;
  final String? bio;
  final List<String> services;
  final int minPriceKobo;
  final String baseAddress;
  final double baseLat;
  final double baseLng;
  final int serviceRadiusKm;
  final int yearsExperience;
  final bool isOnline;
  final double ratingAvg;
  final int ratingCount;
  final int jobsCompleted;

  const WorkshopProfile({
    required this.businessName,
    this.bio,
    required this.services,
    required this.minPriceKobo,
    required this.baseAddress,
    required this.baseLat,
    required this.baseLng,
    this.serviceRadiusKm = 15,
    this.yearsExperience = 0,
    this.isOnline = true,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.jobsCompleted = 0,
  });

  factory WorkshopProfile.fromMap(Map<String, dynamic> m) => WorkshopProfile(
        businessName: m['business_name'] as String,
        bio: m['bio'] as String?,
        services: ((m['services'] as List?) ?? const []).map((e) => e.toString()).toList(),
        minPriceKobo: _i(m['min_price_kobo']),
        baseAddress: m['base_address'] as String,
        baseLat: _d(m['base_lat']),
        baseLng: _d(m['base_lng']),
        serviceRadiusKm: _i(m['service_radius_km']),
        yearsExperience: _i(m['years_experience']),
        isOnline: (m['is_online'] as bool?) ?? true,
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: _i(m['rating_count']),
        jobsCompleted: _i(m['jobs_completed']),
      );

  WorkshopProfile copyWith({bool? isOnline}) => WorkshopProfile(
        businessName: businessName,
        bio: bio,
        services: services,
        minPriceKobo: minPriceKobo,
        baseAddress: baseAddress,
        baseLat: baseLat,
        baseLng: baseLng,
        serviceRadiusKm: serviceRadiusKm,
        yearsExperience: yearsExperience,
        isOnline: isOnline ?? this.isOnline,
        ratingAvg: ratingAvg,
        ratingCount: ratingCount,
        jobsCompleted: jobsCompleted,
      );
}

enum RequestStatus { requested, accepted, rejected, expired, cancelled, enRoute, arrived, inProgress, completed }

RequestStatus requestStatusFromDb(String s) => switch (s) {
      'requested' => RequestStatus.requested,
      'accepted' => RequestStatus.accepted,
      'rejected' => RequestStatus.rejected,
      'expired' => RequestStatus.expired,
      'cancelled' => RequestStatus.cancelled,
      'en_route' => RequestStatus.enRoute,
      'arrived' => RequestStatus.arrived,
      'in_progress' => RequestStatus.inProgress,
      'completed' => RequestStatus.completed,
      _ => RequestStatus.requested,
    };

String requestStatusToDb(RequestStatus s) => switch (s) {
      RequestStatus.enRoute => 'en_route',
      RequestStatus.inProgress => 'in_progress',
      _ => s.name,
    };

enum PaymentStatus { unpaid, held, released, refunded, disputed }

PaymentStatus paymentStatusFromDb(String? s) =>
    PaymentStatus.values.firstWhere((e) => e.name == s, orElse: () => PaymentStatus.unpaid);

class ServiceRequest {
  final String id;
  final String customerId;
  final String mechanicId;
  final String serviceType;
  final String? description;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final int? budgetKobo;
  final int? quotedPriceKobo;
  final RequestStatus status;
  final PaymentStatus paymentStatus;
  final DateTime respondBy;
  final int? etaSeconds;
  final int? distanceMeters;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? cancelReason;

  const ServiceRequest({
    required this.id,
    required this.customerId,
    required this.mechanicId,
    required this.serviceType,
    this.description,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    this.budgetKobo,
    this.quotedPriceKobo,
    required this.status,
    required this.paymentStatus,
    required this.respondBy,
    this.etaSeconds,
    this.distanceMeters,
    required this.createdAt,
    this.completedAt,
    this.cancelReason,
  });

  LatLng get pickup => LatLng(pickupLat, pickupLng);

  bool get isActive =>
      status == RequestStatus.accepted ||
      status == RequestStatus.enRoute ||
      status == RequestStatus.arrived ||
      status == RequestStatus.inProgress ||
      (status == RequestStatus.requested && respondBy.isAfter(DateTime.now()));

  factory ServiceRequest.fromMap(Map<String, dynamic> m) => ServiceRequest(
        id: m['id'] as String,
        customerId: m['customer_id'] as String,
        mechanicId: m['mechanic_id'] as String,
        serviceType: (m['service_type'] as String?) ?? 'General repair',
        description: m['description'] as String?,
        pickupAddress: (m['pickup_address'] as String?) ?? '',
        pickupLat: _d(m['pickup_lat']),
        pickupLng: _d(m['pickup_lng']),
        budgetKobo: _in(m['budget_kobo']),
        quotedPriceKobo: _in(m['quoted_price_kobo']),
        status: requestStatusFromDb(m['status'] as String),
        paymentStatus: paymentStatusFromDb(m['payment_status'] as String?),
        respondBy: _t(m['respond_by']),
        etaSeconds: _in(m['eta_seconds']),
        distanceMeters: _in(m['distance_m']),
        createdAt: _t(m['created_at']),
        completedAt: _tn(m['completed_at']),
        cancelReason: m['cancel_reason'] as String?,
      );

  ServiceRequest copyWith({
    RequestStatus? status,
    PaymentStatus? paymentStatus,
    int? quotedPriceKobo,
    int? etaSeconds,
    bool clearEta = false,
    int? distanceMeters,
    DateTime? completedAt,
    String? cancelReason,
  }) =>
      ServiceRequest(
        id: id,
        customerId: customerId,
        mechanicId: mechanicId,
        serviceType: serviceType,
        description: description,
        pickupAddress: pickupAddress,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        budgetKobo: budgetKobo,
        quotedPriceKobo: quotedPriceKobo ?? this.quotedPriceKobo,
        status: status ?? this.status,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        respondBy: respondBy,
        etaSeconds: clearEta ? null : (etaSeconds ?? this.etaSeconds),
        distanceMeters: clearEta ? null : (distanceMeters ?? this.distanceMeters),
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
        cancelReason: cancelReason ?? this.cancelReason,
      );
}

class Counterpart {
  final String name;
  final String? phone;
  const Counterpart({required this.name, this.phone});
}

class MechanicPoint {
  final double lat;
  final double lng;
  final DateTime? updatedAt;
  const MechanicPoint({required this.lat, required this.lng, this.updatedAt});
  LatLng get latLng => LatLng(lat, lng);
}

class EtaResult {
  final int? seconds;
  final int? meters;
  final List<LatLng>? route;
  final MechanicPoint? mechanic;
  const EtaResult({this.seconds, this.meters, this.route, this.mechanic});
}

class WalletSummary {
  final int availableKobo;
  final int inEscrowKobo; // money I paid that's held
  final int incomingKobo; // money held for me (mechanic)
  final bool allowTestTopups;
  const WalletSummary({required this.availableKobo, required this.inEscrowKobo, required this.incomingKobo, required this.allowTestTopups});

  factory WalletSummary.fromMap(Map<String, dynamic> m) => WalletSummary(
        availableKobo: _i(m['available_kobo']),
        inEscrowKobo: _i(m['in_escrow_kobo']),
        incomingKobo: _i(m['incoming_kobo']),
        allowTestTopups: (m['allow_test_topups'] as bool?) ?? false,
      );
}

class WalletTxn {
  final String id;
  final String kind;
  final int amountKobo;
  final String? description;
  final DateTime createdAt;
  const WalletTxn({required this.id, required this.kind, required this.amountKobo, this.description, required this.createdAt});

  factory WalletTxn.fromMap(Map<String, dynamic> m) => WalletTxn(
        id: m['id'] as String,
        kind: m['kind'] as String,
        amountKobo: _i(m['amount_kobo']),
        description: m['description'] as String?,
        createdAt: _t(m['created_at']),
      );
}

class Bank {
  final String name;
  final String code;
  const Bank(this.name, this.code);
}

class PayoutAccount {
  final String bankName;
  final String bankCode;
  final String accountNumber;
  final String? accountName;
  const PayoutAccount({required this.bankName, required this.bankCode, required this.accountNumber, this.accountName});
}

class RecyclingRate {
  final String itemType;
  final String label;
  final String unit;
  final int rateKobo;
  final double co2Kg;
  final String? description;
  const RecyclingRate({required this.itemType, required this.label, required this.unit, required this.rateKobo, required this.co2Kg, this.description});

  String get unitLabel => switch (unit) { 'kg' => 'kg', 'litre' => 'litres', _ => 'items' };

  /// "1 item", "2 items", "1 litre", "3.5 kg".
  String unitFor(double qty) => switch (unit) {
        'kg' => 'kg',
        'litre' => qty == 1 ? 'litre' : 'litres',
        _ => qty == 1 ? 'item' : 'items',
      };

  factory RecyclingRate.fromMap(Map<String, dynamic> m) => RecyclingRate(
        itemType: m['item_type'] as String,
        label: m['label'] as String,
        unit: m['unit'] as String,
        rateKobo: _i(m['rate_kobo']),
        co2Kg: (m['co2_kg'] as num).toDouble(),
        description: m['description'] as String?,
      );
}

class RecyclingCentre {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final List<String> accepts;
  final String? hours;
  const RecyclingCentre({required this.id, required this.name, required this.address, required this.lat, required this.lng, required this.accepts, this.hours});

  factory RecyclingCentre.fromMap(Map<String, dynamic> m) => RecyclingCentre(
        id: m['id'] as String,
        name: m['name'] as String,
        address: m['address'] as String,
        lat: _d(m['lat']),
        lng: _d(m['lng']),
        accepts: ((m['accepts'] as List?) ?? const []).map((e) => e.toString()).toList(),
        hours: m['hours'] as String?,
      );
}

class RecyclingRequest {
  final String id;
  final String itemType;
  final double quantity;
  final String method;
  final String? pickupAddress;
  final String? centreName;
  final DateTime? preferredDate;
  final int estimatedValueKobo;
  final double estimatedCo2Kg;
  final String status;
  final DateTime createdAt;
  const RecyclingRequest({
    required this.id,
    required this.itemType,
    required this.quantity,
    required this.method,
    this.pickupAddress,
    this.centreName,
    this.preferredDate,
    required this.estimatedValueKobo,
    required this.estimatedCo2Kg,
    required this.status,
    required this.createdAt,
  });

  factory RecyclingRequest.fromMap(Map<String, dynamic> m) => RecyclingRequest(
        id: m['id'] as String,
        itemType: m['item_type'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        method: (m['method'] as String?) ?? 'pickup',
        pickupAddress: m['pickup_address'] as String?,
        centreName: (m['recycling_centres'] as Map?)?['name'] as String?,
        preferredDate: m['preferred_date'] == null ? null : DateTime.tryParse(m['preferred_date'] as String),
        estimatedValueKobo: _i(m['estimated_value_kobo']),
        estimatedCo2Kg: (m['estimated_co2_kg'] as num?)?.toDouble() ?? 0,
        status: m['status'] as String,
        createdAt: _t(m['created_at']),
      );
}

class RecyclingImpact {
  final double co2Kg;
  final int paidKobo;
  final int items;
  const RecyclingImpact({required this.co2Kg, required this.paidKobo, required this.items});
}

class LearnMessage {
  final String role; // user | assistant
  final String content;
  final DateTime createdAt;
  const LearnMessage({required this.role, required this.content, required this.createdAt});

  bool get fromUser => role == 'user';
}
