import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../services/call_sounds.dart';
import '../../services/voip_service.dart';

/// Full-screen incoming Soft-Call card: pulsing avatar, caller identity and
/// big Accept / Decline buttons. Ringer loops until answered/declined and
/// the ring auto-expires after 45s (decline + cancel server-side).
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    CallSounds.instance.playRingtone();
    // Safety: the service also owns a 45s timer; this mirrors it visually.
    Future<void>.delayed(const Duration(seconds: 45), () {
      if (mounted && !_busy) _decline();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    CallSounds.instance.stopRingtone();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await CallSounds.instance.stopRingtone();
    final ok = await VoipService.instance.acceptIncoming();
    if (!mounted) return;
    if (!ok) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      VoipService.instance.clearIncomingRing();
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(
        content: Text(L10n.t(context, 'calls.callEnded')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    Navigator.of(context).pushReplacementNamed('/active-call');
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    await CallSounds.instance.stopRingtone();
    await VoipService.instance.declineIncoming();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final voip = VoipService.instance;
    final ring = voip.incomingRing ?? const <String, dynamic>{};
    final name = (ring['fromName']?.toString().isNotEmpty ?? false)
        ? ring['fromName'].toString()
        : 'SoftCar';
    final role = _roleLabel(context, ring['fromRole']?.toString());
    final masked = ring['maskedNumber']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Text(
              L10n.t(context, 'calls.softCall'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 40),
            // Pulsing avatar --------------------------------------------------
            ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.12).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 42,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 62,
                  backgroundColor: AppColors.accentSoft,
                  child: Text(
                    name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 44,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (role != null && role.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                role,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (masked.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 13, color: Colors.white.withValues(alpha: 0.75)),
                    const SizedBox(width: 6),
                    Text(
                      masked,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            Text(
              L10n.t(context, 'calls.inAppVoice'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),
            // Controls --------------------------------------------------------
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundAction(
                    icon: Icons.call_end_rounded,
                    label: L10n.t(context, 'calls.decline'),
                    size: 78,
                    colors: const [Color(0xFFE02E2E), Color(0xFFB71C1C)],
                    onTap: _decline,
                  ),
                  _RoundAction(
                    icon: Icons.call_rounded,
                    label: L10n.t(context, 'calls.accept'),
                    size: 78,
                    colors: const [Color(0xFF22C55E), Color(0xFF15803D)],
                    onTap: _accept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _roleLabel(BuildContext context, String? rawRole) {
    switch ((rawRole ?? '').toUpperCase()) {
      case 'PASSENGER':
        return L10n.t(context, 'calls.rolePassenger');
      case 'DRIVER':
        return L10n.t(context, 'calls.roleDriver');
      case 'MANAGER':
        return L10n.t(context, 'calls.roleManager');
      case 'AGENT':
      case 'SUPPORT':
        return L10n.t(context, 'calls.roleSupport');
      default:
        return rawRole;
    }
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final double size;
  final List<Color> colors;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.label,
    required this.size,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.last.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.44),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
