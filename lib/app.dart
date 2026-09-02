import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/app_nav.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/help/help_screen.dart';
import 'screens/help/support_chat_screen.dart';
import 'screens/help/support_tickets_screen.dart';
import 'screens/home/event_detail_screen.dart';
import 'screens/home/tier_detail_screen.dart';
import 'screens/legal/legal_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/settings_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/search/trip_details_screen.dart';
import 'screens/search/whereto_screen.dart';
import 'screens/shuttle/booking_success_screen.dart';
import 'screens/shuttle/change_trip_day_screen.dart';
import 'screens/shuttle/live_tracking_screen.dart';
import 'screens/shuttle/my_bookings_screen.dart';
import 'screens/shuttle/seat_selection_screen.dart';
import 'screens/shuttle/ticket_detail_screen.dart';
import 'screens/shuttle/ticket_screen.dart';
import 'screens/shuttle/boarding_confirmation_screen.dart';
import 'screens/calls/active_call_screen.dart';
import 'screens/calls/call_center_screen.dart';
import 'screens/calls/incoming_call_screen.dart';
import 'screens/support/support_call_screen.dart';
import 'screens/shell/main_shell.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/wallet/wallet_recharge_screen.dart';
import 'screens/wallet/wallet_screen.dart';
import 'screens/wallet/vouchers_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/reservation_service.dart';
import 'services/shuttle_service.dart';
import 'services/storage_service.dart';
import 'services/support_service.dart';
import 'services/voucher_service.dart';
import 'services/wallet_service.dart';

/// Root widget: wires all app-wide services into the widget tree.
class SoftCarApp extends StatefulWidget {
  final StorageService storage;
  final bool initialDark;
  final Locale initialLocale;

  const SoftCarApp({
    super.key,
    required this.storage,
    required this.initialDark,
    required this.initialLocale,
  });

  @override
  State<SoftCarApp> createState() => _SoftCarAppState();
}

class _SoftCarAppState extends State<SoftCarApp> {
  late bool _dark = widget.initialDark;
  late Locale _locale = widget.initialLocale;

  void _onThemeChanged(bool dark) => setState(() => _dark = dark);

  void _onLocaleChanged(Locale locale) => setState(() => _locale = locale);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: widget.storage),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ShuttleService()),
        ChangeNotifierProvider(create: (_) => ReservationService()),
        ChangeNotifierProvider(create: (_) => WalletService()),
        ChangeNotifierProvider(create: (_) => SupportService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(create: (_) => VoucherService()),
        ChangeNotifierProvider<ThemeController>(
          create:
              (_) => ThemeController(
                initialDark: _dark,
                storage: widget.storage,
                onChanged: _onThemeChanged,
              ),
        ),
        ChangeNotifierProvider<LocaleController>(
          create:
              (_) => LocaleController(
                initialLocale: _locale,
                storage: widget.storage,
                onChanged: _onLocaleChanged,
              ),
        ),
      ],
      child: Consumer2<ThemeController, LocaleController>(
        builder: (context, theme, locale, _) {
          return MaterialApp(
            title: 'SoftCar-Fleet',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: theme.isDark ? ThemeMode.dark : ThemeMode.light,
            locale: locale.locale,
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SplashScreen(),
            routes: _buildRoutes(),
            navigatorKey: AppNav.key,
          );
        },
      ),
    );
  }
}

Map<String, WidgetBuilder> _buildRoutes() {
  return {
    '/splash': (_) => const SplashScreen(),
    '/onboarding': (_) => const OnboardingScreen(),
    '/auth': (_) => const AuthScreen(),
    '/forgot-password': (_) => const ForgotPasswordScreen(),
    '/search': (_) => const SearchScreen(),
    '/whereto': (_) => const WhereToScreen(),
    '/event-detail': (_) => const EventDetailScreen(),
    '/trip-details': (_) => const TripDetailsScreen(),
    '/tier-detail': (_) => const TierDetailScreen(),
    '/legal': (_) => const LegalScreen(),
    '/wallet-recharge': (_) => const WalletRechargeScreen(),
    '/home': (_) => const MainShell(),
    '/seat-selection': (_) => const SeatSelectionScreen(),
    '/ticket': (_) => const TicketScreen(),
    '/ticket-detail': (_) => const TicketDetailScreen(),
    '/boarding-confirmation': (_) => const BoardingConfirmationScreen(),
    '/change-trip-day': (_) => const ChangeTripDayScreen(),
    '/booking-success': (_) => const BookingSuccessScreen(),
    '/live-tracking': (_) => const LiveTrackingScreen(),
    '/my-bookings': (_) => const MyBookingsScreen(),
    '/wallet': (_) => const WalletScreen(),
    '/vouchers': (_) => const VouchersScreen(),
    '/profile': (_) => const ProfileScreen(),
    '/notifications': (_) => const NotificationsScreen(),
    '/settings': (_) => const SettingsScreen(),
    '/help': (_) => const HelpScreen(),
    '/call-center': (_) => const CallCenterScreen(),
    '/incoming-call': (_) => const IncomingCallScreen(),
    '/active-call': (_) => const ActiveCallScreen(),
    '/support-call': (_) => const SupportCallScreen(),
    '/support-chat': (_) => const SupportChatScreen(),
    '/support-tickets': (_) => const SupportTicketsScreen(),
  };
}

/// Simple controller so the settings screen can flip dark mode globally.
class ThemeController extends ChangeNotifier {
  ThemeController({
    required bool initialDark,
    required this.storage,
    required this.onChanged,
  }) : _isDark = initialDark;

  final StorageService storage;
  final ValueChanged<bool> onChanged;
  bool _isDark;

  bool get isDark => _isDark;

  Future<void> setDark(bool value) async {
    _isDark = value;
    onChanged(value);
    notifyListeners();
    await storage.setDarkMode(value);
  }
}

/// Controls the app language (English / Arabic) and persists the choice so
/// the next launch starts in the same language.
class LocaleController extends ChangeNotifier {
  LocaleController({
    required Locale initialLocale,
    required this.storage,
    required this.onChanged,
  }) : _locale = initialLocale;

  final StorageService storage;
  final ValueChanged<Locale> onChanged;
  Locale _locale;

  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  Future<void> setLanguage(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    onChanged(locale);
    notifyListeners();
    await storage.setLanguage(locale.languageCode);
  }
}
