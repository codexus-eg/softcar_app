import 'package:flutter/foundation.dart';

import '../models/shuttle.dart';
import 'passenger_api.dart';

/// Live-only shuttle catalogue and booking client. Every trip and every
/// reservation comes from the production backend — there is no offline
/// seed or demo data.
class ShuttleService extends ChangeNotifier {
  /// Sentinel fleet-filter value: the merged "Standard · 14/28" fleet (the
  /// 14-seat SoftCar-Fit + 28-seat SoftCar-Go together). `comfort` is reused
  /// as a compact sentinel because the passenger app only ever filters
  /// "Luxury · 3" vs the standard 14+28 fleet.
  static const ShuttleClass standardFleet = ShuttleClass.comfort;

  List<ShuttleTrip> _trips = const [];
  List<ReservationTier> _tiers = const [];
  bool _loading = false;
  Object? _error;
  ShuttleClass? _fleetFilter;

  List<ShuttleTrip> get trips => _trips;
  List<ReservationTier> get tiers => _tiers;
  bool get loading => _loading;
  Object? get error => _error;
  bool get hasTrips => _trips.isNotEmpty;

  /// Whether a fleet filter was set anywhere (home pill → search). null = All.
  ShuttleClass? get fleetFilter => _fleetFilter;

  void setFleetFilter(ShuttleClass? filter) {
    if (_fleetFilter == filter) return;
    _fleetFilter = filter;
    notifyListeners();
  }

  /// Fetches the live upcoming-trips catalogue and a refresh of seat
  /// availability. Returns true when a logged-in session exists.
  Future<bool> syncLive() async {
    return searchTrips();
  }

  /// Loads the active reserve tiers from the backend into [_tiers].
  /// Failures are swallowed so a tiers outage never blocks booking.
  Future<void> loadTiers() async {
    if (!passengerApi.isLoggedIn) return;
    try {
      final rows = await passengerApi.getTiers();
      _tiers = rows.whereType<Map>().map((e) {
        return ReservationTier.fromJson(Map<String, dynamic>.from(e));
      }).toList();
      notifyListeners();
    } catch (_) {}
  }

  /// Reserve tiers that apply to [trip]: trip-scoped tiers whose id matches
  /// the trip's canonical group (recurrence group or raw id, plus any return
  /// leg ids for round trips), followed by general (trip-agnostic) tiers.
  /// The backend resolves a tier's `tripId` from `sourceTripId ||
  /// templateSourceTripId || id`, so matching on both the recurrence group
  /// and the concrete id keeps admin-assigned tiers surfacing.
  List<ReservationTier> tiersFor(ShuttleTrip trip) {
    final keys = <String>{
      if (trip.recurrenceGroupId != null &&
          trip.recurrenceGroupId!.isNotEmpty)
        trip.recurrenceGroupId!,
      trip.id,
      if (trip.returnTrip != null) ...[
        if (trip.returnTrip!.recurrenceGroupId != null &&
            trip.returnTrip!.recurrenceGroupId!.isNotEmpty)
          trip.returnTrip!.recurrenceGroupId!,
        trip.returnTrip!.id,
      ],
    };
    final matching = _tiers
        .where((t) => t.tripId != null && t.tripId!.isNotEmpty)
        .where((t) => keys.contains(t.tripId))
        .toList();
    final general = _tiers
        .where((t) => t.tripId == null || t.tripId!.isEmpty)
        .toList();
    return [...matching, ...general];
  }

  /// Searches live trips by from/to text, or returns all upcoming trips when
  /// both are empty. Returns true when a logged-in session exists.
  Future<bool> searchTrips({
    String? from,
    String? to,
    String? date,
    double? lat,
    double? lng,
  }) async {
    if (_loading) return _trips.isNotEmpty;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (!passengerApi.isLoggedIn) throw StateError('Not signed in');
      final rows = await passengerApi.getTrips(
        from: from,
        to: to,
        date: date,
        lat: lat,
        lng: lng,
      );
      _trips = rows.whereType<Map>().map((e) {
        return ShuttleTrip.fromJson(Map<String, dynamic>.from(e));
      }).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Trips on a given calendar day.
  List<ShuttleTrip> tripsOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return _trips
        .where((t) =>
            t.startTime.year == d.year &&
            t.startTime.month == d.month &&
            t.startTime.day == d.day)
        .toList();
  }

  ShuttleTrip? byTripId(String id) {
    for (final t in _trips) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Books real seats on a live trip. Returns the created ticket (reservation).
  /// [paymentMethod] is one of CASH | WALLET | CARD | CASHLESS_CORPORATE.
  /// For round-trip trips pass the return leg ids to create the pair,
  /// and [tierId] to charge both legs against a reserve tier package.
  Future<Ticket> book({
    required ShuttleTrip trip,
    required String pickupPointId,
    required String dropoffPointId,
    required int seats,
    required String seatNumbers,
    String paymentMethod = 'CASH',
    String? returnPickupPointId,
    String? returnDropoffPointId,
    String? roundTripReturnTripId,
    String? tierId,
  }) async {
    final wantRoundTrip = trip.tripType.isRoundTrip;
    final json = await passengerApi.createReservation(
      tripId: trip.id,
      pickupPointId: pickupPointId,
      dropoffPointId: dropoffPointId,
      seats: seats,
      seatNumbers: seatNumbers,
      paymentMethod: paymentMethod,
      clientRequestId: 'sc-${DateTime.now().microsecondsSinceEpoch}',
      roundTrip: wantRoundTrip,
      roundTripReturnTripId:
          wantRoundTrip ? (roundTripReturnTripId ?? trip.returnTrip?.id) : null,
      returnPickupPointId: wantRoundTrip ? returnPickupPointId : null,
      returnDropoffPointId: wantRoundTrip ? returnDropoffPointId : null,
      tierId: tierId,
    );
    return Ticket.fromJson(Map<String, dynamic>.from(json));
  }

  /// Books a recurring plan on a live trip. Returns the backend response map
  /// (the recurring plan + the created reservations). When [returnTrip] is
  /// provided the return leg is scheduled with the same tier/date range as
  /// a best-effort second recurring plan, so a round trip's both legs are
  /// covered by the tier.
  Future<Map<String, dynamic>> bookRecurring({
    required ShuttleTrip trip,
    required String pickupPointId,
    required String dropoffPointId,
    required int seats,
    required String seatNumbers,
    required DateTime startDate,
    required DateTime endDate,
    required List<int> weekdays,
    String paymentMethod = 'CASH',
    ReservationTier? tier,
    ShuttleTrip? returnTrip,
    String? returnPickupPointId,
    String? returnDropoffPointId,
  }) async {
    final primary = await passengerApi.createRecurringReservation(
      tripId: trip.id,
      pickupPointId: pickupPointId,
      dropoffPointId: dropoffPointId,
      startDate: _isoDate(startDate),
      endDate: _isoDate(endDate),
      weekdays: weekdays,
      seats: seats,
      seatNumbers: seatNumbers,
      paymentMethod: paymentMethod,
      tierId: tier?.id,
      clientRequestId: 'scr-${DateTime.now().microsecondsSinceEpoch}',
    );
    final ret = returnTrip ?? trip.returnTrip;
    if (ret != null) {
      try {
        final recurring = primary['recurringReservation'];
        final primaryPlanId = recurring is Map
            ? recurring['id']?.toString()
            : null;
        await passengerApi.createRecurringReservation(
          tripId: ret.id,
          pickupPointId:
              returnPickupPointId ??
              (ret.pickupStops.isNotEmpty ? ret.pickupStops.first.id : ''),
          dropoffPointId:
              returnDropoffPointId ??
              (ret.dropoffStops.isNotEmpty ? ret.dropoffStops.first.id : ''),
          startDate: _isoDate(startDate),
          endDate: _isoDate(endDate),
          weekdays: weekdays,
          seats: seats,
          seatNumbers: seatNumbers,
          paymentMethod: paymentMethod,
          tierId: tier?.id,
          clientRequestId: 'scr-${DateTime.now().microsecondsSinceEpoch}',
          includedPrimaryPlanId: primaryPlanId,
        );
      } catch (_) {
        // A tier round trip must never be reported as complete with only one
        // direction. Surface the failure so support can resolve the primary
        // plan instead of silently leaving an incomplete package.
        if (tier != null) rethrow;
      }
    }
    return primary;
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
