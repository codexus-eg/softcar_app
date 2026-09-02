import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../services/call_sounds.dart';
import '../../services/voip_service.dart';

/// Call-center IVR entry point: greeting message with animated logo, then a
/// department chooser (RESERVATIONS / COMPLAINTS plus a small direct-agent
/// link). Picking a lane beeps, creates the session and shows live hold
/// music + queue position until the WebRTC call screen takes over.
class CallCenterScreen extends StatefulWidget {
  const CallCenterScreen({super.key});

  @override
  State<CallCenterScreen> createState() => _CallCenterScreenState();
}

class _CallCenterScreenState extends State<CallCenterScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  String? _startingLane;
  bool _transitioning = false;
  bool _endingCall = false;

  @override
  void initState() {
    super.initState();
    CallSounds.instance.playGreeting();
  }

  @override
  void dispose() {
    _pulse.dispose();
    // Leaving mid-call cancels it.
    final voip = VoipService.instance;
    if (!voip.isActiveCall &&
        voip.phase != VoipPhase.idle &&
        voip.phase != VoipPhase.ended) {
      voip.hangUp().then((_) => voip.resetCall());
    }
    CallSounds.instance.stopGreeting();
    super.dispose();
  }

  Future<void> _startLane(String lane) async {
    if (_startingLane != null || _transitioning) return;
    setState(() => _startingLane = lane);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failedText = L10n.t(context, 'calls.callFailed');
    await CallSounds.instance.stopGreeting();
    await CallSounds.instance.playBeep();
    try {
      await VoipService.instance.createSupportLaneCall(
        supportLane: lane,
        reason: switch (lane) {
          'RESERVATIONS' => 'Reservations & inquiries',
          'COMPLAINTS' => 'Complaints & suggestions',
          _ => 'Direct agent request',
        },
        priority: lane == 'COMPLAINTS' ? 2 : 0,
      );
      if (mounted) setState(() => _startingLane = null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _startingLane = null);
      messenger?.showSnackBar(SnackBar(
        content: Text(failedText),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _cancelWaiting() async {
    if (_endingCall) return;
    _endingCall = true;
    final voip = VoipService.instance;
    await voip.hangUp();
    await voip.resetCall();
    _endingCall = false;
  }

  @override
  Widget build(BuildContext context) {
    final voip = VoipService.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(L10n.t(context, 'cc.title')),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListenableBuilder(
        listenable: voip,
        builder: (context, _) {
          final phase = voip.phase;

          // Hand over to the live call screen once an agent accepts.
          if ((phase == VoipPhase.connecting ||
                  phase == VoipPhase.active ||
                  phase == VoipPhase.reconnecting) &&
              !_transitioning) {
            _transitioning = true;
            final nav = Navigator.of(context);
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await CallSounds.instance.stopHold();
              nav.pushReplacementNamed('/active-call');
            });
          }

          // Agent hung up before we connected -> toast + back to greeting.
          if (phase == VoipPhase.ended && !_transitioning && !_endingCall) {
            final messenger = ScaffoldMessenger.maybeOf(context);
            final endedText = L10n.t(context, 'calls.callEnded');
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await CallSounds.instance.stopAll();
              await voip.resetCall();
              messenger?.showSnackBar(SnackBar(
                content: Text(endedText),
                behavior: SnackBarBehavior.floating,
              ));
            });
          }

          final waiting = phase == VoipPhase.outgoingQueued ||
              phase == VoipPhase.outgoingWaiting;

          return waiting
              ? _buildWaiting(voip)
              : _buildGreeting(context, voip);
        },
      ),
    );
  }

  // ---- greeting + department chooser ----------------------------------------

  Widget _buildGreeting(BuildContext context, VoipService voip) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.04).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.18),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child:
                    const Icon(Icons.headset_mic_rounded, size: 42, color: AppColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            L10n.t(context, 'cc.greeting'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.t(context, 'cc.chooseDept'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _DepartmentCard(
            icon: Icons.event_available_rounded,
            title: L10n.t(context, 'cc.reservations'),
            subtitle: L10n.t(context, 'cc.reservationsSub'),
            busy: _startingLane == 'RESERVATIONS',
            onTap: () => _startLane('RESERVATIONS'),
          ),
          const SizedBox(height: 14),
          _DepartmentCard(
            icon: Icons.feedback_rounded,
            title: L10n.t(context, 'cc.complaints'),
            subtitle: L10n.t(context, 'cc.complaintsSub'),
            busy: _startingLane == 'COMPLAINTS',
            onTap: () => _startLane('COMPLAINTS'),
          ),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed:
                  _startingLane == null ? () => _startLane('CALL_CENTER') : null,
              child: Text(
                L10n.t(context, 'cc.talkToAgent'),
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- hold / queue position -------------------------------------------------

  Widget _buildWaiting(VoipService voip) {
    final pos = voip.queuePosition;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.06).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(
                  color: AppColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.graphic_eq_rounded,
                    size: 46, color: AppColors.accent),
              ),
            ),
            const SizedBox(height: 26),
            Text(
              pos == null || pos <= 0
                  ? L10n.t(context, 'calls.searchingAgent')
                  : L10n.t(context, 'cc.youAreNumber')
                      .replaceAll('{n}', '$pos'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              L10n.t(context, 'calls.connecting'),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 44),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              onPressed: _cancelWaiting,
              icon: const Icon(Icons.call_end_rounded, size: 18),
              label: Text(L10n.t(context, 'cc.cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;

  const _DepartmentCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 0.5,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.accent,
                        ),
                      )
                    : Icon(icon, color: AppColors.accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.call_rounded,
                  color: AppColors.success, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
