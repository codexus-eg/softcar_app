import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_map_style.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/egypt_time.dart';
import '../../models/shuttle.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/passenger_api.dart';
import '../../services/passenger_location_service.dart';
import '../../services/push_service.dart';
import '../../services/reservation_service.dart';
import '../../services/shuttle_service.dart';
import '../../services/voucher_service.dart';
import '../../widgets/call_chooser_sheet.dart';
import '../../services/wallet_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/road_route_layer.dart';
import '../../widgets/user_location_marker.dart';
import '../payment/payment_webview_screen.dart';

/// Seat selection for a live trip. Available seats adopt the passenger's
/// gender colour (pink for female / blue for male) and selected seats
/// render as "your seat". Booking is gated by the trip's type:
///  - ONE_TIME  → single reservation → ticket
///  - RECURRING → pick a date range + weekdays (+ optional tier) → plan
///  - ROUND_TRIP → pick return leg stops → outbound+return pair reservation
class SeatSelectionScreen extends StatefulWidget {
  const SeatSelectionScreen({super.key});

  @override
  State<SeatSelectionScreen> createState() => _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends State<SeatSelectionScreen> {
  ShuttleTrip? _trip;
  ReservationTier? _tier;
  String? _pickupId;
  String? _dropoffId;
  String? _returnPickupId;
  String? _returnDropoffId;
  DateTime? _startDate;
  DateTime? _endDate;
  final Set<int> _weekdays = {};
  final Set<int> _selected = {};
  Set<int> _taken = {};
  Map<int, UserGender?> _reservedGender = {};
  bool _busy = false;
  String _paymentMethod = 'CASH';
  final _voucherController = TextEditingController();
  bool _validatingVoucher = false;
  double _discount = 0;
  double? _quoteFare;
  bool _quoteManual = false;
  bool _quoting = false;

  @override
  void dispose() {
    _voucherController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_trip == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is SeatSelectionArgs) {
        _trip = args.trip;
        _tier = args.tier;
      } else if (args is ShuttleTrip) {
        _trip = args;
      }
      final trip = _trip;
      if (trip != null) {
        _pickupId =
            trip.pickupStops.isNotEmpty ? trip.pickupStops.first.id : null;
        _dropoffId =
            trip.dropoffStops.isNotEmpty ? trip.dropoffStops.first.id : null;
        if (args is SeatSelectionArgs) {
          final preferredPickup = args.preferredPickupPointId;
          if (preferredPickup != null &&
              trip.pickupStops.any((s) => s.id == preferredPickup)) {
            _pickupId = preferredPickup;
          }
          final preferredDropoff = args.preferredDropoffPointId;
          if (preferredDropoff != null &&
              trip.dropoffStops.any((s) => s.id == preferredDropoff) &&
              preferredDropoff != _pickupId) {
            _dropoffId = preferredDropoff;
          }
        }
        final ret = trip.returnTrip;
        if (ret != null && ret.pickupPoints.isNotEmpty) {
          _returnPickupId =
              ret.pickupStops.isNotEmpty ? ret.pickupStops.first.id : null;
          _returnDropoffId =
              ret.dropoffStops.isNotEmpty ? ret.dropoffStops.first.id : null;
        }
        final preferred =
            _tier != null && _tier!.durationDays > 0
                ? trip.startTime.add(Duration(days: _tier!.durationDays))
                : trip.startTime.add(const Duration(days: 30));
        _startDate = trip.startTime;
        _endDate = preferred;
        if (trip.reservedSeats.isNotEmpty) {
          _taken = trip.reservedSeats.keys.toSet();
          _reservedGender = Map.of(trip.reservedSeats);
        } else {
          _taken = _occupiedFor(trip);
          _reservedGender = {};
        }
        final pending = context.read<VoucherService>().pendingCode;
        if (pending != null && pending.isNotEmpty) {
          context.read<VoucherService>().pendingCode = null;
          _voucherController.text = pending;
        }
      }
      // Refresh tiers on every open so a passenger who deep-links straight
      // into seat selection still sees the admin-created packages.
      Future.microtask(context.read<ShuttleService>().loadTiers);
      // Refresh own reservations so "your seat" marks / rebooking guard are
      // accurate even when this screen is reached via a deep link.
      final reservations = context.read<ReservationService>();
      Future.microtask(() async {
        await reservations.syncFromLive();
        if (mounted) setState(() {});
      });
      // Always re-validate the seat map against the server so every reserved
      // seat reflects its real owner's gender (pink/blue) no matter which
      // entry path supplied the trip object.
      Future.microtask(_refreshOccupancy);
      // Quote the live segment fare for the default pickup/drop-off pair.
      Future.microtask(_refreshQuote);
    }
  }

  /// Picks which physical seats are already reserved so the map honestly
  /// reflects `seatsRemaining`. Deterministic per trip id on first visit;
  /// every reserved seat stays reserved for the rest of the session.
  Set<int> _occupiedFor(ShuttleTrip trip) {
    final takenCount = trip.totalSeats - trip.seatsRemaining;
    if (takenCount <= 0) return const {};
    final layout = trip.vehicle?.layout ?? const <SeatRow>[];
    final all = layout.expand((r) => r.all).toList();
    if (all.isEmpty) return const {};
    // A stable pseudo-random pick so the same trip always shows the same
    // map for a given logged-in passenger.
    var h = 0;
    for (final c in trip.id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final picked = <int>{};
    var i = (h % all.length + all.length) % all.length;
    for (var n = 0; n < takenCount && n < all.length; n++) {
      picked.add(all[i]);
      i = (i + (h % 7) + 1) % all.length;
    }
    return picked;
  }

  /// Maximum seats a passenger may reserve. Follows the admin rule from the
  /// selected tier (`maximumSeats`), falling back to 2 seats by default.
  int get _maxSeats {
    final tierMax = _tier?.maximumSeats ?? 0;
    return tierMax > 0 ? tierMax : 2;
  }

  /// Re-validates the seat map with the authoritative server payload so
  /// reserved seats always carry their real owner's gender, regardless of
  /// which entry path supplied the initial [ShuttleTrip]. Falls back silently
  /// to whatever the initial trip carried when the server is unreachable.
  Future<void> _refreshOccupancy() async {
    final trip = _trip;
    if (trip == null) return;
    try {
      final detail = await passengerApi.fetchTripDetail(trip.id);
      if (detail == null || !mounted) return;
      final reserved = ShuttleTrip.fromJson(detail).reservedSeats;
      if (reserved.isEmpty) return;
      setState(() {
        _taken = reserved.keys.toSet();
        _reservedGender = Map.of(reserved);
      });
    } catch (_) {
      // Keep whatever the initial trip already carried.
    }
  }

  /// Seats the signed-in passenger already holds on this trip (their own
  /// active reservations), so the map can highlight them as "yours".
  Set<int> _ownSeats() {
    final trip = _trip;
    if (trip == null) return const {};
    final ids = {trip.id, if (trip.returnTrip != null) trip.returnTrip!.id};
    final tickets = context.read<ReservationService>().tickets;
    final seats = <int>{};
    for (final t in tickets) {
      if (!t.isUpcoming || !ids.contains(t.tripId)) continue;
      for (final part in t.seatNumbers.split(',')) {
        final m = RegExp(r'\d+').firstMatch(part);
        final n = m == null ? null : int.parse(m.group(0)!);
        if (n != null) seats.add(n);
      }
    }
    return seats;
  }

  /// Whether the passenger already holds an active reservation for this trip
  /// (or its return leg), which the backend refuses to duplicate (HTTP 409).
  bool _alreadyBooked() {
    final trip = _trip;
    if (trip == null) return false;
    final ids = {trip.id, if (trip.returnTrip != null) trip.returnTrip!.id};
    return context
        .read<ReservationService>()
        .tickets
        .any((t) => t.isUpcoming && ids.contains(t.tripId));
  }

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  /// Per-seat fare: the quoted segment fare for the chosen pickup/drop-off
  /// pair when available, otherwise the trip's published fare.
  double _effectiveFare(ShuttleTrip trip) {
    final quoted = _quoteFare;
    return (quoted != null && quoted > 0) ? quoted : trip.fareForBooking;
  }

  /// Asks the backend for the live per-seat fare for the selected
  /// pickup → drop-off pair (and the return pair on round trips). Falls back
  /// silently to the published fare when the server can't quote.
  Future<void> _refreshQuote() async {
    final trip = _trip;
    if (trip == null || _pickupId == null || _dropoffId == null) return;
    setState(() => _quoting = true);
    try {
      var fare = 0.0;
      var manual = false;
      final out = await passengerApi.quoteTripPrice(
        tripId: trip.id,
        pickupPointId: _pickupId!,
        dropoffPointId: _dropoffId!,
      );
      final outUnit = _num(out['unitPrice']);
      if (outUnit > 0) fare += outUnit;
      if (out['pricingMode'] == 'manual') manual = true;
      final ret = trip.returnTrip;
      if (trip.tripType.isRoundTrip &&
          ret != null &&
          _returnPickupId != null &&
          _returnDropoffId != null) {
        final inQuote = await passengerApi.quoteTripPrice(
          tripId: ret.id,
          pickupPointId: _returnPickupId!,
          dropoffPointId: _returnDropoffId!,
        );
        final inUnit = _num(inQuote['unitPrice']);
        if (inUnit > 0) fare += inUnit;
        if (inQuote['pricingMode'] == 'manual') manual = true;
      }
      if (!mounted) return;
      setState(() {
        _quoteFare = fare > 0 ? fare : null;
        _quoteManual = manual;
        _quoting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _quoting = false);
    }
  }

  void _toggleSeat(int number) {
    if (_ownSeats().contains(number)) {
      Haptics.deny();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.t(context, 'youHoldSeat').replaceFirst('{seat}', '$number'),
          ),
        ),
      );
      return;
    }
    if (_taken.contains(number)) {
      Haptics.deny();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.t(
              context,
              'seatAlreadyReserved',
            ).replaceFirst('{seat}', '$number'),
          ),
        ),
      );
      return;
    }
    Haptics.selection();
    setState(() {
      if (_selected.contains(number)) {
        _selected.remove(number);
      } else {
        if (_selected.length >= _maxSeats) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.t(context, 'maxSeatsPerReservation').replaceFirst(
                  '{count}',
                  '$_maxSeats',
                ),
              ),
            ),
          );
        } else if (_selected.length < _trip!.seatsRemaining) {
          _selected.add(number);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.t(
                  context,
                  'onlySeatsRemain',
                ).replaceFirst('{count}', '${_trip!.seatsRemaining}'),
              ),
            ),
          );
        }
      }
      // The voucher discount is tied to the chosen seats — recompute on change.
      _discount = 0;
    });
  }

  /// Validates the voucher code against this trip and applies the discount
  /// the backend returns to the displayed fare.
  Future<void> _applyVoucher() async {
    final trip = _trip;
    final code = _voucherController.text.trim();
    if (trip == null || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'voucherRequired'))),
      );
      return;
    }
    setState(() => _validatingVoucher = true);
    try {
      final json = await passengerApi.validateVoucher(
        code: code,
        tripId: trip.id,
        pickupPointId: _pickupId,
        dropoffPointId: _dropoffId,
        seats: _selected.isEmpty ? null : _selected.length,
        tierId: _tier?.id,
      );
      final subtotal = _baseTotal(
        _effectiveFare(trip),
        _selected.isEmpty ? 1 : _selected.length,
      );
      final discount = parseVoucherDiscount(json, subtotal);
      if (!mounted) return;
      setState(() {
        _discount = discount;
        _validatingVoucher = false;
      });
      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            discount > 0
                ? L10n.t(context, 'voucherApplied').replaceFirst(
                  '{discount}',
                  '${discount.toStringAsFixed(0)} EGP',
                )
                : L10n.t(
                  context,
                  'voucherApplied',
                ).replaceFirst('{discount}', L10n.t(context, 'freeSeat')),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _discount = 0;
        _validatingVoucher = false;
      });
      final message = e is PassengerApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.t(context, 'voucherInvalid').replaceFirst('{error}', message),
          ),
        ),
      );
    }
  }

  /// Subtotal after the validated voucher discount (never below zero).
  double _discountedSubtotal(ShuttleTrip trip, int seats) {
    final base = _baseTotal(_effectiveFare(trip), seats);
    return base - _discount.clamp(0.0, base);
  }

  Future<void> _confirm() async {
    final trip = _trip;
    if (trip == null || _selected.isEmpty) return;

    // Recurring plan: seat chosen once, schedule picked separately.
    if (trip.tripType.isRecurring) {
      await _confirmRecurring();
      return;
    }

    final shuttle = context.read<ShuttleService>();
    final reservations = context.read<ReservationService>();
    final wallet = context.read<WalletService>();
    final navigator = Navigator.of(context);
    final bus = trip.tripType.isRoundTrip;
    final pickupId = _pickupId ?? trip.pickupStops.first.id;
    final dropoffId = _dropoffId ?? trip.dropoffStops.first.id;
    final returnTrip = trip.returnTrip;
    if (bus &&
        (returnTrip == null ||
            _returnPickupId == null ||
            _returnDropoffId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'returnLegRequired'))),
      );
      return;
    }
    if (_alreadyBooked()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'alreadyReservedForTrip'))),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // Wallet payments need enough balance to cover the total (incl. tax).
      if (_paymentMethod == 'WALLET') {
        final total = _discountedSubtotal(trip, _selected.length) * 1.14;
        if (wallet.data.balance < total) {
          if (!mounted) return;
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'insufficientBalance')),
              action: SnackBarAction(
                label: L10n.t(context, 'topUpWallet'),
                onPressed:
                    () => Navigator.of(context).pushNamed('/wallet-recharge'),
              ),
            ),
          );
          return;
        }
      }
      
      final seatNumbers = _selected
          .map((n) => 'S${n.toString().padLeft(2, '0')}')
          .join(',');
      
      // For CARD payments: book first (PENDING_CARD_CHECKOUT), then open
      // the Cybersource hosted checkout in a WebView and poll until done.
      if (_paymentMethod == 'CARD') {
        // 1. Create the reservation (sets paymentStatus = PENDING_CARD_CHECKOUT)
        final ticket = await shuttle.book(
          trip: trip,
          pickupPointId: pickupId,
          dropoffPointId: dropoffId,
          seats: _selected.length,
          seatNumbers: seatNumbers,
          paymentMethod: _paymentMethod,
          returnPickupPointId: _returnPickupId,
          returnDropoffPointId: _returnDropoffId,
          roundTripReturnTripId: returnTrip?.id,
          tierId: _tier?.id,
        );

        if (!mounted) return;

        // 2. Create the Cybersource checkout session for this reservation
        final sessionResponse = await passengerApi.createPaymentSession(
          reservationId: ticket.id,
        );

        if (!mounted) return;

        final checkoutUrl = sessionResponse['checkoutUrl']?.toString();
        final transactionId = sessionResponse['transactionId']?.toString();

        if (checkoutUrl == null || transactionId == null) {
          setState(() => _busy = false);
          final msg = sessionResponse['message']?.toString() ??
              L10n.t(context, 'bookingFailed')
                  .replaceFirst('{error}', 'Payment gateway not ready');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
          return;
        }

        // 3. Open the Cybersource checkout page in the in-app WebView
        final paymentResult = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PaymentWebViewScreen(
              checkoutUrl: checkoutUrl,
              transactionId: transactionId,
              amount: ticket.total,
            ),
          ),
        );

        if (!mounted) return;

        // 4. Refresh and navigate
        await reservations.syncFromLive();
        try {
          await wallet.refresh();
        } catch (_) {}
        Haptics.success();

        if (paymentResult == true) {
          navigator.pushNamed('/booking-success', arguments: ticket);
        } else {
          // Payment was cancelled – reservation stays PENDING_CARD_CHECKOUT
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.t(context, 'paymentFailed'))),
          );
        }
        return;
      }
      
      // CASH or WALLET - proceed directly
      final ticket = await shuttle.book(
        trip: trip,
        pickupPointId: pickupId,
        dropoffPointId: dropoffId,
        seats: _selected.length,
        seatNumbers: seatNumbers,
        paymentMethod: _paymentMethod,
        returnPickupPointId: _returnPickupId,
        returnDropoffPointId: _returnDropoffId,
        roundTripReturnTripId: returnTrip?.id,
        tierId: _tier?.id,
      );
      await reservations.syncFromLive();
      if (mounted) {
        try {
          await wallet.refresh();
        } catch (_) {}
      }
      if (!mounted) return;
      Haptics.success();
      final pushTitle = L10n.t(context, 'softcarShuttle');
      final pushBody =
          '${L10n.t(context, 'confirmed')} · '
          '${ticket.from} → ${ticket.to} · '
          '${ticket.seats}';
      await PushService.instance.requestPermission();
      await PushService.instance.show(
        title: pushTitle,
        body: pushBody,
        payload: jsonEncode(<String, String>{
          'type': 'BOOKING_CONFIRMED',
          'id': ticket.id,
        }),
      );
      if (!navigator.mounted) return;
      if (bus) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'roundTripCreatedSub'))),
        );
      }
      navigator.pushNamed('/booking-success', arguments: ticket);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.t(context, 'bookingFailed').replaceFirst('{error}', '$e'),
          ),
        ),
      );
    }
  }

  Future<void> _confirmRecurring() async {
    final trip = _trip;
    final start = _startDate;
    final end = _endDate;
    if (trip == null || _selected.isEmpty) return;
    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'dateRangeRequired'))),
      );
      return;
    }
    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'invalidDateRange'))),
      );
      return;
    }
    if (_weekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'noWeekdaySelected'))),
      );
      return;
    }
    if (_alreadyBooked()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'alreadyReservedForTrip'))),
      );
      return;
    }
    final shuttle = context.read<ShuttleService>();
    final wallet = context.read<WalletService>();
    final navigator = Navigator.of(context);
    final pickupId = _pickupId ?? trip.pickupStops.first.id;
    final dropoffId = _dropoffId ?? trip.dropoffStops.first.id;
    setState(() => _busy = true);
    try {
      if (_paymentMethod == 'WALLET') {
        final total = _discountedSubtotal(trip, _selected.length) * 1.14;
        if (wallet.data.balance < total) {
          if (!mounted) return;
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.t(context, 'insufficientBalance'))),
          );
          return;
        }
      }
      final seatNumbers = _selected
          .map((n) => 'S${n.toString().padLeft(2, '0')}')
          .join(',');
      final result = await shuttle.bookRecurring(
        trip: trip,
        pickupPointId: pickupId,
        dropoffPointId: dropoffId,
        seats: _selected.length,
        seatNumbers: seatNumbers,
        startDate: start,
        endDate: end,
        weekdays: _weekdays.toList()..sort(),
        paymentMethod: _paymentMethod,
        tier: _tier,
        returnTrip: trip.returnTrip,
        returnPickupPointId: _returnPickupId,
        returnDropoffPointId: _returnDropoffId,
      );
      if (mounted) {
        try {
          await wallet.refresh();
        } catch (_) {}
      }
      if (!mounted) return;
      final created =
          result['createdReservations'] is List
              ? (result['createdReservations'] as List).length
              : 0;
      Haptics.success();
      if (created > 0) {
        await context.read<ReservationService>().syncFromLive();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${L10n.t(context, 'recurringCreated')} · '
            '$created ${L10n.t(context, 'departures')}',
          ),
        ),
      );
      if (navigator.mounted) navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.t(
              context,
              'bookingRecurringFailed',
            ).replaceFirst('{error}', '$e'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    if (trip == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final auth = context.watch<AuthService>();
    final gender = auth.profile.gender;
    final seatColor = GenderColor.forGender(gender);
    final layout = trip.vehicle?.layout ?? _fallbackLayout(trip.totalSeats);
    final ownSeats = _ownSeats();
    final reservedFallback =
        gender == UserGender.male
            ? const Color(0xFF1E3A8A)
            : gender == UserGender.female
            ? const Color(0xFF9D174D)
            : AppColors.inkSoft;

    return Scaffold(
      appBar: AppBar(
        title: Text(trip.vehicle?.name ?? L10n.t(context, 'shuttle')),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: PrimaryButton(
            label:
                _selected.isEmpty
                    ? L10n.t(context, 'selectSeats')
                    : trip.tripType.isRecurring
                    ? '${L10n.t(context, 'bookRecurring')} ${_selected.length} '
                        '${_selected.length == 1 ? L10n.t(context, 'seatAbbr') : L10n.t(context, 'seatsAbbr')}'
                    : '${L10n.t(context, 'book')} ${_selected.length} '
                        '${_selected.length == 1 ? L10n.t(context, 'seatAbbr') : L10n.t(context, 'seatsAbbr')} · '
                        '${_priceTotal(_effectiveFare(trip), _selected.length, _discount)} EGP',
            accent: true,
            loading: _busy,
            onPressed: _selected.isNotEmpty ? _confirm : null,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        children: [
          _TripSummary(trip: trip),
          _RouteMap(trip: trip),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _StopSelector(
                  label: L10n.t(context, 'pickup'),
                  stops: trip.pickupStops,
                  value: _pickupId,
                  onChange:
                      (id) => setState(() {
                        _pickupId = id;
                        _discount = 0;
                      }),
                  onChangedExtra: _refreshQuote,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StopSelector(
                  label: L10n.t(context, 'dropoff'),
                  stops: trip.dropoffStops,
                  value: _dropoffId,
                  onChange:
                      (id) => setState(() {
                        _dropoffId = id;
                        _discount = 0;
                      }),
                  onChangedExtra: _refreshQuote,
                ),
              ),
            ],
          ),
          if (_quoting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                L10n.t(context, 'updatingFare'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 18),
          _Legend(seatColor: seatColor),
          const SizedBox(height: 4),
          Text(
            trip.seatsRemaining > 0
                ? L10n.t(context, 'seatsLeft')
                    .replaceFirst('{free}', '${trip.seatsRemaining}')
                    .replaceFirst('{total}', '${trip.totalSeats}')
                : L10n.t(context, 'thisTripFull'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.t(context, 'maxSeatsHint').replaceFirst('{count}', '$_maxSeats'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.accent),
          ),
          if (ownSeats.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_seat_rounded,
                    size: 18,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.t(context, 'ownReservationNotice'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          _SeatGrid(
            layout: layout,
            takenSeats: {..._taken, ...ownSeats},
            reservedGender: _reservedGender,
            selected: _selected,
            seatColor: seatColor,
            ownSeats: ownSeats,
            reservedFallback: reservedFallback,
            onTap: _toggleSeat,
          ),
          const SizedBox(height: 18),
          if (trip.tripType.isRecurring) ...[
            _RecurringCard(
              startDate: _startDate,
              endDate: _endDate,
              weekdays: _weekdays,
              tier: _tier,
              onStartDate: (d) => setState(() => _startDate = d),
              onEndDate: (d) => setState(() => _endDate = d),
              onToggleWeekday:
                  (d) => setState(() {
                    if (_weekdays.contains(d)) {
                      _weekdays.remove(d);
                    } else {
                      _weekdays.add(d);
                    }
                  }),
              onTier:
                  (t) => setState(() {
                    _tier = t;
                    _discount = 0;
                    final tierMax = t?.maximumSeats ?? 0;
                    final cap = tierMax > 0 ? tierMax : 2;
                    if (_selected.length > cap) {
                      final sorted = _selected.toList()..sort();
                      _selected
                        ..clear()
                        ..addAll(sorted.take(cap));
                    }
                  }),
            ),
            const SizedBox(height: 18),
          ],
          if (trip.tripType.isRoundTrip && trip.returnTrip != null) ...[
            _ReturnLegCard(
              returnTrip: trip.returnTrip!,
              pickupId: _returnPickupId,
              dropoffId: _returnDropoffId,
              onPickup:
                  (id) => setState(() {
                    _returnPickupId = id;
                    _discount = 0;
                  }),
              onDropoff:
                  (id) => setState(() {
                    _returnDropoffId = id;
                    _discount = 0;
                  }),
            ),
            const SizedBox(height: 18),
          ],
          const SizedBox(height: 18),
          SoftCard(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _voucherController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: L10n.t(context, 'voucherCode'),
                      prefixIcon: const Icon(
                        Icons.confirmation_number_outlined,
                        size: 20,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: PrimaryButton(
                    label: L10n.t(context, 'apply'),
                    height: 48,
                    loading: _validatingVoucher,
                    onPressed: _validatingVoucher ? null : _applyVoucher,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 18,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                L10n.t(context, 'bookingSummary'),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PriceBox(
            fare: _effectiveFare(trip),
            seats: _selected.length,
            discount: _discount,
            voucherCode: _voucherController.text.trim(),
            fareLabel: _quoteManual
                ? L10n.t(context, 'segmentFare')
                : null,
          ),
          const SizedBox(height: 18),
          _DriverCard(trip: trip),
          const SizedBox(height: 18),
          _PaymentPicker(
            method: _paymentMethod,
            walletBalance: context.watch<WalletService>().data.balance,
            total: _discountedSubtotal(trip, _selected.length) * 1.14,
            onChanged: (m) => setState(() => _paymentMethod = m),
            onTopUp: () => Navigator.of(context).pushNamed('/wallet-recharge'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

double _baseTotal(double fare, int seats) {
  final f = fare.ceilToDouble();
  return f * seats;
}

// Fallback floor plan when a trip has no mapped vehicle class:
// plain 4-across rows so the screen never breaks.
List<SeatRow> _fallbackLayout(int count) {
  var n = 1;
  final rows = <SeatRow>[];
  while (n <= count) {
    final all = <int>[];
    for (var c = 0; c < 4 && n <= count; c++) {
      all.add(n);
      n++;
    }
    final mid = (all.length / 2).ceil();
    rows.add(
      SeatRow(
        number: rows.length + 1,
        left: all.sublist(0, mid),
        right: all.sublist(mid),
      ),
    );
  }
  return rows;
}

String _priceTotal(double fare, int seats, double discount) {
  final base = _baseTotal(fare, seats);
  final v = base - discount.clamp(0.0, base);
  return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _RouteMap extends StatefulWidget {
  final ShuttleTrip trip;
  const _RouteMap({required this.trip});

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  final MapController _map = MapController();
  bool _locating = false;

  /// Builds the list of geographic points from the stops that actually
  /// carry coordinates, so a stop with default (0,0) is never drawn.
  List<LatLng> get _points {
    final pts = <LatLng>[];
    for (final s in widget.trip.pickupPoints) {
      if (s.latitude != 0 || s.longitude != 0) {
        pts.add(LatLng(s.latitude, s.longitude));
      }
    }
    return pts;
  }

  @override
  void initState() {
    super.initState();
    PassengerLocationService.instance.addListener(_onLocationChanged);
  }

  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PassengerLocationService.instance.removeListener(_onLocationChanged);
    _map.dispose();
    super.dispose();
  }

  /// Static preview: no position stream, just a one-shot fix that recenters
  /// the mini map on the passenger.
  Future<void> _locateMe() async {
    final location = PassengerLocationService.instance;
    setState(() => _locating = true);
    try {
      final pos = await location.getSingleFix();
      if (!mounted) return;
      if (pos == null) return;
      _map.move(pos, 16);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    if (pts.length < 2) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 150,
          child: Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(pts),
                      padding: const EdgeInsets.all(28),
                    ),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: tileUrlForTime(),
                      subdomains: subdomainsForTime() ?? const [],
                      userAgentPackageName: 'com.softcar.shuttle',
                    ),
                    RoadRoutePolyline(
                      points: pts,
                      color: AppColors.mapRoute,
                      strokeWidth: 4,
                    ),
                    MarkerLayer(
                      markers: [
                        for (var i = 0; i < pts.length; i++)
                          Marker(
                            point: pts[i],
                            width: 34,
                            height: 34,
                            child: Icon(
                              i == 0
                                  ? Icons.trip_origin
                                  : i == pts.length - 1
                                  ? Icons.fmd_good_rounded
                                  : Icons.circle,
                              size: i == 0 || i == pts.length - 1 ? 24 : 12,
                              color: AppColors.accent,
                            ),
                          ),
                        if (PassengerLocationService.instance.currentPosition !=
                            null)
                          UserLocationMarker(
                            point: PassengerLocationService
                                .instance.currentPosition!,
                            size: 24,
                          ).toMarker(),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: LocateMeButton(
                  busy: _locating,
                  tooltip: L10n.t(context, 'locateMe'),
                  onTap: _locateMe,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripSummary extends StatelessWidget {
  final ShuttleTrip trip;
  const _TripSummary({required this.trip});

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (trip.tripType) {
      TripType.oneTime => L10n.t(context, 'oneTimeTrip'),
      TripType.recurring => L10n.t(context, 'recurringTrip'),
      TripType.roundTrip => L10n.t(context, 'roundTrip'),
      TripType.template => L10n.t(context, 'oneTimeTrip'),
    };
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                trip.vehicle?.name ?? L10n.t(context, 'shuttle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  egFormat(trip.startTime, 'EEE, HH:mm'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  typeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          _StopsLine(points: trip.pickupPoints),
        ],
      ),
    );
  }
}

class _StopsLine extends StatelessWidget {
  final List<ShuttleStop> points;
  const _StopsLine({required this.points});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < points.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  i == 0
                      ? Icons.trip_origin
                      : i == points.length - 1
                      ? Icons.fmd_good_rounded
                      : Icons.circle,
                  size: i == 0 || i == points.length - 1 ? 16 : 8,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    points[i].name,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  points[i].stopOrder == 0
                      ? L10n.t(context, 'first')
                      : points[i].stopOrder == points.length - 1
                      ? L10n.t(context, 'last')
                      : '${L10n.t(context, 'stop')} ${points[i].stopOrder}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StopSelector extends StatelessWidget {
  final List<ShuttleStop> stops;
  final String? value;
  final ValueChanged<String?> onChange;
  final String? label;
  final VoidCallback? onChangedExtra;

  const _StopSelector({
    required this.stops,
    required this.value,
    required this.onChange,
    this.label,
    this.onChangedExtra,
  });

  @override
  Widget build(BuildContext context) {
    ShuttleStop? current;
    for (final s in stops) {
      if (s.id == value) current = s;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Text(
              label!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
        InkWell(
          onTap: () async {
            final id = await showModalBottomSheet<String>(
              context: context,
              builder:
                  (ctx) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SheetHandle(),
                      for (final s in stops)
                        ListTile(
                          title: Text(s.name),
                          selected: s.id == value,
                          onTap: () => Navigator.pop(ctx, s.id),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
            );
            if (id != null) {
              onChange(id);
              onChangedExtra?.call();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    current?.name ?? L10n.t(context, 'chooseStop'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color seatColor;
  const _Legend({required this.seatColor});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _LegendDot(color: seatColor, label: L10n.t(context, 'yourSeat')),
        const SizedBox(width: 2),
        _LegendDot(color: Colors.white, label: L10n.t(context, 'free')),
        const SizedBox(width: 2),
        _LegendDot(
          color: const Color(0xFF1E3A8A),
          label: L10n.t(context, 'reservedMale'),
        ),
        const SizedBox(width: 2),
        _LegendDot(
          color: const Color(0xFF9D174D),
          label: L10n.t(context, 'reservedFemale'),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.divider),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SeatGrid extends StatelessWidget {
  final List<SeatRow> layout;
  final Set<int> takenSeats;
  final Map<int, UserGender?> reservedGender;
  final Set<int> selected;
  final Color seatColor;
  final Set<int> ownSeats;
  final Color reservedFallback;
  final ValueChanged<int> onTap;

  const _SeatGrid({
    required this.layout,
    required this.takenSeats,
    required this.reservedGender,
    required this.selected,
    required this.seatColor,
    required this.ownSeats,
    required this.reservedFallback,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final freeCount =
        layout.expand((r) => r.all).length -
        takenSeats.length -
        selected.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          // Front of the vehicle --------------------------------------------
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.inkSoft,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    L10n.t(context, 'driver'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white70 : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.accent.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.airport_shuttle_rounded,
                  size: 17,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final row in layout)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(
                      '${L10n.t(context, 'row')} ${row.number}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Left block (window side)
                        for (final n in row.left) ...[
                          _seat(n),
                          const SizedBox(width: 4),
                        ],
                        if (row.left.isNotEmpty) const SizedBox(width: 8),
                        // Aisle gap
                        Container(
                          width: 12,
                          height: 34,
                          decoration: BoxDecoration(
                            color:
                                isDark
                                    ? AppColors.dividerDark
                                    : AppColors.divider,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        if (row.right.isNotEmpty) const SizedBox(width: 8),
                        for (final n in row.right) ...[
                          _seat(n),
                          const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 46,
                    child: Text(
                      '${L10n.t(context, 'row')} ${row.number}',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            freeCount > 0
                ? '$freeCount '
                    '${freeCount == 1 ? L10n.t(context, 'freeSeat') : L10n.t(context, 'freeSeats')}'
                : L10n.t(context, 'allSeatsReserved'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: freeCount > 0 ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _seat(int n) {
    final taken = takenSeats.contains(n);
    final isSelected = selected.contains(n);
    final reservedByMe = ownSeats.contains(n);
    final maxSide = 4;
    final edge = _edgeWidth(maxSide);
    final takenColor = switch (reservedGender[n]) {
      UserGender.male => const Color(0xFF1E3A8A),
      UserGender.female => const Color(0xFF9D174D),
      _ => reservedFallback,
    };
    return GestureDetector(
      onTap: () => onTap(n),
      child: Container(
        width: edge,
        height: 34,
        decoration: BoxDecoration(
          color:
              taken
                  ? takenColor
                  : isSelected
                  ? seatColor
                  : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color:
                reservedByMe
                    ? Colors.white
                    : taken
                    ? takenColor
                    : isSelected
                    ? seatColor
                    : AppColors.divider,
            width: reservedByMe ? 2 : (isSelected ? 1.6 : 1),
          ),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: seatColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                  : reservedByMe
                  ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.6),
                      blurRadius: 3,
                    ),
                  ]
                  : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color:
                taken
                    ? Colors.white
                    : isSelected
                    ? Colors.white
                    : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// Fixed seat width that keeps up to 4 across + aisle inside phone width.
  double _edgeWidth(int across) {
    return switch (across) {
      4 => 44.0,
      3 => 52.0,
      _ => 58.0,
    };
  }
}

class _PriceBox extends StatelessWidget {
  final double fare;
  final int seats;
  final double discount;
  final String voucherCode;
  final String? fareLabel;
  const _PriceBox({
    required this.fare,
    required this.seats,
    this.discount = 0,
    this.voucherCode = '',
    this.fareLabel,
  });

  @override
  Widget build(BuildContext context) {
    final subtotal = fare * seats;
    final applied = discount.clamp(0.0, subtotal);
    final discounted = subtotal - applied;
    final tax = discounted * 0.14;
    final total = discounted + tax;
    return SoftCard(
      child: Column(
        children: [
          if (seats > 0) ...[
            _line(
              fareLabel ??
                  '${L10n.t(context, 'fare')} '
                      '(${seats == 1 ? '1 ${L10n.t(context, 'seatAbbr')}' : '$seats ${L10n.t(context, 'seatsAbbr')}'})',
              subtotal,
            ),
            if (applied > 0) ...[
              const SizedBox(height: 8),
              _line(
                voucherCode.isNotEmpty
                    ? '${L10n.t(context, 'discount')} ($voucherCode)'
                    : L10n.t(context, 'discount'),
                -applied,
                strong: true,
                valueColor: AppColors.success,
              ),
            ],
            const SizedBox(height: 8),
            _line('${L10n.t(context, 'taxVat')} (14%)', tax),
            Divider(color: AppColors.divider, height: 20),
            _line(L10n.t(context, 'total'), total, strong: true),
          ] else
            Text(
              L10n.t(context, 'pickSeatsForPrice'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

Widget _line(
  String label,
  double value, {
  bool strong = false,
  Color? valueColor,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      Text(
        '${value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2)} EGP',
        style: TextStyle(
          fontSize: 14,
          fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
          color: valueColor,
        ),
      ),
    ],
  );
}

class _PaymentPicker extends StatelessWidget {
  final String method;
  final double walletBalance;
  final double total;
  final ValueChanged<String> onChanged;
  final VoidCallback onTopUp;
  const _PaymentPicker({
    required this.method,
    required this.walletBalance,
    required this.total,
    required this.onChanged,
    required this.onTopUp,
  });

  @override
  Widget build(BuildContext context) {
    final walletEnough = walletBalance >= total;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.t(context, 'paymentMethod'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _methodTile(
            context,
            value: 'CASH',
            icon: Icons.payments_outlined,
            title: L10n.t(context, 'cashOnArrival'),
            subtitle: L10n.t(context, 'payWithCash'),
          ),
          const Divider(height: 1),
          _methodTile(
            context,
            value: 'WALLET',
            icon: Icons.account_balance_wallet_outlined,
            title: L10n.t(context, 'payWallet'),
            subtitle:
                walletEnough
                    ? L10n.t(context, 'payWithWallet')
                    : '${L10n.t(context, 'walletBalance')}: '
                        '${walletBalance.toStringAsFixed(0)} EGP · '
                        '${L10n.t(context, 'insufficientBalance')}',
            trailing:
                walletEnough
                    ? null
                    : GestureDetector(
                      onTap: onTopUp,
                      child: Text(
                        L10n.t(context, 'topUpWallet'),
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
          ),
          const Divider(height: 1),
          _methodTile(
            context,
            value: 'CARD',
            icon: Icons.credit_card,
            title: L10n.t(context, 'payCard'),
            subtitle: L10n.t(context, 'payWithCard'),
          ),
        ],
      ),
    );
  }

  Widget _methodTile(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    bool enabled = true,
  }) {
    final selected = method == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        size: 22,
        color: enabled ? AppColors.accent : AppColors.textTertiary,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: enabled ? null : AppColors.textTertiary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing:
          enabled
              ? Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.accent : AppColors.textTertiary,
                size: 20,
              )
              : Chip(
                label: Text(L10n.t(context, 'cardSoon')),
                backgroundColor: AppColors.accentSoft,
                labelStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
      onTap: enabled ? () => onChanged(value) : null,
    );
  }
}

class _DriverCard extends StatelessWidget {
  final ShuttleTrip trip;
  const _DriverCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final driver = trip.driver;
    if (driver == null || !driver.isAssigned) {
      return SoftCard(
        child: Row(
          children: [
            const Icon(Icons.person_outline, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context, 'assignedDriver'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    L10n.t(context, 'driverNotAssigned'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return SoftCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.accentSoft,
            backgroundImage:
                driver.photoUrl != null && driver.photoUrl!.isNotEmpty
                    ? NetworkImage(Formatters.imageUrl(driver.photoUrl))
                    : null,
            child:
                driver.photoUrl == null || driver.photoUrl!.isEmpty
                    ? const Icon(Icons.person, color: AppColors.accent)
                    : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.t(context, 'assignedDriver'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  driver.name ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (driver.phone != null && driver.phone!.isNotEmpty)
                  Text(
                    driver.phone!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (driver.carModel != null && driver.carModel!.isNotEmpty)
                Text(
                  driver.carModel!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              if (driver.carPlateNumber != null &&
                  driver.carPlateNumber!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    driver.carPlateNumber!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              if ((driver.userId?.isNotEmpty ?? false) ||
                  (driver.phone?.isNotEmpty ?? false))
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.success.withValues(alpha: 0.12),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    color: AppColors.success,
                    icon: const Icon(Icons.call_rounded),
                    onPressed: () => showCallChooser(
                      context,
                      targetUserId: driver.userId ?? 'DRIVER',
                      displayName:
                          driver.name ?? L10n.t(context, 'assignedDriver'),
                      phone: driver.phone,
                      tripId: trip.id,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Recurring-trip extras: a start/end date range, the repeat weekdays and an
/// optional reserve tier. Only shown for `RECURRING` trips.
class _RecurringCard extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final Set<int> weekdays;
  final ReservationTier? tier;
  final ValueChanged<DateTime?> onStartDate;
  final ValueChanged<DateTime?> onEndDate;
  final ValueChanged<int> onToggleWeekday;
  final ValueChanged<ReservationTier?> onTier;

  const _RecurringCard({
    required this.startDate,
    required this.endDate,
    required this.weekdays,
    required this.tier,
    required this.onStartDate,
    required this.onEndDate,
    required this.onToggleWeekday,
    required this.onTier,
  });

  static const _days = [
    ('sun', 0),
    ('mon', 1),
    ('tue', 2),
    ('wed', 3),
    ('thu', 4),
    ('fri', 5),
    ('sat', 6),
  ];

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.repeat_rounded,
                color: AppColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                L10n.t(context, 'recurringSchedule'),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            L10n.t(context, 'recurringScheduleSub'),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: L10n.t(context, 'startDate'),
                  value: startDate,
                  onPick:
                      () async =>
                          onStartDate(await _pickDate(context, startDate)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateField(
                  label: L10n.t(context, 'endDate'),
                  value: endDate,
                  onPick:
                      () async => onEndDate(await _pickDate(context, endDate)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            L10n.t(context, 'weekdays'),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (key, day) in _days)
                ChoiceChip(
                  label: Text(L10n.t(context, key)),
                  selected: weekdays.contains(day),
                  onSelected: (_) => onToggleWeekday(day),
                  selectedColor: AppColors.accentSoft,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color:
                        weekdays.contains(day)
                            ? AppColors.accent
                            : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          if (tier != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.sell_outlined,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${L10n.t(context, 'tierApplied')}: ${tier!.name}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.success,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Future<DateTime?> _pickDate(
    BuildContext context,
    DateTime? current,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 366)),
    );
    return picked;
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final Future<void> Function() onPick;
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: AppColors.accent,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                value == null ? label : DateFormat('MMM d').format(value!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color:
                      value == null
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round-trip extras: the return leg pickup and drop-off stops, taken from
/// the paired return trip. Only shown for `ROUND_TRIP` trips.
class _ReturnLegCard extends StatelessWidget {
  final ShuttleTrip returnTrip;
  final String? pickupId;
  final String? dropoffId;
  final ValueChanged<String?> onPickup;
  final ValueChanged<String?> onDropoff;

  const _ReturnLegCard({
    required this.returnTrip,
    required this.pickupId,
    required this.dropoffId,
    required this.onPickup,
    required this.onDropoff,
  });

  @override
  Widget build(BuildContext context) {
    final stops = returnTrip.pickupPoints;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                L10n.t(context, 'returnLeg'),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${L10n.t(context, 'returnLegSub')} · '
            '${egFormat(returnTrip.startTime, 'EEE, HH:mm')}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ReturnStop(
                  label: L10n.t(context, 'chooseReturnPickup'),
                  stops: stops,
                  value: pickupId,
                  onChanged: onPickup,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReturnStop(
                  label: L10n.t(context, 'chooseReturnDropoff'),
                  stops: stops,
                  value: dropoffId,
                  onChanged: onDropoff,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReturnStop extends StatelessWidget {
  final String label;
  final List<ShuttleStop> stops;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _ReturnStop({
    required this.label,
    required this.stops,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    String? display;
    for (final s in stops) {
      if (s.id == value) display = s.name;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
        ),
        GestureDetector(
          onTap: () async {
            final id = await showModalBottomSheet<String>(
              context: context,
              builder:
                  (ctx) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SheetHandle(),
                      for (final s in stops)
                        ListTile(
                          title: Text(s.name),
                          selected: s.id == value,
                          onTap: () => Navigator.pop(ctx, s.id),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
            );
            if (id != null) onChanged(id);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    display ?? L10n.t(context, 'chooseStop'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
