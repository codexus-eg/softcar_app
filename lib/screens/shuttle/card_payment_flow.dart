import '../../services/passenger_api.dart';

/// Outcome of one authenticated payment-status check.
enum CardPaymentStatusResult { pending, completed, terminal }

/// Result of a poll. A `pending` outcome covers both "still processing" and
/// "the API/network briefly failed" — in both cases the bank's OTP page must
/// stay visible and polling continues.
class CardPaymentCheck {
  const CardPaymentCheck(this.outcome, [this.terminalMessage]);

  final CardPaymentStatusResult outcome;

  /// Set for the terminal states (FAILED / EXPIRED / CANCELLED).
  final String? terminalMessage;
}

/// Security-critical state machine for the card-payment screen.
///
/// The hosted WebView only ever *suggests* a final state through the
/// `SoftCarCheckout` bridge. This controller enforces that the authenticated
/// `GET /payments/{transactionId}` response is the only source of truth:
/// - a COMPLETED bridge message merely triggers a re-check that must confirm
///   against the API before the screen can mark the payment done;
/// - a transient network failure is silently swallowed (`pending`) so it never
///   covers the OTP page;
/// - terminal gateway states surface a message and a retry.
class CardPaymentFlow {
  CardPaymentFlow({required this.fetchStatus});

  final Future<Map<String, dynamic>> Function(String transactionId) fetchStatus;

  bool _checking = false;
  bool _completed = false;
  String? _terminalMessage;

  bool get checking => _checking;
  bool get completed => _completed;
  String? get terminalMessage => _terminalMessage;

  static const _terminalStatuses = {'FAILED', 'EXPIRED', 'CANCELLED'};

  /// Runs one authenticated status check. Returns the outcome without ever
  /// treating a bridge signal or a network hiccup as proof of payment.
  Future<CardPaymentCheck> check(String transactionId) async {
    if (_checking) {
      return const CardPaymentCheck(CardPaymentStatusResult.pending);
    }
    if (_completed) {
      return const CardPaymentCheck(CardPaymentStatusResult.completed);
    }
    _checking = true;
    try {
      final result = await fetchStatus(transactionId);
      final payment =
          result['payment'] is Map
              ? Map<String, dynamic>.from(result['payment'] as Map)
              : <String, dynamic>{};
      final status = payment['status']?.toString().toUpperCase() ?? '';
      if (status == 'COMPLETED') {
        _completed = true;
        return const CardPaymentCheck(CardPaymentStatusResult.completed);
      }
      if (_terminalStatuses.contains(status)) {
        _terminalMessage =
            status == 'EXPIRED'
                ? 'The payment window expired. No payment was recorded.'
                : 'The bank did not complete this payment. No payment was recorded.';
        return CardPaymentCheck(
          CardPaymentStatusResult.terminal,
          _terminalMessage,
        );
      }
      return const CardPaymentCheck(CardPaymentStatusResult.pending);
    } on PassengerApiException {
      // A brief connection/API failure must never interrupt the bank page.
      // Polling and lifecycle checks will retry.
      return const CardPaymentCheck(CardPaymentStatusResult.pending);
    } finally {
      _checking = false;
    }
  }

  /// True when a bridge message announces a final state, so the screen can
  /// re-check against the authenticated API sooner than its polling interval.
  /// The bridge never, by itself, proves that a payment completed.
  bool shouldRecheck(String rawStatus) {
    final status = rawStatus.trim().toUpperCase();
    return status == 'COMPLETED' || status == 'FAILED';
  }
}
