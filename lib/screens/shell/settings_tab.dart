import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../models/shuttle.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/reservation_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/common_widgets.dart';

/// Settings tab: the passenger's home base for their account. Tapping the
/// profile card opens the full editable profile (personal info, saved Home /
/// Work places, referral code); the menu below reaches tickets, vouchers,
/// notifications, preferences and support.
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final reservations = context.watch<ReservationService>();
    final wallet = context.watch<WalletService>();
    final profile = auth.isLoggedIn ? auth.profile : const UserProfile();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            L10n.t(context, 'settings'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          _ProfileCard(
            profile: profile,
            signedIn: auth.isLoggedIn,
            onTap: () => Navigator.of(context).pushNamed('/profile'),
          ),
          const SizedBox(height: 20),
          if (auth.isLoggedIn) ...[
            Row(
              children: [
                Expanded(
                  child: _StatRow(
                    icon: Icons.confirmation_number_outlined,
                    label: L10n.t(context, 'upcomingTickets'),
                    value: '${reservations.upcoming.length}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: L10n.t(context, 'walletBalance'),
                    value:
                        '${wallet.data.currency.isEmpty ? 'EGP' : wallet.data.currency} '
                        '${wallet.data.balance.toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionLabel(L10n.t(context, 'account')),
            _MenuTile(
              icon: Icons.person_outline_rounded,
              label: L10n.t(context, 'profile'),
              onTap: () => Navigator.of(context).pushNamed('/profile'),
            ),
            _MenuTile(
              icon: Icons.location_on_outlined,
              label: L10n.t(context, 'savedPlacesTitle'),
              onTap: () => Navigator.of(context).pushNamed('/profile'),
            ),
            _MenuTile(
              icon: Icons.card_giftcard_rounded,
              label: L10n.t(context, 'referralCode'),
              onTap: () => Navigator.of(context).pushNamed('/profile'),
            ),
            _MenuTile(
              icon: Icons.confirmation_number_outlined,
              label: L10n.t(context, 'myTickets'),
              onTap: () => Navigator.of(context).pushNamed('/my-bookings'),
            ),
            const SizedBox(height: 12),
            _SectionLabel(L10n.t(context, 'preferences')),
            _MenuTile(
              icon: Icons.confirmation_number_outlined,
              label: L10n.t(context, 'vouchers'),
              onTap: () => Navigator.of(context).pushNamed('/vouchers'),
            ),
            _MenuTile(
              icon: Icons.notifications_none_rounded,
              label: L10n.t(context, 'notifications'),
              onTap: () => Navigator.of(context).pushNamed('/notifications'),
            ),
            _MenuTile(
              icon: Icons.settings_outlined,
              label: L10n.t(context, 'appearance'),
              onTap: () => Navigator.of(context).pushNamed('/settings'),
            ),
            _MenuTile(
              icon: Icons.tune_rounded,
              label: L10n.t(context, 'helpSupport'),
              onTap: () => Navigator.of(context).pushNamed('/help'),
            ),
            _MenuTile(
              icon: Icons.headset_mic_outlined,
              label: L10n.t(context, 'contactSupport'),
              onTap: () => Navigator.of(context).pushNamed('/call-center'),
            ),
            _MenuTile(
              icon: Icons.description_outlined,
              label: L10n.t(context, 'termsPolicies'),
              onTap: () => Navigator.of(context).pushNamed('/legal'),
            ),
            const SizedBox(height: 12),
            _MenuTile(
              icon: Icons.logout_rounded,
              label: L10n.t(context, 'signOut'),
              destructive: true,
              onTap: () async {
                await auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                      '/onboarding', (_) => false);
                }
              },
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: () => _confirmDeleteAccount(context, auth),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  backgroundColor: AppColors.error.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.delete_forever_outlined, size: 20),
                label: Text(
                  L10n.t(context, 'deleteAccount'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'v1.0.0 · ${L10n.t(context, 'signedInWith')}',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ),
          ] else ...[
            _MenuTile(
              icon: Icons.help_outline_rounded,
              label: L10n.t(context, 'helpSupport'),
              onTap: () => Navigator.of(context).pushNamed('/help'),
            ),
            _MenuTile(
              icon: Icons.description_outlined,
              label: L10n.t(context, 'termsPolicies'),
              onTap: () => Navigator.of(context).pushNamed('/legal'),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, AuthService auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'deleteAccountConfirmTitle')),
        content: Text(L10n.t(ctx, 'deleteAccountConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final err = await auth.deleteAccount();
              if (!context.mounted) return;
              if (err == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(L10n.t(context, 'accountDeleted'))));
                Navigator.of(context).pushNamedAndRemoveUntil(
                    '/onboarding', (_) => false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err)));
              }
            },
            child: Text(L10n.t(ctx, 'delete')),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.signedIn,
    required this.onTap,
  });

  final UserProfile profile;
  final bool signedIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gender = profile.gender;
    final genderColor =
        GenderColor.forGender(gender, fallback: AppColors.accent);
    final initials = profile.name.isEmpty
        ? '?'
        : profile.name
              .split(' ')
              .where((w) => w.isNotEmpty)
              .take(2)
              .map((w) => w[0])
              .join()
              .toUpperCase();
    final imageUrl = profile.image;

    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.surfaceDarkElevated
          : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: genderColor,
                  borderRadius: BorderRadius.circular(18),
                  image: imageUrl != null && imageUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(
                              'https://softcarshuttle.com$imageUrl'),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: imageUrl == null || imageUrl.isEmpty
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signedIn && profile.name.isNotEmpty
                          ? profile.name
                          : L10n.t(context, 'hello'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      signedIn
                          ? (profile.email ?? profile.phone ?? '—')
                          : L10n.t(context, 'signInForProfile'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  const _MenuTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = destructive
        ? AppColors.error
        : isDark
            ? Colors.white
            : AppColors.textPrimary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 19, color: destructive ? AppColors.error : color),
      ),
      title: Text(label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: destructive ? AppColors.error : color,
          )),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }
}