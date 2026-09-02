import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/wallet_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/primary_button.dart';

/// Wallet tab: live balance plus the transaction history from the
/// production `/wallet/transactions` endpoint.
class WalletTab extends StatelessWidget {
  const WalletTab({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final tx = wallet.data.transactions;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => wallet.refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(L10n.t(context, 'wallet'),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            _BalanceCard(
              balance: wallet.data.balance,
              currency: wallet.data.currency,
              loading: wallet.loading,
            ),
            const SizedBox(height: 12),
            _WeekSummaryStrip(transactions: tx),
            const SizedBox(height: 12),
            _LoyaltyCard(wallet: wallet),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(L10n.t(context, 'transactions'),
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            if (tx.isEmpty)
              EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: L10n.t(context, 'noTransactionsYet'),
                subtitle: L10n.t(context, 'noTransactionsSub'),
              )
            else
              for (final t in tx) _TransactionTile(data: t),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double balance;
  final String currency;
  final bool loading;

  const _BalanceCard({
    required this.balance,
    required this.currency,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ink, Color(0xFF3A1418), AppColors.accentDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(L10n.t(context, 'availableBalance'),
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
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
              '${currency.isEmpty ? 'EGP ' : '$currency '}'
              '${balance.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            L10n.t(context, 'paymentsSettled'),
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: L10n.t(context, 'recharge'),
                  icon: Icons.add,
                  accent: true,
                  height: 50,
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/wallet-recharge'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context)
                      .pushNamed('/my-bookings'),
                  icon: const Icon(Icons.confirmation_number_outlined,
                      size: 18),
                  label: Text(L10n.t(context, 'tickets'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// This-week deposits vs spending, derived from the live transactions.
class _WeekSummaryStrip extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  const _WeekSummaryStrip({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final (deposits, spent) = _weekSummary(transactions);
    final hasData = deposits > 0 || spent > 0;
    if (!hasData) return const SizedBox.shrink();

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: _summaryItem(
              context,
              icon: Icons.south_west_rounded,
              iconColor: AppColors.success,
              label: L10n.t(context, 'weekDeposits'),
              value: Formatters.currency(deposits),
              valueColor: AppColors.success,
            ),
          ),
          Container(
            width: 1,
            height: 38,
            color: AppColors.divider,
          ),
          Expanded(
            child: _summaryItem(
              context,
              icon: Icons.north_east_rounded,
              iconColor: AppColors.error,
              label: L10n.t(context, 'weekSpending'),
              value: Formatters.currency(spent),
              valueColor: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Sums deposits vs spending for the current ISO week (Monday → now) from the
/// live transaction records.
(double, double) _weekSummary(List<Map<String, dynamic>> tx) {
  final now = DateTime.now();
  final weekStart =
      DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
  var deposits = 0.0;
  var spent = 0.0;
  for (final t in tx) {
    final at = _date(t['createdAt'] ?? t['date'] ?? t['at']);
    if (at.isBefore(weekStart)) continue;
    final amount = _num(t['amount']);
    if (_isExpense(t)) {
      spent += amount.abs();
    } else {
      deposits += amount.abs();
    }
  }
  return (deposits, spent);
}

class _LoyaltyCard extends StatelessWidget {
  final WalletService wallet;
  const _LoyaltyCard({required this.wallet});

  /// The /loyalty payload nests the summary under `summary`.
  Map<String, dynamic> get _summary =>
      wallet.loyalty['summary'] is Map
          ? Map<String, dynamic>.from(wallet.loyalty['summary'] as Map)
          : wallet.loyalty;

  @override
  Widget build(BuildContext context) {
    if (wallet.loyalty.isEmpty && !wallet.loyaltyLoading) {
      return const SizedBox.shrink();
    }
    final s = _summary;
    final current = s['currentLevel'] is Map
        ? Map<String, dynamic>.from(s['currentLevel'] as Map)
        : const <String, dynamic>{};
    final levelName = current['name']?.toString() ?? 'BRONZE';
    final points = _num(s['points']);
    final progress = _num(s['progressPercent']);

    return SoftCard(
      accent: true,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFCE7E7),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.workspace_premium_rounded,
                color: AppColors.accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${L10n.t(context, 'loyalty')} · $levelName',
                        style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    Text('$points ${L10n.t(context, 'pts')}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w900,
                            )),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (progress / 100).clamp(0, 1),
                    minHeight: 6,
                    color: AppColors.accent,
                    backgroundColor: AppColors.accentSoft,
                  ),
                ),
                if (wallet.loyaltyLoading)
                  const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How a wallet transaction is presented: an outgoing payment, a refund back
/// to the wallet, or a plain deposit/credit.
enum _TxBucket {
  expense,
  refund,
  deposit,
  topupApproved,
  topupRefunded,
  topupRejected,
  topupReviewing,
  changeCredit,
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TransactionTile({required this.data});

  _TxBucket get _bucket {
    final type = data['type']?.toString().toUpperCase() ?? '';
    final status = (data['topupStatus'] ?? data['status'])
            ?.toString()
            .toUpperCase() ??
        '';
    final purpose = data['purpose']?.toString().toLowerCase() ?? '';
    final isTopup = purpose == 'wallet_top_up' ||
        data['topupStatus'] != null ||
        type.contains('TOPUP') ||
        type.contains('TOP_UP') ||
        type.contains('RECHARGE');
    if (type == 'DRIVER_CASH_CHANGE_TO_WALLET') {
      return _TxBucket.changeCredit;
    }
    if (isTopup) {
      if (status == 'REFUNDED') return _TxBucket.topupRefunded;
      if (status == 'REJECTED' || status == 'FAILED' || status == 'CANCELLED') {
        return _TxBucket.topupRejected;
      }
      if (WalletService.pendingTopupStatuses.contains(status) ||
          status == 'PENDING') {
        return _TxBucket.topupReviewing;
      }
      if (status == 'APPROVED' ||
          status == 'AUTHORIZED' ||
          status == 'PAID' ||
          status == 'POSTED') {
        return _TxBucket.topupApproved;
      }
    }
    if (_isExpense(data)) return _TxBucket.expense;
    if (type.contains('REFUND') || data['refundAmount'] != null) {
      return _TxBucket.refund;
    }
    return _TxBucket.deposit;
  }

  @override
  Widget build(BuildContext context) {
    final bucket = _bucket;
    final amount = _num(data['amount']);
    final sign = bucket == _TxBucket.expense ? '-' : '+';
    final color = switch (bucket) {
      _TxBucket.expense => AppColors.error,
      _TxBucket.refund => AppColors.warning,
      _TxBucket.deposit => AppColors.success,
      _TxBucket.topupApproved => AppColors.success,
      _TxBucket.topupRefunded => AppColors.warning,
      _TxBucket.topupRejected => AppColors.error,
      _TxBucket.topupReviewing => AppColors.textTertiary,
      _TxBucket.changeCredit => AppColors.info,
    };
    final labelKey = switch (bucket) {
      _TxBucket.expense => 'paidLabel',
      _TxBucket.refund => 'refundedLabel',
      _TxBucket.deposit => 'depositLabel',
      _TxBucket.topupApproved => 'topupApproved',
      _TxBucket.topupRefunded => 'topupRefunded',
      _TxBucket.topupRejected => 'topupRejected',
      _TxBucket.topupReviewing => 'topupReviewing',
      _TxBucket.changeCredit => 'changeCredit',
    };
    final icon = switch (bucket) {
      _TxBucket.expense => Icons.north_east_rounded,
      _TxBucket.topupApproved => Icons.check_rounded,
      _TxBucket.topupRefunded => Icons.replay_rounded,
      _TxBucket.topupRejected => Icons.close_rounded,
      _TxBucket.topupReviewing => Icons.question_mark_rounded,
      _TxBucket.changeCredit => Icons.currency_exchange_rounded,
      _ => Icons.south_west_rounded,
    };
    final description = data['description']?.toString() ??
        data['title']?.toString() ??
        data['type']?.toString() ??
        L10n.t(context, 'walletActivity');
    final title = bucket == _TxBucket.changeCredit ||
            bucket == _TxBucket.topupApproved ||
            bucket == _TxBucket.topupRefunded ||
            bucket == _TxBucket.topupRejected ||
            bucket == _TxBucket.topupReviewing
        ? L10n.t(context, labelKey)
        : '${L10n.t(context, labelKey)} · $description';
    final amountPrefix = bucket == _TxBucket.topupRejected ||
            bucket == _TxBucket.topupReviewing
        ? ''
        : sign;

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          Text(
            '$amountPrefix${Formatters.currency(amount.abs())}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

double _num(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

bool _isExpense(Map<String, dynamic> data) {
  final type = data['type']?.toString().toUpperCase() ?? '';
  final direction = data['direction']?.toString().toUpperCase() ?? '';
  final amount = _num(data['amount']);
  return direction == 'DEBIT' ||
      type.contains('RESERVATION_PAYMENT') ||
      type.contains('PAYMENT') ||
      type.contains('DEBIT') ||
      amount < 0;
}

DateTime _date(Object? v) =>
    DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
