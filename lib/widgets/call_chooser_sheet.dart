import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_colors.dart';
import '../services/voip_service.dart';

/// Bottom sheet offering the two ways to reach someone:
///  * Soft-Call — free in-app WebRTC call through [VoipService]
///  * regular carrier call via the masked/public [phone] number
///
/// Usage: `showCallChooser(context,
///   targetUserId: passenger.id, displayName: passenger.name,
///   phone: passenger.phone, tripId: trip.id);`
///
/// When [softCallOpensCallCenter] is true (help / hotline entries), the
/// Soft-Call option routes into the call-center IVR instead of dialing a
/// specific user.
Future<void> showCallChooser(
  BuildContext context, {
  required String targetUserId,
  required String displayName,
  String? phone,
  String? tripId,
  bool softCallOpensCallCenter = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _CallChooserSheet(
      targetUserId: targetUserId,
      displayName: displayName,
      phone: phone,
      tripId: tripId,
      softCallOpensCallCenter: softCallOpensCallCenter,
    ),
  );
}

class _CallChooserSheet extends StatelessWidget {
  final String targetUserId;
  final String displayName;
  final String? phone;
  final String? tripId;
  final bool softCallOpensCallCenter;

  const _CallChooserSheet({
    required this.targetUserId,
    required this.displayName,
    this.phone,
    this.tripId,
    this.softCallOpensCallCenter = false,
  });

  Future<void> _startSoftCall(BuildContext sheetContext) async {
    final nav = Navigator.of(sheetContext);
    final messenger = ScaffoldMessenger.maybeOf(sheetContext);
    final failedText = L10n.t(sheetContext, 'calls.callFailed');
    nav.pop();
    if (softCallOpensCallCenter) {
      nav.pushNamed('/call-center');
      return;
    }
    try {
      await VoipService.instance.createDirectCall(
        targetUserId,
        tripId: tripId,
        reason: 'Direct contact',
      );
      nav.pushNamed('/active-call');
    } catch (_) {
      messenger?.showSnackBar(SnackBar(
        content: Text(failedText),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _startPhoneCall() async {
    if (phone == null || phone!.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone!.trim());
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone != null && phone!.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              L10n.t(context, 'calls.chooseHow'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              displayName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            _OptionTile(
              icon: Icons.wifi_calling_3_rounded,
              iconColor: AppColors.success,
              containerColor: AppColors.success.withValues(alpha: 0.1),
              title: L10n.t(context, 'calls.softCall'),
              subtitle: L10n.t(context, 'calls.softCallSub'),
              badge: L10n.t(context, 'calls.freeBadge'),
              onTap: () => _startSoftCall(context),
            ),
            if (hasPhone) ...[
              const SizedBox(height: 12),
              _OptionTile(
                icon: Icons.phone_rounded,
                iconColor: AppColors.accent,
                containerColor: AppColors.accentSoft,
                title: L10n.t(context, 'calls.phoneCall'),
                subtitle: phone!,
                onTap: _startPhoneCall,
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color containerColor;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.iconColor,
    required this.containerColor,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: containerColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 15, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
