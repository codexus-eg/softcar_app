import 'package:flutter/foundation.dart';

import 'passenger_api.dart';

class WalletData {
  final double balance;
  final String currency;
  final String status;
  final List<Map<String, dynamic>> transactions;

  const WalletData({
    this.balance = 0,
    this.currency = 'EGP',
    this.status = 'ACTIVE',
    this.transactions = const [],
  });

  factory WalletData.fromJson(Map<String, dynamic> json) {
    final wallet =
        json['wallet'] is Map
            ? Map<String, dynamic>.from(json['wallet'])
            : <String, dynamic>{};
    final tx =
        json['transactions'] is List
            ? (json['transactions'] as List).whereType<Map>().toList()
            : <Map>[];
    final ledger =
        json['ledger'] is List
            ? (json['ledger'] as List).whereType<Map>().toList()
            : <Map>[];
    final pending =
        json['pendingTransactions'] is List
            ? (json['pendingTransactions'] as List).whereType<Map>().toList()
            : <Map>[];
    final byId = <String, Map<String, dynamic>>{};
    for (final row in [...pending, ...tx, ...ledger]) {
      final item = Map<String, dynamic>.from(row);
      final id = item['id']?.toString() ??
          '${item['type']}:${item['createdAt']}:${item['amount']}';
      byId[id] = item;
    }
    return WalletData(
      balance: _num(wallet['balance']),
      currency: wallet['currency']?.toString() ?? 'EGP',
      status: wallet['status']?.toString() ?? 'ACTIVE',
      transactions:
          byId.values.toList()
            ..sort(
              (a, b) => _date(
                b['createdAt'] ?? b['date'] ?? b['at'],
              ).compareTo(_date(a['createdAt'] ?? a['date'] ?? a['at'])),
            ),
    );
  }

  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  static DateTime _date(Object? v) =>
      DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
}

/// Live wallet balance + transactions provider.
class WalletService extends ChangeNotifier {
  WalletData _data = const WalletData();
  bool _loading = false;
  Object? _error;

  // Loyalty summary from GET /loyalty (points, level, progress).
  Map<String, dynamic> _loyalty = const {};
  bool _loyaltyLoading = false;

  WalletData get data => _data;
  bool get loading => _loading;
  Object? get error => _error;
  Map<String, dynamic> get loyalty => _loyalty;
  bool get loyaltyLoading => _loyaltyLoading;

  /// Top-up transactions still being reviewed (before the money lands). The
  /// backend allows at most two pending top-ups at a time.
  static const pendingTopupStatuses = {
    'PENDING_EVIDENCE',
    'PENDING_REVIEW',
    'METADATA_REVIEW',
    'PENDING_GATEWAY',
    'BANK_CHECKOUT_READY',
    'VISA_CHECKOUT_READY',
  };

  int get pendingTopups =>
      _data.transactions.where((t) {
        final status =
            (t['status']?.toString() ??
                    t['transactionStatus']?.toString() ??
                    t['topupStatus']?.toString() ??
                    '')
                .toUpperCase();
        return pendingTopupStatuses.contains(status);
      }).length;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (!passengerApi.isLoggedIn) throw StateError('Not signed in');
      final json = await passengerApi.getWallet();
      _data = WalletData.fromJson(json);
      refreshLoyalty();
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshLoyalty() async {
    if (_loyaltyLoading) return;
    _loyaltyLoading = true;
    notifyListeners();
    try {
      _loyalty = await passengerApi.getLoyalty();
    } catch (_) {
      _loyalty = const {};
    } finally {
      _loyaltyLoading = false;
      notifyListeners();
    }
  }

  /// Starts a wallet top-up: [amount] EGP + [senderNumber] + [channel]
  /// (e.g. TRANSFER/BANK_TRANSFER). Returns the created transaction, which
  /// needs a screenshot uploaded via [submitEvidence] for finance review.
  Future<Map<String, dynamic>> requestRecharge({
    required double amount,
    required String senderNumber,
    String channel = 'TRANSFER',
    String? recipientNumber,
  }) async {
    final body = <String, dynamic>{
      'amount': amount,
      'senderNumber': senderNumber.trim(),
      'channel': channel,
      if (recipientNumber != null && recipientNumber.trim().isNotEmpty)
        'recipientNumber': recipientNumber.trim(),
    };
    final json = await passengerApi.rechargeWallet(body);
    await refresh();
    return json;
  }

  /// Uploads a screenshot/transfer receipt for a top-up transaction so the
  /// finance team can review it (PENDING_REVIEW). [bytes] must be an image.
  Future<Map<String, dynamic>> submitEvidence({
    required String transactionId,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    final json = await passengerApi.uploadWalletEvidence(
      transactionId: transactionId,
      bytes: bytes,
      contentType: contentType,
    );
    await refresh();
    return json;
  }
}
