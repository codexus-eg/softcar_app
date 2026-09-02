import 'package:flutter/foundation.dart';

import 'passenger_api.dart';

/// Active promo vouchers from `GET /api/vouchers/active` plus the code the
/// passenger wants to pre-fill into booking ("fast apply"), shared between the
/// first-open overlay and the seat-selection voucher field.
class VoucherService extends ChangeNotifier {
  List<Map<String, dynamic>> _vouchers = const [];
  bool _loading = false;
  String? _pendingCode;

  List<Map<String, dynamic>> get vouchers => _vouchers;
  bool get loading => _loading;

  /// The voucher code to pre-fill into the next seat-selection screen after
  /// the user picked "Apply now" on the overlay.
  String? get pendingCode => _pendingCode;
  set pendingCode(String? code) {
    _pendingCode = code;
    notifyListeners();
  }

  Future<void> loadActive() async {
    _loading = true;
    notifyListeners();
    try {
      _vouchers = await passengerApi.getActiveVouchers();
    } catch (_) {
      _vouchers = const [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

/// Extracts the validated discount (in EGP) from the `/vouchers/validate`
/// response. Accepts either an absolute `discountAmount`/`amount` or a
/// `discountPercent` applied to [subtotal], digging through common `data` /
/// `result` / `voucher` wrappers. Clamped to [subtotal].
double parseVoucherDiscount(Map<String, dynamic> json, double subtotal) {
  double numOf(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  final maps = <Map<String, dynamic>>[json];
  for (final key in ['data', 'result', 'voucher', 'validation']) {
    final nested = json[key];
    if (nested is Map) {
      maps.add(Map<String, dynamic>.from(nested));
    }
  }

  const amountKeys = [
    'discountAmount',
    'discountValue',
    'discountAmountPerBooking',
    'amount',
    'discount',
  ];
  for (final m in maps) {
    for (final key in amountKeys) {
      final v = m[key];
      final n = numOf(v);
      if (n > 0) return n > subtotal ? subtotal : n;
    }
  }
  for (final m in maps) {
    final pct = numOf(m['discountPercent'] ?? m['percent'] ?? m['percentage']);
    if (pct > 0) {
      final amount = subtotal * pct / 100;
      return amount > subtotal ? subtotal : amount;
    }
  }
  return 0;
}
