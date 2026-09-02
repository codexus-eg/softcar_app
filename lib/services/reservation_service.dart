import 'package:flutter/foundation.dart';

import '../models/shuttle.dart';
import 'passenger_api.dart';

/// Live-only ticket store. Pulls the passenger's real reservations from the
/// backend (`GET /api/mobile/reservations`). There is no in-memory
/// reservation creation — every ticket shown is a real server record.
class ReservationService extends ChangeNotifier {
  List<Ticket> _tickets = const [];
  bool _loading = false;

  List<Ticket> get tickets => _tickets;
  bool get loading => _loading;

  Future<void> syncFromLive() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      if (!passengerApi.isLoggedIn) return;
      final rows = await passengerApi.getReservations();
      _tickets = rows.whereType<Map>().map((e) {
        return Ticket.fromJson(Map<String, dynamic>.from(e));
      }).toList()
        ..sort((a, b) => b.departure.compareTo(a.departure));
    } catch (_) {
      // Keep the current list if refresh fails.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Upcoming reservations, soonest first.
  List<Ticket> get upcoming => _tickets.where((t) => t.isUpcoming).toList()
    ..sort((a, b) => a.departure.compareTo(b.departure));

  /// Historical reservations (completed / cancelled), newest first.
  List<Ticket> get history =>
      _tickets.where((t) => !t.isUpcoming).toList()
        ..sort((a, b) => b.departure.compareTo(a.departure));

  Ticket? byId(String id) {
    for (final t in _tickets) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Refunded amount from the last successful [cancel] call, when the
  /// backend reported one — lets the UI confirm how much went back to the
  /// passenger's wallet.
  double? lastRefundedAmount;

  /// Cancels the passenger's own reservation on the live backend and re-syncs
  /// the ticket list. Returns an error message on failure, or null on success.
  /// On success, [lastRefundedAmount] carries the backend's reported refund.
  Future<String?> cancel(String id) async {
    try {
      final json = await passengerApi.cancelReservation(id);
      final refund = json['refundedAmount'];
      lastRefundedAmount =
          refund is num ? refund.toDouble() : double.tryParse('$refund');
      await syncFromLive();
      return null;
    } on PassengerApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not cancel the reservation right now.';
    }
  }

  /// Moves a RESERVED reservation to another SCHEDULED trip of the same
  /// class and re-syncs the ticket list. Returns an error message on failure,
  /// or null on success.
  Future<String?> transfer(String id, String targetTripId) async {
    try {
      await passengerApi.transferReservation(
        reservationId: id,
        targetTripId: targetTripId,
      );
      await syncFromLive();
      return null;
    } on PassengerApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not change the trip right now.';
    }
  }

  Future<void> remove(String id) async {
    _tickets = _tickets.where((t) => t.id != id).toList();
    notifyListeners();
  }
}