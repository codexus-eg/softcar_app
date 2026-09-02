import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:softcar_passengers/screens/shuttle/card_payment_flow.dart';
import 'package:softcar_passengers/services/passenger_api.dart';

void main() {
  group('CardPaymentFlow', () {
    test('marks completed only when the API confirms COMPLETED', () async {
      final flow = CardPaymentFlow(
        fetchStatus:
            (_) async => {
              'payment': {'id': 'TX1', 'status': 'COMPLETED'},
            },
      );

      final result = await flow.check('TX1');

      expect(result.outcome, CardPaymentStatusResult.completed);
      expect(flow.completed, isTrue);
      expect(flow.terminalMessage, isNull);
    });

    test('an in-flight attempt returns pending', () async {
      final flow = CardPaymentFlow(
        fetchStatus:
            (_) async => {
              'payment': {'status': 'PENDING_CHECKOUT'},
            },
      );

      final result = await flow.check('TX1');

      expect(result.outcome, CardPaymentStatusResult.pending);
      expect(flow.completed, isFalse);
    });

    test(
      'a transient API failure stays pending and never marks terminal',
      () async {
        final flow = CardPaymentFlow(
          fetchStatus:
              (_) async => throw const PassengerApiException('offline'),
        );

        final result = await flow.check('TX1');

        expect(result.outcome, CardPaymentStatusResult.pending);
        expect(flow.completed, isFalse);
        expect(flow.terminalMessage, isNull);
      },
    );

    test('FAILED surfaces a terminal message', () async {
      final flow = CardPaymentFlow(
        fetchStatus:
            (_) async => {
              'payment': {'status': 'FAILED'},
            },
      );

      final result = await flow.check('TX1');

      expect(result.outcome, CardPaymentStatusResult.terminal);
      expect(flow.terminalMessage, contains('did not complete'));
    });

    test('EXPIRED surfaces the window-expired message', () async {
      final flow = CardPaymentFlow(
        fetchStatus:
            (_) async => {
              'payment': {'status': 'EXPIRED'},
            },
      );

      final result = await flow.check('TX1');

      expect(result.outcome, CardPaymentStatusResult.terminal);
      expect(flow.terminalMessage, contains('window expired'));
    });

    test('CANCELLED is terminal like the other gateway endings', () async {
      final flow = CardPaymentFlow(
        fetchStatus:
            (_) async => {
              'payment': {'status': 'CANCELLED'},
            },
      );

      final result = await flow.check('TX1');

      expect(result.outcome, CardPaymentStatusResult.terminal);
      expect(flow.terminalMessage, isNotNull);
    });

    test(
      'a COMPLETED bridge suggestion is re-verified against the API',
      () async {
        final flow = CardPaymentFlow(
          fetchStatus:
              (_) async => {
                'payment': {'status': 'PENDING_CHECKOUT'},
              },
        );

        expect(flow.shouldRecheck('COMPLETED'), isTrue);

        final result = await flow.check('TX1');

        expect(result.outcome, CardPaymentStatusResult.pending);
        expect(flow.completed, isFalse);
      },
    );

    test('only COMPLETED and FAILED bridge messages trigger a re-check', () {
      final flow = CardPaymentFlow(fetchStatus: (_) async => const {});

      expect(flow.shouldRecheck('COMPLETED'), isTrue);
      expect(flow.shouldRecheck('failed'), isTrue);
      expect(flow.shouldRecheck('EXPIRED'), isFalse);
      expect(flow.shouldRecheck('pending'), isFalse);
      expect(flow.shouldRecheck(''), isFalse);
    });

    test('concurrent polls collapse to a single API round trip', () async {
      final calls = <String>[];
      final gate = Completer<void>();
      final flow = CardPaymentFlow(
        fetchStatus: (id) {
          calls.add(id);
          return gate.future.then(
            (_) => {
              'payment': {'status': 'PENDING'},
            },
          );
        },
      );

      final first = flow.check('TX1');
      final second = await flow.check('TX1');

      expect(second.outcome, CardPaymentStatusResult.pending);
      gate.complete();
      expect((await first).outcome, CardPaymentStatusResult.pending);
      expect(calls, ['TX1']);
    });

    test('a missing payment map is reported as pending, not a crash', () async {
      final flow = CardPaymentFlow(
        fetchStatus: (_) async => {'somethingElse': true},
      );

      final result = await flow.check('TX1');

      expect(result.outcome, CardPaymentStatusResult.pending);
      expect(flow.completed, isFalse);
    });

    test('a COMPLETED payment stays completed for every later poll', () async {
      final flow = CardPaymentFlow(
        fetchStatus:
            (_) async => {
              'payment': {'status': 'COMPLETED'},
            },
      );

      await flow.check('TX1');
      final again = await flow.check('TX1');

      expect(again.outcome, CardPaymentStatusResult.completed);
      expect(flow.completed, isTrue);
    });
  });
}
