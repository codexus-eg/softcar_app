import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/call_chooser_sheet.dart';

/// Help & support center with a contact banner and FAQ accordions.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _open;

  List<(String, String)> _faqs(BuildContext context) => [
        (L10n.t(context, 'faqHow'), L10n.t(context, 'faqHowA')),
        (L10n.t(context, 'faqVehicles'), L10n.t(context, 'faqVehiclesA')),
        (L10n.t(context, 'faqFare'), L10n.t(context, 'faqFareA')),
        (L10n.t(context, 'faqSeats'), L10n.t(context, 'faqSeatsA')),
        (L10n.t(context, 'faqPay'), L10n.t(context, 'faqPayA')),
      ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final faqs = _faqs(context);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'helpTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Contact banner -----------------------------------------------------
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF10B981)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.support_agent, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Text(L10n.t(context, 'helpWeAreHere'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.t(context, 'helpBanner'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ContactButton(
                        icon: Icons.chat_bubble_outline,
                        label: L10n.t(context, 'chat'),
                        onTap: () => Navigator.of(context)
                            .pushNamed('/support-chat'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ContactButton(
                        icon: Icons.phone_outlined,
                        label: L10n.t(context, 'call'),
                        onTap: () => _callSupport(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(L10n.t(context, 'faq'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),

          for (var i = 0; i < faqs.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: dark
                    ? AppColors.surfaceDarkElevated
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  onExpansionChanged: (open) =>
                      setState(() => _open = open ? i : null),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  title: Text(
                    faqs[i].$1,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  trailing: Icon(
                    _open == i
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
child: Text(faqs[i].$2,
                            style: const TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Center(
            child: Text(L10n.t(context, 'supportEmail'),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textTertiary)),
          ),
        ],
      ),
    );
  }

  /// Contact entry: opens the Soft-Call chooser. Picking "Soft-Call" routes
  /// into the in-app call-center IVR (free); the carrier option keeps
  /// dialing the support hotline.
  Future<void> _callSupport() async {
    final phone = L10n.t(context, 'supportPhone');
    await showCallChooser(
      context,
      targetUserId: 'SUPPORT',
      displayName: L10n.t(context, 'helpTitle'),
      phone: phone,
      softCallOpensCallCenter: true,
    );
  }
}

class _ContactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ContactButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: Colors.white),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
