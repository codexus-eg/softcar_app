import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/utils/app_nav.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';

/// Boot screen: restores the live session and the saved language, then sends
/// the user to the home shell (signed in), the auth screen (onboarded, not
/// signed in) or the onboarding flow for first-time users.
///
/// Layout is a full-bleed photo splash: the uploaded splash image is shown
/// edge-to-edge filling the whole screen (BoxFit.cover), so it adapts to any
/// device aspect ratio. No logo, wordmark, or frames are drawn on top.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final auth = context.read<AuthService>();
    final storage = context.read<StorageService>();
    final locale = context.read<LocaleController>();
    final theme = context.read<ThemeController>();

    var storedLang = 'en';
    var onboarded = false;
    var darkMode = false;
    try {
      final values = await Future.wait<Object?>(<Future<Object?>>[
        auth.bootstrap().then<Object?>((_) => null),
        storage.getLanguage(),
        storage.isOnboarded(),
        storage.getDarkMode(),
      ]).timeout(
        const Duration(seconds: 5),
        onTimeout: () => <Object?>[null, 'en', false, false],
      );
      storedLang = values[1] as String? ?? 'en';
      onboarded = values[2] as bool? ?? false;
      darkMode = values[3] as bool? ?? false;
    } catch (_) {
      // A damaged/temporarily unavailable platform store must never trap the
      // passenger on the splash screen. Defaults safely open onboarding.
    }

    if (!mounted) return;
    if (storedLang == 'ar') {
      await locale.setLanguage(const Locale('ar'));
    }
    if (!mounted) return;
    if (darkMode != theme.isDark) {
      await theme.setDark(darkMode);
    }
    if (!mounted) return;

    if (auth.isLoggedIn) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } else if (onboarded) {
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil('/onboarding', (_) => false);
    }
    // Splash redirect is done: any notification tap buffered during a
    // cold start can now safely land on its target screen.
    AppNav.splashFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        child: Image.asset(
          'assets/splash/splash_screen.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
