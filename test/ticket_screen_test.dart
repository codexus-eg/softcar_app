import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:softcar_passengers/models/shuttle.dart';
import 'package:softcar_passengers/screens/shuttle/ticket_detail_screen.dart';
import 'package:softcar_passengers/screens/shuttle/ticket_screen.dart';
import 'package:softcar_passengers/services/auth_service.dart';
import 'package:softcar_passengers/widgets/board_pass_qr.dart';

Ticket _ticket(String status, {String method = 'CARD'}) {
  return Ticket.fromJson({
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
    'totalPrice': 114.0,
    'paymentMethod': method,
    'paymentStatus': status,
    'status': 'RESERVED',
    'reservedAt': '2026-08-10T08:00:00Z',
  });
}

Future<void> _pumpTicket(
  WidgetTester tester,
  Widget screen,
  Ticket ticket,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthService>.value(
      value: AuthService(),
      child: MaterialApp(
        home: Builder(
          builder:
              (context) => Center(
                child: TextButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          settings: RouteSettings(arguments: ticket),
                          builder: (_) => screen,
                        ),
                      ),
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('TicketScreen', () {
    testWidgets('hides the boarding QR for an unpaid card reservation', (
      tester,
    ) async {
      await _pumpTicket(
        tester,
        const TicketScreen(),
        _ticket('PENDING_PAYMENT'),
      );

      expect(find.byType(BoardPassQr), findsNothing);
      expect(find.text('SCS-TEST-0001'), findsNothing);
      expect(find.text('Continue card payment'), findsOneWidget);
      expect(find.text('Payment pending'), findsOneWidget);
    });

    testWidgets('shows the boarding QR once the card payment is paid', (
      tester,
    ) async {
      await _pumpTicket(tester, const TicketScreen(), _ticket('PAID'));

      expect(find.byType(BoardPassQr), findsOneWidget);
      expect(find.text('SCS-TEST-0001'), findsWidgets);
      expect(find.text('Continue card payment'), findsNothing);
      expect(find.text('Payment pending'), findsNothing);
    });
  });

  group('TicketDetailScreen', () {
    testWidgets('gates the QR with a payment CTA for an unpaid card', (
      tester,
    ) async {
      await _pumpTicket(
        tester,
        const TicketDetailScreen(),
        _ticket('PENDING_CARD_CHECKOUT'),
      );

      expect(find.byType(BoardPassQr), findsNothing);
      expect(find.text('Continue card payment'), findsWidgets);
      expect(find.text('Payment pending'), findsOneWidget);
    });

    testWidgets('shows the QR for a paid card reservation', (tester) async {
      await _pumpTicket(
        tester,
        const TicketDetailScreen(),
        _ticket('AUTHORIZED'),
      );

      expect(find.byType(BoardPassQr), findsOneWidget);
      expect(find.text('SCS-TEST-0001'), findsWidgets);
      expect(find.text('Continue card payment'), findsNothing);
      expect(find.text('Payment pending'), findsNothing);
    });
  });
}
