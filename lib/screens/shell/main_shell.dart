import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../services/ads_service.dart';
import '../../services/auth_service.dart';
import '../../services/reservation_service.dart';
import '../../services/shuttle_service.dart';
import '../../services/storage_service.dart';
import '../../services/voucher_service.dart';
import '../../services/wallet_service.dart';
import '../../services/notification_service.dart';
import '../../services/passenger_api.dart';
import '../../services/soft_call_bootstrap.dart';
import '../../widgets/focus_event_overlay.dart';
import '../../widgets/forced_notification_overlay.dart';
import '../../widgets/voucher_overlay.dart';
import 'home_tab.dart';
import 'tickets_tab.dart';
import 'wallet_tab.dart';
import 'settings_tab.dart';

/// The authenticated app shell: a floating rounded bottom bar with the four
/// core destinations — Reservations (shuttle + Where-to), Tickets (live
/// reservations), Wallet and Settings (profile & account). Every tab is
/// backed by the live production API.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prime();
      context.read<NotificationService>().addForcedListener(_onForcedNotification);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Revive the SoftBase realtime stream if the OS dropped the socket
    // while the app was backgrounded.
    if (state == AppLifecycleState.resumed) {
      SoftCallBootstrap.connect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    context.read<NotificationService>().removeForcedListener(_onForcedNotification);
    super.dispose();
  }

  /// Handles a newly-arrived focused notification: plays the loud system
  /// sound and forces the in-app overlay on top of whatever screen the
  /// passenger is on. The overlay can only be dismissed with the X button.
  void _onForcedNotification(Map<String, dynamic> notification) {
    if (!mounted) return;
    final title = notification['title']?.toString() ?? '';
    final message = notification['message']?.toString() ?? '';
    if (title.isEmpty && message.isEmpty) return;
    showForcedNotificationOverlay(
      context,
      title: title,
      message: message,
      actionLabel: L10n.t(context, 'open'),
    ).then((action) {
      if (!mounted) return;
      if (notification['type']?.toString().contains('CONFIRMATION') == true) {
        _maybeShowBoardingConfirmation();
      }
      if (action != true) return;
      Navigator.of(context).pushNamed('/notifications');
    });
  }

  Future<void> _prime() async {
    final auth = context.read<AuthService>();
    // If a persisted session was revoked (401) underneath, drop to sign-in
    // instead of painting an empty, unusable shell.
    if (!auth.isLoggedIn) {
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/onboarding', (_) => false);
      }
      return;
    }
    final shuttle = context.read<ShuttleService>();
    final reservations = context.read<ReservationService>();
    final wallet = context.read<WalletService>();
    final notifications = context.read<NotificationService>();
    await Future.wait([
      shuttle.syncLive(),
      reservations.syncFromLive(),
      wallet.refresh(),
      notifications.refresh(),
    ]);
    if (!mounted) return;
    _maybeShowBoardingConfirmation();
    _maybeShowVoucher(
      context.read<VoucherService>(),
      context.read<StorageService>(),
    );
    _maybeShowFocusEvent(context.read<StorageService>());
  }

  /// The driver may be waiting for the passenger to confirm a boarding or
  /// cash action. When there is a pending confirmation, force the dedicated
  /// confirmation screen on top so the passenger can answer it.
  Future<void> _maybeShowBoardingConfirmation() async {
    try {
      final rows = await passengerApi.getPendingConfirmations();
      if (!mounted || rows.isEmpty) return;
      Navigator.of(context).pushNamed('/boarding-confirmation');
    } catch (_) {
      // Never block the home shell if the confirmation poll fails.
    }
  }

  /// Fetches the configured "focused event" ad once the home has loaded and,
  /// if the passenger hasn't seen it yet, shows the forced event overlay.
  /// Seen ad ids are persisted so each focused event only pops once.
  Future<void> _maybeShowFocusEvent(StorageService storage) async {
    try {
      final raw = await passengerApi.getFocusedAd();
      if (!mounted || raw == null) return;
      final ad = AdItem.fromJson(raw);
      if (ad.id.isEmpty) return;
      final seen = await storage.getSeenFocusAds();
      if (!mounted || seen.contains(ad.id)) return;
      final action = await showFocusEventOverlay(context, ad);
      if (!mounted) return;
      await storage.markFocusAdSeen(ad.id);
      if (!mounted) return;
      if (action == true) {
        Navigator.of(context).pushNamed('/event-detail', arguments: ad);
      }
    } catch (_) {
      // Never break the home shell if the focused-ad fetch fails.
    }
  }

  /// Fetches the active vouchers once the home has loaded and, if there is a
  /// voucher this passenger hasn't seen yet, shows the first-open promo
  /// overlay. Seen codes are persisted so each voucher only pops once.
  Future<void> _maybeShowVoucher(
    VoucherService vouchers,
    StorageService storage,
  ) async {
    await vouchers.loadActive();
    if (!mounted || vouchers.vouchers.isEmpty) return;
    final seen = await storage.getSeenVouchers();
    if (!mounted) return;
    Map<String, dynamic>? first;
    for (final v in vouchers.vouchers) {
      final code = v['code']?.toString() ?? '';
      if (code.isEmpty || seen.contains(code)) continue;
      first = v;
      break;
    }
    final voucher = first;
    if (voucher == null) return;
    final code = voucher['code']?.toString() ?? '';
    final action = await showVoucherOverlay(context, voucher);
    if (!mounted) return;
    if (code.isNotEmpty) await storage.markVoucherSeen(code);
    if (!mounted) return;
    if (action == 'apply') {
      context.read<VoucherService>().pendingCode = code;
      Navigator.of(context).pushNamed('/search');
    }
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = context.select<ReservationService, int>(
      (s) => s.upcoming.length,
    );

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeTab(),
          TicketsTab(),
          WalletTab(),
          SettingsTab(),
        ],
      ),
      // Floating, soft-corner bottom bar with a subtle top shadow.
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color:
              Theme.of(context).brightness == Brightness.dark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.directions_bus_filled_rounded,
                  label: L10n.t(context, 'reservations'),
                  badge: upcoming,
                  selected: _index == 0,
                  onTap: () => _switchTo(0),
                ),
                _NavItem(
                  icon: Icons.confirmation_number_outlined,
                  label: L10n.t(context, 'tickets'),
                  selected: _index == 1,
                  onTap: () => _switchTo(1),
                ),
                _NavItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: L10n.t(context, 'wallet'),
                  selected: _index == 2,
                  onTap: () => _switchTo(2),
                ),
                _NavItem(
                  icon: Icons.settings_outlined,
                  label: L10n.t(context, 'settings'),
                  selected: _index == 3,
                  onTap: () => _switchTo(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _switchTo(int i) {
    if (_index == i) return;
    setState(() => _index = i);
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        selected
            ? Colors.white
            : Theme.of(context).brightness == Brightness.dark
            ? Colors.white54
            : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow:
                selected
                    ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                    : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 22, color: color),
                  if (badge > 0)
                    Positioned(
                      right: -7,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        constraints: const BoxConstraints(
                          minWidth: 15,
                          minHeight: 15,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: AppColors.accent, width: 1.4),
                          ),
                        ),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
