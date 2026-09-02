import 'package:flutter/material.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/primary_button.dart';

/// Call-center access: one tap to call the registered SoftCar number, or
/// jump straight into the live support chat where an agent picks up the
/// session from the queue.
class CallCenterScreen extends StatelessWidget {
  const CallCenterScreen({super.key});

  Future<void> _callNow(BuildContext context) async {
    await Navigator.of(context).pushNamed('/support-call');
  }

  void _chatNow(BuildContext context) {
    Navigator.of(context).pushNamed('/support-chat');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'callCenter'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Contact banner ----------------------------------------------------
          Container(
            padding: const EdgeInsets.all(20),
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
                    Icon(
                      Icons.headset_mic_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      L10n.t(context, 'callCenter'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.t(context, 'supportRepliesAway'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  L10n.t(context, 'callCenterPhone'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Call us -----------------------------------------------------------
          PrimaryButton(
            accent: true,
            icon: Icons.phone_outlined,
            label: L10n.t(context, 'callUs'),
            onPressed: () => _callNow(context),
          ),
          const SizedBox(height: 12),
          // Chat with us ------------------------------------------------------
          PrimaryButton(
            outline: true,
            icon: Icons.chat_bubble_outline_rounded,
            label: L10n.t(context, 'chatWithUs'),
            onPressed: () => _chatNow(context),
          ),
          const SizedBox(height: 24),
          SoftCenterCardInfo(
            icon: Icons.help_outline_rounded,
            text: '${L10n.t(context, 'connectingToSupport')} '
                '${L10n.t(context, 'waiting')}',
            dark: dark,
          ),
        ],
      ),
    );
  }
}

/// Small muted helper card used under the call-center actions.
class SoftCenterCardInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool dark;
  const SoftCenterCardInfo({
    super.key,
    required this.icon,
    required this.text,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDarkElevated : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
