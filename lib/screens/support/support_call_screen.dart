import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/network_call_service.dart';
import '../../services/passenger_api.dart';

class SupportCallScreen extends StatefulWidget {
  const SupportCallScreen({super.key});

  @override
  State<SupportCallScreen> createState() => _SupportCallScreenState();
}

class _SupportCallScreenState extends State<SupportCallScreen> {
  late final NetworkCallService _call;
  final _reason = TextEditingController(text: 'I need help with my booking');
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _call = NetworkCallService(
      refreshCall: (id) async {
        final json = await passengerApi.getSupportCall(id);
        return _session(json);
      },
      sendSignal: passengerApi.sendCallSignal,
      receiveSignals: passengerApi.getCallSignals,
      endRemoteCall: (id) => passengerApi.updateSupportCall(id, 'end'),
    )..addListener(_changed);
  }

  static Map<String, dynamic>? _session(Map<String, dynamic> json) {
    final raw = json['session'];
    if (raw is! Map) return null;
    final value = Map<String, dynamic>.from(raw);
    if (json['queuePosition'] != null) {
      value['queuePosition'] = json['queuePosition'];
    }
    if (json['iceServers'] != null) value['iceServers'] = json['iceServers'];
    return value;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty || _starting) return;
    setState(() => _starting = true);
    try {
      final json = await passengerApi.createSupportCall(reason: reason);
      final session = _session(json);
      if (session == null) {
        throw const PassengerApiException('Call was not created.');
      }
      await _call.startCaller(session);
    } on PassengerApiException catch (e) {
      _message(e.message);
    } catch (_) {
      _message('Could not start the secure call. Please check your internet.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  void dispose() {
    _call.removeListener(_changed);
    _call.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final started = _call.callId.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Call customer service')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.support_agent_rounded,
              size: 72,
              color: AppColors.accent,
            ),
            const SizedBox(height: 16),
            Text(
              started ? _statusTitle() : 'A private in-app support call',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              started
                  ? _statusDetail()
                  : 'No phone number is shared. Calls are routed automatically to an available agent, then to a manager when the team is busy.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            if (!started) ...[
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'What do you need help with?',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _starting ? null : _start,
                icon:
                    _starting
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.call_rounded),
                label: const Text('Join call queue'),
              ),
            ] else ...[
              if (_call.agentName != null)
                _InfoTile(
                  icon: Icons.badge_outlined,
                  label: 'Helping you',
                  value: _call.agentName!,
                ),
              const SizedBox(height: 12),
              _InfoTile(
                icon: Icons.lock_outline_rounded,
                label: 'Connection',
                value: _call.connectionState.toUpperCase(),
              ),
              if (_call.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _call.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallControl(
                    icon:
                        _call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _call.muted ? 'Unmute' : 'Mute',
                    onTap: _call.toggleMute,
                  ),
                  const SizedBox(width: 18),
                  _CallControl(
                    icon:
                        _call.speaker
                            ? Icons.volume_up_rounded
                            : Icons.hearing_rounded,
                    label: 'Speaker',
                    active: _call.speaker,
                    onTap: _call.toggleSpeaker,
                  ),
                  const SizedBox(width: 18),
                  _CallControl(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    destructive: true,
                    onTap: () async {
                      await _call.hangUp();
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusTitle() {
    if (_call.isFinished) return 'Call ended';
    if (_call.status == 'QUEUED') return 'You are in the queue';
    if (_call.status == 'ASSIGNED') return 'Agent found';
    if (_call.status == 'ACTIVE') return 'Connected';
    return 'Connecting securely';
  }

  String _statusDetail() {
    if (_call.status == 'QUEUED') {
      final position = _call.queuePosition;
      return position == null
          ? 'We will connect you as soon as an agent is available.'
          : 'Queue position $position. Keep this screen open.';
    }
    return 'Your encrypted audio stays inside the SoftCar support system.';
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool active;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Ink(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                destructive
                    ? AppColors.error
                    : active
                    ? AppColors.accent
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Icon(icon, color: destructive || active ? Colors.white : null),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}
