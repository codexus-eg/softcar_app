import 'package:flutter/material.dart';

import '../../models/shuttle.dart';
import '../screens/shuttle/card_payment_screen.dart';
import 'passenger_api.dart';

/// A checkout the backend authenticated and created for this passenger.
class CardCheckoutSession {
  const CardCheckoutSession({
    required this.transactionId,
    required this.checkoutUrl,
  });

  final String transactionId;
  final String checkoutUrl;
}

/// Creates, validates and launches the hosted Cybersource checkout.
///
/// Shared by the reserve flow and the ticket "Continue card payment" flow so
/// that every entry point enforces the same invariants: a non-empty opaque
/// transaction id and an HTTPS checkout URL. Never hand an invalid or insecure
/// link to the WebView.
class CardCheckout {
  const CardCheckout._();

  static Future<Map<String, dynamic>> _defaultCreateSession(
    String reservationId,
  ) => passengerApi.createCardPaymentSession(reservationId);

  /// Calls [createSession] and validates its response. Throws
  /// [PassengerApiException] when the backend does not confirm a valid
  /// checkout instead of returning an unverified link to the caller.
  static Future<CardCheckoutSession> fetchSession(
    String reservationId, {
    Future<Map<String, dynamic>> Function(String reservationId)? createSession,
  }) async {
    final create = createSession ?? _defaultCreateSession;
    final payment = await create(reservationId);
    final transactionId = payment['transactionId']?.toString().trim() ?? '';
    final checkoutUrl = payment['checkoutUrl']?.toString().trim() ?? '';
    if (transactionId.isEmpty || checkoutUrl.isEmpty) {
      throw const PassengerApiException(
        'The bank did not return a secure checkout link.',
      );
    }
    final uri = Uri.tryParse(checkoutUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const PassengerApiException(
        'The bank returned an insecure checkout link.',
      );
    }
    return CardCheckoutSession(
      transactionId: transactionId,
      checkoutUrl: checkoutUrl,
    );
  }

  /// Pushes the hosted card-payment screen for a validated [session].
  /// [buildScreen] is injectable for tests so the WebView never needs to load
  /// in a widget test.
  static Future<void> push(
    BuildContext context, {
    required Ticket ticket,
    required CardCheckoutSession session,
    Widget Function(Ticket ticket, CardCheckoutSession session)? buildScreen,
  }) {
    final screen =
        buildScreen?.call(ticket, session) ??
        CardPaymentScreen(
          ticket: ticket,
          transactionId: session.transactionId,
          checkoutUrl: session.checkoutUrl,
        );
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}
