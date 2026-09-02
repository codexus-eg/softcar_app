import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/wallet_service.dart';
import '../../widgets/common_widgets.dart';

/// SoftCar Wallet: live balance and transaction history from the production
/// `/wallet/transactions` endpoint. No offline/demo values.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final tx = wallet.data.transactions;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'wallet'))),
      body: RefreshIndicator(
        onRefresh: () => wallet.refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0B0B0D), Color(0xFF2C2C33)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.t(context, 'availableBalance'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 6),
                  if (wallet.loading)
                    const SizedBox(
                      width: 180,
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    )
                  else
                    Text(
                      Formatters.moneyWhole(wallet.data.balance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _CardButton(
                          icon: Icons.add,
                          label: L10n.t(context, 'addMoney'),
                          onTap: () =>
                              Navigator.of(context).pushNamed('/wallet-recharge'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CardButton(
                            icon: Icons.send_outlined,
                            label: L10n.t(context, 'send'),
                            onTap: () => _toast(
                                context, L10n.t(context, 'transfersProcessed')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(L10n.t(context, 'recentActivity'),
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            if (tx.isEmpty)
              EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: L10n.t(context, 'noTransactionsYet'),
                subtitle: L10n.t(context, 'noTransactionsSub'),
              )
            else
              for (final t in tx) _transactionRow(context, t),
          ],
        ),
      ),
    );
  }

  Widget _transactionRow(BuildContext context, Map<String, dynamic> t) {
    var title = t['description']?.toString() ??
        t['note']?.toString() ??
        t['title']?.toString() ??
        (t['type']?.toString() ?? L10n.t(context, 'walletActivity'));
    final amount = _num(t['amount']);
    final positive = amount >= 0;
    final type = t['type']?.toString().toUpperCase() ?? '';
    final status = (t['topupStatus'] ?? t['status'])
            ?.toString()
            .toUpperCase() ??
        '';
    final isTopup = t['purpose']?.toString() == 'wallet_top_up' ||
        t['topupStatus'] != null ||
        type.contains('TOPUP') ||
        type.contains('TOP_UP') ||
        type.contains('RECHARGE');
    final isChange = type == 'DRIVER_CASH_CHANGE_TO_WALLET';
    final reviewing = isTopup &&
        (WalletService.pendingTopupStatuses.contains(status) ||
            status == 'PENDING');
    final rejected = isTopup &&
        const {'REJECTED', 'FAILED', 'CANCELLED'}.contains(status);
    final refunded = isTopup && status == 'REFUNDED';
    final approved = isTopup && !reviewing && !rejected && !refunded;
    final color = isChange
        ? AppColors.info
        : reviewing
            ? AppColors.textTertiary
            : rejected
                ? AppColors.error
                : refunded
                    ? AppColors.warning
                    : approved
                        ? AppColors.success
                        : positive
                            ? AppColors.success
                            : AppColors.accent;
    final icon = isChange
        ? Icons.currency_exchange_rounded
        : reviewing
            ? Icons.question_mark_rounded
            : rejected
                ? Icons.close_rounded
                : refunded
                    ? Icons.replay_rounded
                    : approved
                        ? Icons.check_rounded
                        : positive
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded;
    if (isChange) title = L10n.t(context, 'changeCredit');
    if (reviewing) title = L10n.t(context, 'topupReviewing');
    if (rejected) title = L10n.t(context, 'topupRejected');
    if (refunded) title = L10n.t(context, 'topupRefunded');
    if (approved) title = L10n.t(context, 'topupApproved');
    final at = DateTime.tryParse(
            t['createdAt']?.toString() ?? t['date']?.toString() ?? '') ??
        DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(Formatters.relative(at),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(
            '${reviewing || rejected ? '' : positive ? '+' : ''}${Formatters.currency(amount.abs())}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

double _num(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class _CardButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CardButton({
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
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white),
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
