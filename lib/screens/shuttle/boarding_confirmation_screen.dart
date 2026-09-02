import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_time.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../services/passenger_api.dart';

/// Forced confirmation screen shown while the driver is waiting for the
/// passenger to confirm a boarding / cash-collection action. Polls
/// `GET /reservations/confirmations` every few seconds and only clears once
/// no pending confirmations remain.
class BoardingConfirmationScreen extends StatefulWidget {
  const BoardingConfirmationScreen({super.key});

  @override
  State<BoardingConfirmationScreen> createState() =>
      _BoardingConfirmationScreenState();
}

class _BoardingConfirmationScreenState
    extends State<BoardingConfirmationScreen> {
  Timer? _timer;
  bool _loading = true;
  bool _working = false;
  List<Map<String, dynamic>> _confirmations = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final rows = await passengerApi.getPendingConfirmations();
      if (!mounted) return;
      setState(() {
        _confirmations =
            rows.whereType<Map>().map(Map<String, dynamic>.from).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _wantsCash(String? type) =>
      type == 'CASH_COLLECTION' || type == 'CASH_AND_BOARDING';
  bool _wantsBoarding(String? type) =>
      type == 'BOARDING' || type == 'CASH_AND_BOARDING';
  bool _isNotComing(String? type) => type == 'NOT_COMING';

  Future<void> _respond(
    Map<String, dynamic> confirmation, {
    required bool confirmedBoarding,
    required bool confirmedPayment,
    String? note,
  }) async {
    setState(() => _working = true);
    try {
      await passengerApi.respondToConfirmation(
        confirmation['id'].toString(),
        confirmedBoarding: confirmedBoarding,
        confirmedPayment: confirmedPayment,
        responseNote: note,
      );
      Haptics.success();
      await _refresh();
    } on PassengerApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send your answer right now.')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _confirmFlow(Map<String, dynamic> confirmation) {
    final cash = _wantsCash(confirmation['type']?.toString());
    final board = _wantsBoarding(confirmation['type']?.toString());
    final notComing = _isNotComing(confirmation['type']?.toString());
    final amount = _money(confirmation['requestedCashAmount']);

    if (notComing) {
      _confirmNotComingFlow(confirmation);
      return;
    }
    var paid = false;
    var boarded = false;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.t(context, 'confirmBoarding'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                L10n.t(context, 'confirmBoardingSub'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              if (cash)
                _checkRow(
                  context,
                  checked: paid,
                  title: L10n.t(context, 'iPaidCash'),
                  subtitle: amount,
                  onChanged: (v) => setSheet(() => paid = v),
                ),
              if (board)
                _checkRow(
                  context,
                  checked: boarded,
                  title: L10n.t(context, 'iBoarded'),
                  subtitle: L10n.t(context, 'iBoardedSub'),
                  onChanged: (v) => setSheet(() => boarded = v),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _working
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          _respond(
                            confirmation,
                            confirmedBoarding: boarded,
                            confirmedPayment: paid,
                          );
                        },
                  child: Text(
                    L10n.t(context, 'confirm'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmNotComingFlow(Map<String, dynamic> confirmation) {
    final tripName = confirmation['trip']?['title']?.toString() ?? '';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: AppColors.error,
          size: 48,
        ),
        title: Text(
          L10n.t(context, 'notComingConfirmTitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L10n.t(context, 'notComingConfirmBody')
                  .replaceAll('{trip}', tripName),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.t(context, 'notComingWarning'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(L10n.t(context, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _respond(
                confirmation,
                confirmedBoarding: false,
                confirmedPayment: false,
              );
            },
            child: Text(
              L10n.t(context, 'confirmNotComing'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  void _rejectFlow(Map<String, dynamic> confirmation) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.t(context, 'rejectBoarding')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L10n.t(context, 'rejectBoardingSub'),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: L10n.t(context, 'reasonOptional'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(L10n.t(context, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _respond(
                confirmation,
                confirmedBoarding: false,
                confirmedPayment: false,
                note: controller.text.trim(),
              );
            },
            child: Text(L10n.t(context, 'reject')),
          ),
        ],
      ),
    );
  }

  Widget _checkRow(
    BuildContext context, {
    required bool checked,
    required String title,
    required String subtitle,
    required ValueChanged<bool> onChanged,
  }) {
    return CheckboxListTile(
      value: checked,
      onChanged: (v) => onChanged(v ?? false),
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
      activeColor: AppColors.success,
    );
  }

  String _money(Object? value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return '${Formatters.currency(amount)} EGP';
  }

  String _expiryText(Map<String, dynamic> c) {
    final expires = DateTime.tryParse(c['expiresAt']?.toString() ?? '');
    if (expires == null) return '';
    final minutes = expires.difference(DateTime.now()).inMinutes.clamp(0, 999);
    return '${L10n.t(context, 'expiresIn')} $minutes ${L10n.t(context, 'minutesUnit')}';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.isArabic(context);

    return Scaffold(
      backgroundColor: AppColors.success.withValues(alpha: 0.08),
      appBar: AppBar(
        title: Text(L10n.t(context, 'confirmBoarding')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _confirmations.isEmpty
                ? _ClearState(onDone: () {
                    Haptics.success();
                    Navigator.of(context).maybePop();
                  })
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                L10n.t(context, 'confirmBoardingBanner'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final c in _confirmations) ...[
                        _ConfirmationCard(
                          confirmation: c,
                          working: _working,
                          isArabic: isArabic,
                          onConfirm: () => _confirmFlow(c),
                          onReject: () => _rejectFlow(c),
                          expiryText: _expiryText(c),
                          money: _money(c['requestedCashAmount']),
                          cash: _wantsCash(c['type']?.toString()),
                          boarding: _wantsBoarding(c['type']?.toString()),
                          notComing: _isNotComing(c['type']?.toString()),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  final Map<String, dynamic> confirmation;
  final bool working;
  final bool isArabic;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  final String expiryText;
  final String money;
  final bool cash;
  final bool boarding;
  final bool notComing;

  const _ConfirmationCard({
    required this.confirmation,
    required this.working,
    required this.isArabic,
    required this.onConfirm,
    required this.onReject,
    required this.expiryText,
    required this.money,
    required this.cash,
    required this.boarding,
    this.notComing = false,
  });

  Map<String, dynamic> get _trip =>
      confirmation['trip'] is Map
          ? Map<String, dynamic>.from(confirmation['trip'] as Map)
          : const <String, dynamic>{};
  Map<String, dynamic> get _driver =>
      confirmation['driver'] is Map
          ? Map<String, dynamic>.from(confirmation['driver'] as Map)
          : const <String, dynamic>{};
  Map<String, dynamic> get _reservation =>
      confirmation['reservation'] is Map
          ? Map<String, dynamic>.from(confirmation['reservation'] as Map)
          : const <String, dynamic>{};

  String get _pickupName {
    final pickup = _reservation['pickupPoint'];
    if (pickup is Map && pickup['name'] != null) {
      return pickup['name'].toString();
    }
    return '—';
  }

  String get _dropoffName {
    final dropoff = _reservation['dropoffPoint'];
    if (dropoff is Map && dropoff['name'] != null) {
      return dropoff['name'].toString();
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = egFormat(
      DateTime.tryParse(_trip['startTime']?.toString() ?? ''),
      'EEE, MMM d · HH:mm',
    );
    final labels = <String>[
      if (cash) L10n.t(context, 'collectingCash'),
      if (boarding) L10n.t(context, 'boardingConfirmation'),
      if (notComing) L10n.t(context, 'notComingConfirmTitle'),
    ];
    final attempt = confirmation['attemptNumber'];
    final maxAttempts = confirmation['maxAttempts'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: notComing ? AppColors.error.withValues(alpha: 0.4) : AppColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _trip['title']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: (notComing ? AppColors.error : AppColors.warning).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  labels.join(' + '),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: notComing ? AppColors.error : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          if (startLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              startLabel,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.trip_origin,
                size: 14,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _pickupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.location_on,
                size: 14,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _dropoffName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (cash) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    L10n.t(context, 'cashAmount'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    money,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_driver['name'] != null &&
              _driver['name'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.accentSoft,
                  backgroundImage:
                      _driver['image'] != null &&
                          _driver['image'].toString().isNotEmpty
                      ? NetworkImage(
                          Formatters.imageUrl(_driver['image'].toString()),
                        )
                      : null,
                  child:
                      _driver['image'] == null ||
                          _driver['image'].toString().isEmpty
                      ? const Icon(Icons.person, size: 16, color: AppColors.accent)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.t(context, 'driver'),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _driver['name'].toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_driver['carModel'] != null &&
                    _driver['carModel'].toString().isNotEmpty)
                  Text(
                    _driver['carModel'].toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
          if (expiryText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              expiryText,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (attempt != null && maxAttempts != null) ...[
            const SizedBox(height: 4),
            Text(
              '${L10n.t(context, 'attempt')} $attempt/$maxAttempts',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                      color: AppColors.error.withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: working ? null : onReject,
                  child: Text(
                    L10n.t(context, 'reject'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: working ? null : onConfirm,
                  child: Text(
                    L10n.t(context, 'confirm'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClearState extends StatelessWidget {
  final VoidCallback onDone;
  const _ClearState({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 44,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            L10n.t(context, 'allConfirmed'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.t(context, 'allConfirmedSub'),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 36,
                vertical: 14,
              ),
            ),
            onPressed: onDone,
            child: Text(L10n.t(context, 'done')),
          ),
        ],
      ),
    );
  }
}