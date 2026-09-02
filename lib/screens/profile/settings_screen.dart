import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';

/// App settings: theme, language, notifications, safety and account.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final locale = context.watch<LocaleController>();
    final auth = context.watch<AuthService>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isArabic = locale.isArabic;

    Widget switchTile({
      required IconData icon,
      required String title,
      String? subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return SwitchListTile(
        secondary: Icon(icon, size: 22),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
        value: value,
        activeTrackColor: AppColors.accent,
        onChanged: onChanged,
      );
    }

    Widget navTile({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) {
      return ListTile(
        leading: Icon(icon, size: 22),
        title:
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      );
    }

    Future<void> setNotifications({
      bool? push,
      bool? email,
      bool? sms,
    }) async {
      await auth.updateProfile(
        pushNotifications: push,
        emailNotifications: email,
        phoneNotifications: sms,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'settings'))),
      body: ListView(
        children: [
          _Section(L10n.t(context, 'language')),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ListTile(
                    leading: const Icon(Icons.language_outlined, size: 22),
                    title: Text(
                        isArabic ? 'العربية' : 'English (US)',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      L10n.t(context, 'language'),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.accent,
                      selectedForegroundColor: Colors.white,
                    ),
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('EN')),
                      ButtonSegment(value: 'ar', label: Text('AR')),
                    ],
                    selected: {locale.locale.languageCode},
                    onSelectionChanged: (s) {
                      locale.setLanguage(Locale(s.first));
                      if (auth.isLoggedIn) {
                        auth.updateProfile(
                            preferredLanguage:
                                s.first == 'ar' ? 'ar' : 'en');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _Section(L10n.t(context, 'appearance')),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: switchTile(
              icon: Icons.dark_mode_outlined,
              title: L10n.t(context, 'darkMode'),
              subtitle: L10n.t(context, 'darkModeSub'),
              value: theme.isDark,
              onChanged: (v) => theme.setDark(v),
            ),
          ),
          const SizedBox(height: 20),

          _Section(L10n.t(context, 'notifications')),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                switchTile(
                  icon: Icons.notifications_active_outlined,
                  title: L10n.t(context, 'pushNotifications'),
                  subtitle: L10n.t(context, 'pushNotificationsSub'),
                  value: auth.profile.pushNotifications,
                  onChanged: (v) => setNotifications(push: v),
                ),
                const Divider(height: 1, indent: 56),
                switchTile(
                  icon: Icons.email_outlined,
                  title: L10n.t(context, 'emailNotifications'),
                  value: auth.profile.emailNotifications,
                  onChanged: (v) => setNotifications(email: v),
                ),
                const Divider(height: 1, indent: 56),
                switchTile(
                  icon: Icons.sms_outlined,
                  title: L10n.t(context, 'smsNotifications'),
                  value: auth.profile.phoneNotifications,
                  onChanged: (v) => setNotifications(sms: v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _Section(L10n.t(context, 'support')),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                navTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: L10n.t(context, 'chat'),
                  onTap: () => Navigator.of(context).pushNamed('/support-chat'),
                ),
                const Divider(height: 1, indent: 56),
                navTile(
                  icon: Icons.confirmation_number_outlined,
                  title: L10n.t(context, 'ticketsSupport'),
                  onTap: () =>
                      Navigator.of(context).pushNamed('/support-tickets'),
                ),
                const Divider(height: 1, indent: 56),
                navTile(
                  icon: Icons.help_outline,
                  title: L10n.t(context, 'helpSupport'),
                  onTap: () => Navigator.of(context).pushNamed('/help'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(title,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.4)),
    );
  }
}
