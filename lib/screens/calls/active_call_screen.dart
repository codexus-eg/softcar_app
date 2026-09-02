import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../services/call_sounds.dart';
import '../../services/voip_service.dart';

/// In-call UI shared by outgoing and accepted Soft-Calls: hold music +
/// live queue position while waiting for an agent, duration/mute/speaker
/// once the WebRTC peer connects, and a graceful ended state.
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _popping = false;

  @override
  void initState() {
    super.initState();
    // Hold music only makes sense pre-connect; the service stops it when
    // the peer connects.
    CallSounds.instance.playHold();
  }

  @override
  void dispose() {
    if (!VoipService.instance.isActiveCall) {
      CallSounds.instance.stopAll();
    }
    super.dispose();
  }

  Future<void> _end() async {
    await CallSounds.instance.stopAll();
    await VoipService.instance.hangUp();
    await VoipService.instance.resetCall();
    if (mounted && !_popping) {
      _popping = true;
      Navigator.of(context).pop();
    }
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final voip = VoipService.instance;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: ListenableBuilder(
        listenable: voip,
        builder: (context, _) {
          final phase = voip.phase;

          // Remote side hung up -> toast + leave.
          if (phase == VoipPhase.ended && !_popping) {
            _popping = true;
            final nav = Navigator.of(context);
            final messenger = ScaffoldMessenger.maybeOf(context);
            final endedText = L10n.t(context, 'calls.callEnded');
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await CallSounds.instance.stopAll();
              await voip.resetCall();
              messenger?.showSnackBar(SnackBar(
                content: Text(endedText),
                behavior: SnackBarBehavior.floating,
              ));
              nav.pop();
            });
          }

          final waiting = phase == VoipPhase.outgoingQueued ||
              phase == VoipPhase.outgoingWaiting;
          final connecting = phase == VoipPhase.connecting;
          final active = phase == VoipPhase.active ||
              phase == VoipPhase.reconnecting;

          final title = waiting || connecting
              ? L10n.t(context, 'calls.connecting')
              : active
                  ? _fmt(voip.elapsedSeconds)
                  : '';
          final subtitle = waiting
              ? _queueText(voip.queuePosition)
              : phase == VoipPhase.reconnecting
                  ? L10n.t(context, 'calls.reconnecting')
                  : connecting
                      ? (voip.remoteName ?? '')
                      : (voip.remoteName ?? '');

          return SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 64),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 56),
                _Avatar(name: voip.remoteName, image: voip.remoteImage),
                if (voip.maskedNumber?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.6)),
                      const SizedBox(width: 6),
                      Text(
                        voip.maskedNumber!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                if (active)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ControlButton(
                          icon: voip.isMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: voip.isMuted
                              ? L10n.t(context, 'calls.unmute')
                              : L10n.t(context, 'calls.mute'),
                          active: voip.isMuted,
                          onTap: () => voip.toggleMute(),
                        ),
                        _ControlButton(
                          icon: Icons.volume_up_rounded,
                          label: L10n.t(context, 'calls.speaker'),
                          active: voip.isSpeakerOn,
                          onTap: () => voip.toggleSpeaker(),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 36),
                _RoundAction(
                  icon: Icons.call_end_rounded,
                  size: 76,
                  colors: const [Color(0xFFE02E2E), Color(0xFFB71C1C)],
                  onTap: _end,
                ),
                const SizedBox(height: 44),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Passengers' L10n.t has no parameter support — interpolate manually.
  String _queueText(int? pos) {
    if (pos == null || pos <= 0) return L10n.t(context, 'calls.searchingAgent');
    return L10n.t(context, 'calls.queuePosition').replaceAll('{n}', '$pos');
  }
}

class _Avatar extends StatelessWidget {
  final String? name;
  final String? image;

  const _Avatar({this.name, this.image});

  @override
  Widget build(BuildContext context) {
    final initial = (name?.isNotEmpty ?? false)
        ? name!.characters.first.toUpperCase()
        : '?';
    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.25),
            blurRadius: 38,
            spreadRadius: 4,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 60,
        backgroundColor: AppColors.accentSoft,
        backgroundImage:
            (image?.isNotEmpty ?? false) ? NetworkImage(image!) : null,
        child: (image?.isNotEmpty ?? false)
            ? null
            : Text(
                initial,
                style: const TextStyle(
                  fontSize: 42,
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
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
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.12),
            ),
            child: Icon(
              icon,
              color: active ? AppColors.ink : Colors.white,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final double size;
  final List<Color> colors;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.size,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
    );
  }
}
