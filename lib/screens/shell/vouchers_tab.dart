import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_time.dart';
import '../../services/passenger_api.dart';
import '../../widgets/common_widgets.dart';

/// Vouchers tab: the passenger's personal bonus vouchers from
/// `GET /api/mobile/member/vouchers`. Each voucher shows its name,
/// description, a copyable code chip, an expiry date, its used-up state and
/// the free tier it was issued for (when present).
class VouchersTab extends StatefulWidget {
  const VouchersTab({super.key});

  @override
  State<VouchersTab> createState() => _VouchersTabState();
}

class _VouchersTabState extends State<VouchersTab> {
  List<Map<String, dynamic>> _vouchers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await passengerApi.getMemberVouchers();
      if (!mounted) return;
      setState(() => _vouchers = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _vouchers = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'copied')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Text(
              L10n.t(context, 'vouchers'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              L10n.t(context, 'noVouchersSub'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : _vouchers.isEmpty
                      ? _emptyList(context)
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          itemCount: _vouchers.length,
                          itemBuilder: (context, i) => _VoucherCard(
                            voucher: _vouchers[i],
                            onCopy: _copy,
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyList(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 70),
        EmptyState(
          icon: Icons.confirmation_number_outlined,
          title: L10n.t(context, 'noVouchers'),
          subtitle: L10n.t(context, 'noVouchersSub'),
        ),
      ],
    );
  }
}

/// One voucher card: name, description, a highlighted code chip with a copy
/// button, the expiry date and an optional free-tier label. Used-up vouchers
/// render dimmed.
class _VoucherCard extends StatelessWidget {
  final Map<String, dynamic> voucher;
  final ValueChanged<String> onCopy;
  const _VoucherCard({required this.voucher, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final usedUp = voucher['usedUp'] == true;
    final code = voucher['code']?.toString() ?? '';
    final name = voucher['name']?.toString() ?? '';
    final description = voucher['description']?.toString() ?? '';
    final endAt = DateTime.tryParse(voucher['endAt']?.toString() ?? '');
    final freeTier =
        voucher['freeTier'] is Map
            ? Map<String, dynamic>.from(voucher['freeTier'] as Map)
            : const <String, dynamic>{};
    final freeTierName = freeTier['name']?.toString() ?? '';

    return Opacity(
      opacity: usedUp ? 0.5 : 1,
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: usedUp
                        ? AppColors.textTertiary.withValues(alpha: 0.2)
                        : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.confirmation_number_rounded,
                    color: usedUp ? AppColors.textTertiary : AppColors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (freeTierName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${L10n.t(context, 'freeTier')} · $freeTierName',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (usedUp)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      L10n.t(context, 'used'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            if (endAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.event_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    L10n.t(context, 'expiresOn').replaceFirst(
                      '{date}',
                      egFormat(endAt, 'MMM d, yyyy'),
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.surfaceDark
                    : AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: L10n.t(context, 'copy'),
                    onPressed: () => onCopy(code),
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: usedUp
                          ? AppColors.textTertiary
                          : AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
