import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/utils/egypt_time.dart';
import 'user_profile.dart';

/// The three SoftCar shuttle vehicles. Real seat capacities:
/// SoftCar-Go · 28 coach, SoftCar-Fit · 14 mid-size shuttle, SoftCar-Luxury · 3
/// private sedan. Booking still sends the legacy service class codes.
enum ShuttleClass {
  fit(
    'SoftCar-Go · 28',
    'The everyday 28-seat SoftCar-Go coach for your regular rides',
    28,
  ),
  comfort(
    'SoftCar-Fit · 14',
    'The 14-seat SoftCar-Fit mid-size shuttle for quick, comfortable trips',
    14,
  ),
  luxury(
    'SoftCar-Luxury · 3',
    'A premium private ride in a 3-seat SoftCar-Luxury sedan',
    3,
  );

  const ShuttleClass(this.name, this.tagline, this.seats);

  final String name;
  final String tagline;
  final int seats;

  /// Maps the live backend `serviceClassCode` to the SoftCar fleet. Both the
  /// legacy codes (still returned by live trips) and the new fleet codes
  /// (`SOFTCAR_GO_28` / `SOFTCAR_GO_14` / `SOFTCAR_LUXURY`) are accepted.
  static ShuttleClass? fromApi(String? code) {
    switch (code?.toUpperCase()) {
      case 'ECONOMY_COASTER':
      case 'SOFTCAR_GO_28':
        return ShuttleClass.fit;
      case 'STANDARD_HIACE':
      case 'SOFTCAR_GO_14':
        return ShuttleClass.comfort;
      case 'LUXURY_SEDAN':
      case 'LUXURY_VIP':
      case 'SOFTCAR_LUXURY':
        return ShuttleClass.luxury;
      default:
        return null;
    }
  }

  String get apiCode => switch (this) {
    ShuttleClass.fit => 'ECONOMY_COASTER',
    ShuttleClass.comfort => 'STANDARD_HIACE',
    ShuttleClass.luxury => 'LUXURY_SEDAN',
  };

  IconData get icon => switch (this) {
    ShuttleClass.fit => Icons.airport_shuttle_rounded,
    ShuttleClass.comfort => Icons.airport_shuttle_outlined,
    ShuttleClass.luxury => Icons.workspace_premium_rounded,
  };

  Color get color => switch (this) {
    ShuttleClass.fit => const Color(0xFF2563EB),
    ShuttleClass.comfort => const Color(0xFF0D9488),
    ShuttleClass.luxury => const Color(0xFF7C3AED),
  };

  /// How many seats sit to the left and right of the aisle per row.
  /// [SeatRow.left] and [SeatRow.right] hold the absolute seat numbers.
  /// A coach minibus and sedan each get a distinctive floor plan instead
  /// of one generic grid — deeper than the copycat "square blocks".
  List<SeatRow> get layout => switch (this) {
    // Coach: 7 rows of 4 across a central aisle (2+2) = 28.
    ShuttleClass.fit => List.generate(7, (r) {
      final base = r * 4;
      return SeatRow(
        number: r + 1,
        left: [base + 1, base + 2],
        right: [base + 3, base + 4],
      );
    }),
    // Minibus: co-driver front seat, three 2+2 rows and a rear bench.
    ShuttleClass.comfort => [
      SeatRow(number: 1, left: [1], right: const []),
      SeatRow(number: 2, left: [2, 3], right: [4, 5]),
      SeatRow(number: 3, left: [6, 7], right: [8, 9]),
      SeatRow(number: 4, left: [10, 11], right: [12, 13]),
      SeatRow(number: 5, left: [14], right: const []),
    ],
    // Sedan: one front co-pilot seat behind the wheel + rear bench.
    ShuttleClass.luxury => [
      SeatRow(number: 1, left: [1], right: const []),
      SeatRow(number: 2, left: [2], right: [3]),
    ],
  };

  int get maxDefiniteTaken =>
      layout.expand((r) => [...r.left, ...r.right]).length;
}

/// One row of a vehicle floor plan. Seats are numbered from the front.
class SeatRow {
  final int number;
  final List<int> left;
  final List<int> right;

  const SeatRow({
    required this.number,
    required this.left,
    required this.right,
  });

  List<int> get all => [...left, ...right];
}

/// How a trip is sold. The backend gates booking by this:
/// one-time trips book a single reservation, recurring trips book a plan
/// (`POST /api/mobile/recurring-reservations`) and round-trip trips book an
/// outbound + return pair in a single reservation.
enum TripType {
  oneTime('ONE_TIME'),
  recurring('RECURRING'),
  roundTrip('ROUND_TRIP'),
  template('TEMPLATE');

  const TripType(this.apiCode);

  final String apiCode;

  static TripType fromApi(Object? v) {
    switch (v?.toString().toUpperCase()) {
      case 'RECURRING':
        return TripType.recurring;
      case 'ROUND_TRIP':
        return TripType.roundTrip;
      case 'TEMPLATE':
        return TripType.template;
      default:
        return TripType.oneTime;
    }
  }

  bool get isRecurring => this == TripType.recurring;
  bool get isRoundTrip => this == TripType.roundTrip;
}

/// One concrete occurrence of a recurring trip, as listed under the
/// representative trip's `occurrences` array by `GET /api/mobile/trips`.
class ShuttleOccurrence {
  final String id;
  final DateTime startTime;
  final DateTime? estimatedEndTime;
  final int seatsRemaining;
  final int totalSeats;
  final TripType tripType;

  const ShuttleOccurrence({
    required this.id,
    required this.startTime,
    this.estimatedEndTime,
    required this.seatsRemaining,
    required this.totalSeats,
    this.tripType = TripType.oneTime,
  });

  factory ShuttleOccurrence.fromJson(Map<String, dynamic> json) =>
      ShuttleOccurrence(
        id: json['id']?.toString() ?? '',
        startTime:
            DateTime.tryParse(json['startTime']?.toString() ?? '') ??
            DateTime.now(),
        estimatedEndTime: DateTime.tryParse(
          json['estimatedEndTime']?.toString() ?? '',
        ),
        seatsRemaining: _Num.toInt(json['seatsRemaining']),
        totalSeats: _Num.toInt(json['totalSeats']),
        tripType: TripType.fromApi(json['tripType']),
      );
}

/// One pickup point / stop on a trip.
class ShuttleStop {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final int stopOrder;
  final String pointType;

  /// Minutes after the trip's scheduled start when the vehicle is expected
  /// at this stop (set by the admin in the trip form). Zero when unknown.
  final int arrivalOffsetMin;

  const ShuttleStop({
    required this.id,
    required this.name,
    this.address = '',
    this.latitude = 0,
    this.longitude = 0,
    this.stopOrder = 0,
    this.pointType = 'PICKUP',
    this.arrivalOffsetMin = 0,
  });

  factory ShuttleStop.fromJson(Map<String, dynamic> json) => ShuttleStop(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? json['address']?.toString() ?? '',
    address: json['address']?.toString() ?? '',
    latitude: _num(json['latitude']),
    longitude: _num(json['longitude']),
    stopOrder: _int(json['stopOrder']),
    pointType: json['pointType']?.toString().toUpperCase() ?? 'PICKUP',
    arrivalOffsetMin: _int(json['arrivalOffsetMin']),
  );

  bool get isDropoff => pointType == 'DROPOFF';

  /// Expected arrival at this stop relative to the trip's scheduled start.
  /// Falls back to [tripStart] when the admin did not set an offset.
  DateTime arrivalAt(DateTime tripStart) =>
      tripStart.add(Duration(minutes: arrivalOffsetMin));

  static int _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
}

/// Small numeric helpers shared by model serialisers in this file.
class _Num {
  static int toInt(Object? v, {int fallback = 0}) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;
}

/// The driver assigned to a trip (from the backend's `driverProfile`).
class TripDriver {
  final String? name;
  final String? phone;

  /// Backend user id of the driver — enables in-app Soft-Calls
  /// (parsed from the embedded `user.id` when present).
  final String? userId;
  final String? carModel;
  final String? carPlateNumber;
  final String? photoUrl;
  final String? carPhotoUrl;
  final double? currentLat;
  final double? currentLng;
  final double? currentHeading;
  final double? currentSpeedKph;
  final DateTime? lastLocationAt;

  const TripDriver({
    this.name,
    this.phone,
    this.userId,
    this.carModel,
    this.carPlateNumber,
    this.photoUrl,
    this.carPhotoUrl,
    this.currentLat,
    this.currentLng,
    this.currentHeading,
    this.currentSpeedKph,
    this.lastLocationAt,
  });

  bool get isAssigned =>
      (name != null && name!.trim().isNotEmpty) ||
      (phone != null && phone!.trim().isNotEmpty);

  bool hasFreshLocation(
    DateTime now, {
    Duration maxAge = const Duration(minutes: 3),
  }) {
    final updatedAt = lastLocationAt;
    return currentLat != null &&
        currentLng != null &&
        updatedAt != null &&
        now.difference(updatedAt).abs() <= maxAge;
  }

  LatLng? livePosition(DateTime now) =>
      hasFreshLocation(now) ? LatLng(currentLat!, currentLng!) : null;

  factory TripDriver.fromJson(Map<String, dynamic> json) {
    final user =
        json['user'] is Map
            ? Map<String, dynamic>.from(json['user'])
            : <String, dynamic>{};
    return TripDriver(
      name: json['fullName']?.toString() ?? user['name']?.toString(),
      phone: json['phone']?.toString() ?? user['phone']?.toString(),
      userId: (json['userId'] ?? user['id'] ?? json['driverId'])?.toString(),
      carModel: json['carModel']?.toString(),
      carPlateNumber: json['carPlateNumber']?.toString(),
      photoUrl: json['photoUrl']?.toString() ?? user['image']?.toString(),
      carPhotoUrl: json['carPhotoUrl']?.toString(),
      currentLat: _nullableDouble(json['currentLat']),
      currentLng: _nullableDouble(json['currentLng']),
      currentHeading: _nullableDouble(json['currentHeading']),
      currentSpeedKph: _nullableDouble(json['currentSpeedKph']),
      lastLocationAt: DateTime.tryParse(
        json['lastLocationAt']?.toString() ?? '',
      ),
    );
  }

  static double? _nullableDouble(Object? value) {
    if (value == null) return null;
    return value is num ? value.toDouble() : double.tryParse(value.toString());
  }
}

/// A live trip from `GET /api/mobile/trips`, mapped to what the UI needs.
class ShuttleTrip {
  final String id;
  final String title;
  final String mainDestination;
  final DateTime startTime;
  final double price;
  final int totalSeats;
  final int seatsRemaining;
  final ShuttleClass? vehicle;
  final List<ShuttleStop> pickupPoints;
  final TripDriver? driver;
  final TripType tripType;
  final ShuttleTrip? returnTrip;
  final double? roundTripPrice;
  final String? recurrenceGroupId;
  final int occurrenceCount;
  final List<ShuttleOccurrence> occurrences;

  /// Physical seats already reserved on this trip mapped to the gender of the
  /// passenger who holds them (`null` when the backend doesn't report it).
  /// Keys are 1-based seat numbers from each reservation's `seatNumbers`.
  final Map<int, UserGender?> reservedSeats;

  const ShuttleTrip({
    required this.id,
    required this.title,
    required this.mainDestination,
    required this.startTime,
    required this.price,
    required this.totalSeats,
    required this.seatsRemaining,
    required this.vehicle,
    required this.pickupPoints,
    this.driver,
    this.tripType = TripType.oneTime,
    this.returnTrip,
    this.roundTripPrice,
    this.recurrenceGroupId,
    this.occurrenceCount = 1,
    this.occurrences = const [],
    this.reservedSeats = const {},
  });

  factory ShuttleTrip.fromJson(Map<String, dynamic> json) {
    final stops =
        (json['pickupPoints'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ShuttleStop.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    final start =
        DateTime.tryParse(json['startTime']?.toString() ?? '') ??
        DateTime.now();
    final total = _int(json['totalSeats']);
    final driver =
        json['driverProfile'] is Map
            ? TripDriver.fromJson(
              Map<String, dynamic>.from(json['driverProfile']),
            )
            : null;
    final returnJson = json['returnTrip'];
    final occurrences =
        (json['occurrences'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (e) => ShuttleOccurrence.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList();

    final reserved = <int, UserGender?>{};
    for (final raw in (json['reservations'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final user = raw['user'] is Map ? raw['user'] as Map : null;
      final gender = UserGender.fromCode(
        user?['gender'] ?? raw['gender'],
      );
      for (final part in (raw['seatNumbers']?.toString() ?? '').split(',')) {
        final m = RegExp(r'\d+').firstMatch(part);
        final n = m == null ? null : int.parse(m.group(0)!);
        if (n != null && !reserved.containsKey(n)) {
          reserved[n] = gender;
        }
      }
    }

    return ShuttleTrip(
      id: json['id'].toString(),
      title:
          json['title']?.toString() ??
          json['mainDestination']?.toString() ??
          'Shuttle ride',
      mainDestination:
          json['mainDestination']?.toString() ??
          json['title']?.toString() ??
          '',
      startTime: start,
      price: _num(json['basePrice']),
      totalSeats: total,
      seatsRemaining: _int(json['seatsRemaining'], fallback: total),
      vehicle: ShuttleClass.fromApi(json['serviceClassCode']?.toString()),
      pickupPoints: stops,
      driver: driver,
      tripType: TripType.fromApi(json['tripType']),
      returnTrip:
          returnJson is Map
              ? ShuttleTrip.fromJson(Map<String, dynamic>.from(returnJson))
              : null,
      roundTripPrice:
          json['roundTripPrice'] is num
              ? (json['roundTripPrice'] as num).toDouble()
              : null,
      recurrenceGroupId: json['recurrenceGroupId']?.toString(),
      occurrenceCount: _int(json['occurrenceCount'], fallback: 1),
      occurrences: occurrences,
      reservedSeats: reserved,
    );
  }

  String get fromName =>
      pickupPoints.isNotEmpty ? pickupPoints.first.name : 'Departure';
  String get toName =>
      pickupPoints.isNotEmpty ? pickupPoints.last.name : mainDestination;

  /// Pickup-capable stops (pointType PICKUP). Falls back to all stops when
  /// the payload does not carry point types.
  List<ShuttleStop> get pickupStops {
    final picks = pickupPoints.where((s) => !s.isDropoff).toList();
    return picks.isNotEmpty ? picks : pickupPoints;
  }

  /// Drop-off-capable stops (pointType DROPOFF). Falls back to all stops
  /// when the payload does not carry point types.
  List<ShuttleStop> get dropoffStops {
    final drops = pickupPoints.where((s) => s.isDropoff).toList();
    return drops.isNotEmpty ? drops : pickupPoints;
  }

  ShuttleStop? get origin => pickupStops.isNotEmpty ? pickupStops.first : null;
  ShuttleStop? get destination =>
      dropoffStops.length > 1 ? dropoffStops.last : null;

  double get fareForOne => price;

  /// Net price charged per passenger for this booking. Round-trip trips bill
  /// their `roundTripPrice` (outbound + return together); everything else
  /// uses the regular per-seat fare.
  double get fareForBooking =>
      tripType.isRoundTrip && (roundTripPrice ?? 0) > 0
          ? roundTripPrice!
          : price;

  static int _int(Object? v, {int fallback = 0}) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;
  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
}

/// A reserve tier / package from `GET /api/mobile/tiers`. General tiers have
/// an empty [tripId]; trip-scoped tiers carry the canonical trip id the
/// backend resolves from `sourceTripId || templateSourceTripId || id`.
class ReservationTier {
  final String id;
  final String name;
  final String code;
  final String description;
  final String? imageUrl;
  final int gridSpanX;
  final int gridSpanY;
  final int durationDays;
  final List<int> excludedWeekdays;
  final double originalPrice;
  final double packagePrice;
  final int minimumSeats;
  final int maximumSeats;
  final List<String> paymentMethods;
  final String cancellationPolicy;
  final String? tripId;
  final bool isRecommended;
  final bool isActive;
  final double? discountPercent;
  final double? walletBonusAmount;
  final bool priorityBooking;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int reservationCount;
  final List<String> benefits;

  const ReservationTier({
    required this.id,
    required this.name,
    required this.code,
    this.description = '',
    this.imageUrl,
    this.gridSpanX = 4,
    this.gridSpanY = 4,
    this.durationDays = 0,
    this.excludedWeekdays = const [],
    this.originalPrice = 0,
    this.packagePrice = 0,
    this.minimumSeats = 1,
    this.maximumSeats = 0,
    this.paymentMethods = const [],
    this.cancellationPolicy = '',
    this.tripId,
    this.isRecommended = false,
    this.isActive = true,
    this.discountPercent,
    this.walletBonusAmount,
    this.priorityBooking = false,
    this.validFrom,
    this.validUntil,
    this.reservationCount = 0,
    this.benefits = const [],
  });

  factory ReservationTier.fromJson(Map<String, dynamic> json) {
    List<int> weekdays = const [];
    final wd = json['excludedWeekdays'];
    if (wd is List) {
      weekdays = wd.whereType<num>().map((e) => e.toInt()).toList();
    }
    return ReservationTier(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString(),
      gridSpanX: ((json['gridSpanX'] is num)
              ? (json['gridSpanX'] as num).toInt()
              : 4)
          .clamp(1, 4),
      gridSpanY: ((json['gridSpanY'] is num)
              ? (json['gridSpanY'] as num).toInt()
              : 4)
          .clamp(1, 6),
      durationDays: _num(json['durationDays']).toInt(),
      excludedWeekdays: weekdays,
      originalPrice: _num(json['originalPrice']),
      packagePrice: _num(json['packagePrice']),
      minimumSeats: _num(json['minimumSeats']).toInt(),
      maximumSeats: _num(json['maximumSeats']).toInt(),
      paymentMethods:
          (json['paymentMethods'] as List? ?? const [])
              .map((e) => e.toString())
              .toList(),
      cancellationPolicy: json['cancellationPolicy']?.toString() ?? '',
      tripId: json['tripId']?.toString(),
      isRecommended: json['isRecommended'] == true,
      isActive: json['isActive'] != false,
      discountPercent:
          json['discountPercent'] is num
              ? (json['discountPercent'] as num).toDouble()
              : null,
      walletBonusAmount:
          json['walletBonusAmount'] is num
              ? (json['walletBonusAmount'] as num).toDouble()
              : null,
      priorityBooking: json['priorityBooking'] == true,
      validFrom: DateTime.tryParse(json['validFrom']?.toString() ?? ''),
      validUntil: DateTime.tryParse(json['validUntil']?.toString() ?? ''),
      reservationCount: _num(json['reservationCount']).toInt(),
      benefits: _parseBenefits(json['benefitsJson']),
    );
  }

  /// Parses a tier's `benefitsJson` into a displayable list of benefit
  /// strings. Accepts either a JSON-array string, a stringified list, a
  /// plain list of strings, or a map — anything else yields an empty list.
  static List<String> _parseBenefits(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is! String || raw.trim().isEmpty) return const [];
    final text = raw.trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (decoded is Map) {
        return decoded.values
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [text];
  }

  double get savings =>
      originalPrice > packagePrice ? originalPrice - packagePrice : 0;

  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
}

/// Arguments passed to the seat-selection screen: the trip to book plus an
/// optional reserve tier that should be pre-selected (e.g. when a rider taps
/// "Use this tier" on the trip-details screen).
class SeatSelectionArgs {
  final ShuttleTrip trip;
  final ReservationTier? tier;

  /// Stop ids suggested by an upstream picker (the Where-to search) so the
  /// board/alight dropdowns open on the chosen stops instead of stop #1.
  final String? preferredPickupPointId;
  final String? preferredDropoffPointId;

  const SeatSelectionArgs({
    required this.trip,
    this.tier,
    this.preferredPickupPointId,
    this.preferredDropoffPointId,
  });
}

/// A booked reservation (ticket) from `GET /api/mobile/reservations`.
class Ticket {
  final String id;
  final String ticketCode;
  final String from;
  final String to;
  final DateTime departure;
  final double subtotal;
  final double tax;
  final double total;
  final int seats;
  final String seatNumbers;
  final String paymentStatus;
  final String status;
  final DateTime createdAt;
  final ShuttleClass? vehicleClass;
  final String tripTitle;
  final String paymentMethod;

  /// The reservation's canonical trip id (from the nested `trip.id`), used
  /// to group tickets of the same journey together.
  final String tripId;

  /// Whether the passenger already reviewed this completed reservation.
  final bool reviewed;

  /// The trip's ordered stops (with lat/lng when the backend sends them) —
  /// used to draw the live route and estimate the minibus position.
  final List<ShuttleStop> pickupPoints;

  /// The driver assigned to the reservation's trip, when provided.
  final TripDriver? driver;

  /// The backend's estimated arrival time for the trip, when provided.
  final DateTime? estimatedEndTime;

  /// How the trip is sold (`ONE_TIME` / `ROUND_TRIP` / `RECURRING`), read
  /// from the nested `trip.tripType` object.
  final String tripType;

  /// Which leg of a round-trip reservation this ticket is
  /// (`OUTBOUND` / `RETURN`, empty for non round-trip tickets).
  final String roundTripLeg;

  /// Id linking an outbound and return leg of the same round-trip booking,
  /// when the backend sends it on the reservation.
  final String roundTripGroupId;

  /// Id of the recurring plan this reservation belongs to, when the ticket
  /// is one occurrence of a recurring booking.
  final String recurringReservationId;

  /// The actual date this reservation is served, when it differs from the
  /// trip template's default departure day (always set for recurring and
  /// one-time concrete reservations).
  final DateTime? serviceDate;

  const Ticket({
    required this.id,
    required this.ticketCode,
    required this.from,
    required this.to,
    required this.departure,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.seats,
    required this.seatNumbers,
    required this.paymentStatus,
    required this.status,
    required this.createdAt,
    this.vehicleClass,
    this.tripTitle = '',
    this.paymentMethod = 'CASH',
    this.tripId = '',
    this.reviewed = false,
    this.pickupPoints = const [],
    this.driver,
    this.estimatedEndTime,
    this.tripType = 'ONE_TIME',
    this.roundTripLeg = '',
    this.roundTripGroupId = '',
    this.recurringReservationId = '',
    this.serviceDate,
  });

  Ticket copyWith({String? paymentStatus, String? status}) {
    return Ticket(
      id: id,
      ticketCode: ticketCode,
      from: from,
      to: to,
      departure: departure,
      subtotal: subtotal,
      tax: tax,
      total: total,
      seats: seats,
      seatNumbers: seatNumbers,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status ?? this.status,
      createdAt: createdAt,
      vehicleClass: vehicleClass,
      tripTitle: tripTitle,
      paymentMethod: paymentMethod,
      tripId: tripId,
      reviewed: reviewed,
      pickupPoints: pickupPoints,
      driver: driver,
      estimatedEndTime: estimatedEndTime,
      tripType: tripType,
      roundTripLeg: roundTripLeg,
      roundTripGroupId: roundTripGroupId,
      recurringReservationId: recurringReservationId,
      serviceDate: serviceDate,
    );
  }

  factory Ticket.fromJson(Map<String, dynamic> json) {
    final trip =
        json['trip'] is Map
            ? Map<String, dynamic>.from(json['trip'])
            : <String, dynamic>{};
    final pickup =
        json['pickupPoint'] is Map
            ? Map<String, dynamic>.from(json['pickupPoint'])
            : <String, dynamic>{};
    final dropoff =
        json['dropoffPoint'] is Map
            ? Map<String, dynamic>.from(json['dropoffPoint'])
            : <String, dynamic>{};

    final stops =
        (trip['pickupPoints'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ShuttleStop.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
    final driver =
        trip['driverProfile'] is Map
            ? TripDriver.fromJson(
              Map<String, dynamic>.from(trip['driverProfile']),
            )
            : null;

    return Ticket(
      id: json['id']?.toString() ?? '',
      ticketCode: json['ticketCode']?.toString() ?? 'SCS-000000',
      from:
          pickup['name']?.toString() ??
          json['pickupLabel']?.toString() ??
          'Pickup',
      to:
          dropoff['name']?.toString() ??
          trip['mainDestination']?.toString() ??
          'Destination',
      departure:
          DateTime.tryParse(trip['startTime']?.toString() ?? '') ??
          DateTime.now(),
      subtotal: _num(json['subtotalPrice']),
      tax: _num(json['taxAmount']),
      total: _num(json['totalPrice']),
      seats: _int(json['seats'], fallback: 1),
      seatNumbers: json['seatNumbers']?.toString() ?? '',
      paymentStatus: json['paymentStatus']?.toString() ?? 'AUTHORIZED',
      status: json['status']?.toString() ?? 'RESERVED',
      createdAt:
          DateTime.tryParse(json['reservedAt']?.toString() ?? '') ??
          DateTime.now(),
      vehicleClass: ShuttleClass.fromApi(trip['serviceClassCode']?.toString()),
      tripTitle: trip['title']?.toString() ?? '',
      paymentMethod: json['paymentMethod']?.toString() ?? 'CASH',
      tripId: trip['id']?.toString() ?? '',
      reviewed:
          json['reviewed'] == true ||
          json['hasReview'] == true ||
          json['review'] is Map,
      pickupPoints: stops,
      driver: driver,
      estimatedEndTime: DateTime.tryParse(
        trip['estimatedEndTime']?.toString() ?? '',
      ),
      tripType: trip['tripType']?.toString() ?? 'ONE_TIME',
      roundTripLeg: json['roundTripLeg']?.toString() ?? '',
      roundTripGroupId: json['roundTripGroupId']?.toString() ?? '',
      recurringReservationId:
          json['recurringReservationId']?.toString() ?? '',
      serviceDate: DateTime.tryParse(json['serviceDate']?.toString() ?? ''),
    );
  }

  /// Stops that actually carry coordinates, in route order. These drive the
  /// live map polyline and the interpolated bus position.
  List<ShuttleStop> get liveStops =>
      pickupPoints.where((s) => s.latitude != 0 || s.longitude != 0).toList();

  /// Estimated arrival used for live tracking. Falls back to a two-hour
  /// ride when the backend does not send `estimatedEndTime`.
  DateTime get liveEndTime =>
      estimatedEndTime ?? departure.add(const Duration(hours: 2));

  bool get isUpcoming =>
      status == 'RESERVED' || status == 'BOARDED' || status == 'PENDING';

  /// True when the ticket is still an active (not yet started) reservation —
  /// the only state where the passenger can cancel or change the trip day.
  bool get isReserved => status == 'RESERVED';
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled =>
      status == 'CANCELLED' || status == 'CANCELED' || status == 'EXPIRED';

  /// True for a round-trip reservation: either the booked trip is marked
  /// ROUND_TRIP, or this is one of the outbound/return legs (the backend
  /// links them via `roundTripGroupId`).
  bool get isRoundTrip =>
      tripType == 'ROUND_TRIP' ||
      roundTripLeg.isNotEmpty ||
      roundTripGroupId.isNotEmpty;

  /// Whether this is the forward (outbound) leg of a round-trip booking.
  bool get isOutboundLeg => roundTripLeg == 'OUTBOUND';

  /// Whether this is the return leg of a round-trip booking.
  bool get isReturnLeg => roundTripLeg == 'RETURN';

  /// True for an occurrence of a recurring plan (or a recurring trip type).
  bool get isRecurring =>
      tripType == 'RECURRING' || recurringReservationId.isNotEmpty;

  /// English default for the trip-type label. The UI resolves the localized
  /// text through the `tripTypeLabelKey` / l10n keys instead of this getter.
  String get tripTypeLabel => switch (tripType) {
    'ROUND_TRIP' => 'Round trip',
    'RECURRING' => 'Recurring',
    _ => 'One-time',
  };

  /// Leg label for round-trip tickets: `Outbound` / `Return`, otherwise ''.
  String get legLabel => switch (roundTripLeg) {
    'OUTBOUND' => 'Outbound',
    'RETURN' => 'Return',
    _ => '',
  };

  /// Which l10n key best describes this ticket's type.
  String get tripTypeLabelKey => switch (tripType) {
    'ROUND_TRIP' => 'roundTrip',
    'RECURRING' => 'recurring',
    _ => 'oneTime',
  };

  /// The concrete calendar day the reservation runs on — prefers the
  /// backend's `serviceDate`, falling back to the trip's departure read in
  /// Egypt wall-clock time.
  DateTime get serviceDay {
    final sd = serviceDate;
    if (sd != null) return DateTime(sd.year, sd.month, sd.day);
    final eg = egDate(departure)!;
    return DateTime(eg.year, eg.month, eg.day);
  }

  String get statusLabel {
    if (isCancelled) return 'Cancelled';
    if (isCompleted) return 'Completed';
    return 'Upcoming';
  }

  static int _int(Object? v, {int fallback = 0}) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;
  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
}

/// Display colours keyed by the passenger's gender (pink / blue).
mixin GenderColor {
  static Color forGender(UserGender? gender, {Color? fallback}) =>
      gender == UserGender.female
          ? const Color(0xFFEC4899)
          : gender == UserGender.male
          ? const Color(0xFF3B82F6)
          : fallback ?? const Color(0xFF1F6FFF);
}
