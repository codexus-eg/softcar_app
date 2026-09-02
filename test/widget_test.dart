// Basic smoke tests for the SoftCar passenger app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:softcar_passengers/app.dart';
import 'package:softcar_passengers/services/storage_service.dart';

void main() {
  testWidgets('Splash screen renders the SoftCar brand mark', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(SoftCarApp(
      storage: StorageService(),
      initialLocale: const Locale('en'),
      initialDark: false,
    ));
    await tester.pump();

    expect(find.byType(Image), findsWidgets); // brand logo image
    expect(find.text('Soft'), findsOneWidget);
    expect(find.text('Car'), findsOneWidget);

    // Let the splash boot navigate so no timers are left pending.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}