import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../models/shuttle.dart';
import '../../services/passenger_api.dart';

/// The passenger's own suggest-trip requests: every submission with its live
/// status (pending / approved / auto-resolved / cancelled), the departure-time
/// preference they typed, and an action for each state:
///  - PENDING        → cancel
///  - AUTO_RESOLVED  → book the matched trip right away
/// Refreshes on pull-to-refresh and after every kill.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  bool _cancelling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await passengerApi.mySuggestions();
      if (!mounted) return;
      setState(() {
        _requests = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _cancel(Map<String, dynamic> request) async {
    final id = request['id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'myRequestsCancelTitle')),
        content: Text(L10n.t(ctx, 'myRequestsCancelSub')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'myRequestsCancel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    Haptics.medium();
    setState(() => _cancelling = true);
    try {
      await passengerApi.cancelSuggestion(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.t(context, 'myRequestsCancelled'))));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.t(context, 'myRequestsError'))));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _bookNow(Map<String, dynamic> request) async {
    final trip = request['resolvedTrip'];
    if (trip is! Map) return;
    final tripId = trip['id']?.toString();
    if (tripId == null || tripId.isEmpty) return;
    Haptics.selection();
    try {
      final detail = await passengerApi.fetchTripDetail(tripId);
      if (!mounted) return;
      if (detail == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'myRequestsTripGone'))),
        );
        return;
      }
      final shuttle = ShuttleTrip.fromJson(detail);
      await Navigator.of(
        context,
      ).pushNamed('/seat-selection', arguments: shuttle);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.t(context, 'myRequestsTripGone'))));
    }
  }

  String _statusKey(String? status) {
    switch (status?.toUpperCase()) {
      case 'PENDING':
        return 'myRequestsPending';
      case 'APPROVED':
        return 'myRequestsApproved';
      case 'AUTO_RESOLVED':
        return 'myRequestsResolved';
      case 'REJECTED':
        return 'myRequestsRejected';
      case 'CANCELLED':
        return 'myRequestsCancelTitle';
      case 'DISMISSED':
        return 'myRequestsDismissed';
      default:
        return 'myRequestsPending';
    }
  }

  Color _statusColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'PENDING':
        return AppColors.accent;
      case 'APPROVED':
        return AppColors.success;
      case 'AUTO_RESOLVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.error;
      case 'CANCELLED':
      case 'DISMISSED':
        return AppColors.textTertiary;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          L10n.t(context, 'myRequestsTitle'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _centered(
                _error!,
                icon: Icons.wifi_off_rounded,
                onRetry: _load,
              )
            : _requests.isEmpty
            ? _centered(
                L10n.t(context, 'myRequestsEmpty'),
                icon: Icons.hourglass_empty_rounded,
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _requests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final request = _requests[i];
                  return _RequestCard(
                    request: request,
                    onCancel:
                        (request['status']?.toString().toUpperCase() ==
                            'PENDING')
                            ? (request['id']?.toString().isNotEmpty == true)
                                  ? () => _cancel(request)
                                  : null
                            : null,
                    onBook:
                        (request['status']?.toString().toUpperCase() ==
                                'AUTO_RESOLVED' &&
                            request['resolvedTrip'] is Map)
                            ? () => _bookNow(request)
                            : null,
                    cancelling: _cancelling,
                    statusText: L10n.t(context, _statusKey(request['status']?.toString())),
                    statusColor: _statusColor(request['status']?.toString()),
                  );
                },
              ),
      ),
    );
  }

  Widget _centered(String message, {required IconData icon, VoidCallback? onRetry}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 52, color: AppColors.textTertiary),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(L10n.t(context, 'retry')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onCancel;
  final VoidCallback? onBook;
  final bool cancelling;
  final String statusText;
  final Color statusColor;

  const _RequestCard({
    required this.request,
    required this.onCancel,
    required this.onBook,
    required this.cancelling,
    required this.statusText,
    required this.statusColor,
  });

  String _placeName(Object? place) {
    if (place is Map) {
      return place['name']?.toString() ?? '';
    }
    return '';
  }

  String _preference() {
    final pref = request['departureTimePreference']?.toString() ?? '';
    return pref.trim().isEmpty ? '' : pref.trim();
  }

  String _resolvedTitle() {
    final trip = request['resolvedTrip'];
    if (trip is Map) {
      final title = trip['title']?.toString() ?? '';
      if (title.isNotEmpty) return title;
      return _placeName(request['destination']);
    }
    return _placeName(request['destination']);
  }

  @override
  Widget build(BuildContext context) {
    final origin = _placeName(request['origin']);
    final destination = _placeName(request['destination']);
    final pref = _preference();
    final createdAt = DateTime.tryParse(request['createdAt']?.toString() ?? '');
    final isPending = onCancel != null;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).brightness == Brightness.dark ? AppColors.surfaceDarkElevated : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      origin.isEmpty ? '—' : origin,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_downward_rounded,
                          size: 14,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            destination.isEmpty ? '—' : destination,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (createdAt != null) ...[
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    _formatDate(context, createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
              if (pref.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(Icons.access_time_rounded, size: 14, color: AppColors.accent),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    pref,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (onBook != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBook,
                icon: const Icon(Icons.event_seat_rounded),
                label: Text(
                  L10n.t(context, 'myRequestsBookNow').replaceFirst(
                    '{trip}',
                    _resolvedTitle(),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: cancelling ? null : onCancel,
                icon: cancelling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.close_rounded, size: 18),
                label: Text(L10n.t(context, 'myRequestsCancel')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(BuildContext context, DateTime date) {
    final isArabic = L10n.isArabic(context);
    final local = date.toLocal();
    String months;
    if (isArabic) {
      const arMonths = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
      ];
      months = arMonths[local.month - 1];
      return '${local.day} $months ${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    const enMonths = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    months = enMonths[local.month - 1];
    return '${local.day} $months ${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}