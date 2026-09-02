import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softcar_passengers/models/shuttle.dart';
import 'package:softcar_passengers/services/card_checkout.dart';
import 'package:softcar_passengers/services/passenger_api.dart';

void main() {
  group('CardCheckout.fetchSession', () {
    test('accepts a validated transaction id + https checkout url', () async {
      final session = await CardCheckout.fetchSession(
        'res_1',
        createSession:
            (_) async => {
              'transactionId': 'pay_1',
              'checkoutUrl':
                  'https://softcarshuttle.com/payments/cybersource/checkout/token',
            },
      );

      expect(session.transactionId, 'pay_1');
      expect(session.checkoutUrl, contains('/checkout/token'));
    });

    test('rejects a session without a transaction id', () async {
      await expectLater(
        CardCheckout.fetchSession(
          'res_1',
          createSession:
              (_) async => {
                'checkoutUrl': 'https://softcarshuttle.com/payments/1',
              },
        ),
        throwsA(
          isA<PassengerApiException>().having(
            (e) => e.message,
            'message',
            contains('secure checkout link'),
          ),
        ),
      );
    });

    test('rejects an empty checkout url', () async {
      await expectLater(
        CardCheckout.fetchSession(
          'res_1',
          createSession: (_) async => {'transactionId': 'pay_1'},
        ),
        throwsA(isA<PassengerApiException>()),
      );
    });

    test('rejects a non-https checkout url', () async {
      await expectLater(
        CardCheckout.fetchSession(
          'res_1',
          createSession:
              (_) async => {
                'transactionId': 'pay_1',
                'checkoutUrl': 'http://softcarshuttle.com/payments/1',
              },
        ),
        throwsA(
          isA<PassengerApiException>().having(
            (e) => e.message,
            'message',
            contains('insecure checkout link'),
          ),
        ),
      );
    });

    test('rejects a malformed checkout url', () async {
      await expectLater(
        CardCheckout.fetchSession(
          'res_1',
          createSession:
              (_) async => {
                'transactionId': 'pay_1',
                'checkoutUrl': '://not-a-url',
              },
        ),
        throwsA(isA<PassengerApiException>()),
      );
    });
  });

  group('CardCheckout.push', () {
    testWidgets('pushes the built screen with the validated session', (
      tester,
    ) async {
      final ticket = Ticket.fromJson({
        'id': 'res_1',
        'ticketCode': 'SCS-TEST-0001',
        'pickupPoint': {'id': 'p1', 'name': 'Downtown'},
        'dropoffPoint': {'id': 'p2', 'name': 'Airport'},
        'trip': {
          'id': 'tr1',
          'title': 'Downtown \u2192 Airport',
          'mainDestination': 'Airport',
          'startTime': '2026-08-10T09:00:00Z',
          'serviceClassCode': 'ECONOMY_COASTER',
          'pickupPoints': <Map<String, dynamic>>[],
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => Center(
                    child: TextButton(
                      onPressed:
                          () => CardCheckout.push(
                            context,
                            ticket: ticket,
                            session: const CardCheckoutSession(
                              transactionId: 'pay_1',
                              checkoutUrl:
                                  'https://example.test/checkout/token',
                            ),
                            buildScreen:
                                (t, s) => Text('screen:${s.transactionId}'),
                          ),
                      child: const Text('go'),
                    ),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('screen:pay_1'), findsOneWidget);
    });
  });
}
