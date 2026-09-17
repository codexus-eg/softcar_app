import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../models/referral_data.dart';
import '../../services/auth_service.dart';
import '../../services/passenger_api.dart';

/// Professional referral hub: the passenger's own invite code + share button,
/// live program rewards (admin-configurable), personal stats and reward history,
/// plus the apply-a-friend's-code flow when the account has no referrer yet.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  ReferralData? _data;
  bool _loading = true;
  String? _error;
  bool _sharing = false;
  bool _applying = false;
  final _codeText = TextEditingController();

  @override
  void dispose() {
    _codeText.dispose();
    super.dispose();
  }

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
      final json = await passengerApi.fetchReferral();
      if (!mounted) return;
      setState(() => _data = ReferralData.fromJson(json));
    } on PassengerApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = L10n.t(context, 'referralLoadError'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyCode() async {
    final data = _data;
    if (data == null || !data.hasCode) return;
    await Clipboard.setData(ClipboardData(text: data.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.t(context, 'copied')), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _share() async {
    final data = _data;
    if (data == null || !data.hasCode) return;
    setState(() => _sharing = true);
    final message = L10n.t(context, 'referralShareMessage').replaceAll('{code}', data.code);
    try {
      await Share.share('$message\n${data.shareUrl.isEmpty ? data.code : data.shareUrl}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'referralShareFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _applyCode() async {
    final code = _codeText.text.trim();
    if (code.isEmpty) return;
    setState(() => _applying = true);
    final err = await context.read<AuthService>().applyReferral(code);
    if (!mounted) return;
    setState(() => _applying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? L10n.t(context, 'referralApplied')),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (err == null) {
      _codeText.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'referralTitle')),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _load)
                : _buildContent(context, _data!),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ReferralData data) {
    final locale = Localizations.localeOf(context).languageCode;
    final isAr = locale == 'ar';
    final surface = Theme.of(context).colorScheme.surface;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _heroCard(context, data),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.group_outlined,
                  label: L10n.t(context, 'referralInvites'),
                  value: '${data.invites}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.monetization_on_outlined,
                  label: L10n.t(context, 'referralEarned'),
                  value: '${data.earned}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.card_giftcard_outlined,
                  label: L10n.t(context, 'referralRewards'),
                  value: data.freeTrips + data.discounts > 0
                      ? '${data.freeTrips + data.discounts}'
                      : '0',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (data.appliedReferrerName == null) ...[
            _applyCard(context, surface),
            const SizedBox(height: 16),
          ],
          _SectionLabel(L10n.t(context, 'referralHowItWorks')),
          const SizedBox(height: 8),
          _card(
            context,
            surface,
            Column(
              children: [
                _benefitRow(
                  context,
                  Icons.volunteer_activism_outlined,
                  _youGetText(context, data, isAr),
                ),
                const Divider(height: 1),
                _benefitRow(
                  context,
                  Icons.waving_hand_outlined,
                  _friendGetText(context, data, isAr),
                ),
                if (data.termsAr != null || data.termsEn != null) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Text(
                      isAr && data.termsAr != null
                          ? data.termsAr!
                          : data.termsEn ?? data.termsAr ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: dark ? AppColors.textTertiary : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(L10n.t(context, 'referralHistory')),
          const SizedBox(height: 8),
          if (data.rewards.isEmpty)
            _card(
              context,
              surface,
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    L10n.t(context, 'referralNoInvitesYet'),
                    style: TextStyle(
                      fontSize: 13,
                      color: dark ? AppColors.textTertiary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            )
          else
            ...data.rewards.take(12).map(
                  (reward) => _rewardRow(context, surface, reward),
                ),
        ],
      ),
    );
  }

  String _rewardValueLabel(String type, double value, String locale) {
    if (type == 'FREE_TRIP') return '1 رحلة مجانية';
    final suffix = locale == 'ar'
        ? (type == 'FIXED_AMOUNT_DISCOUNT' ? ' ج.م' : '% ')
        : (type == 'FIXED_AMOUNT_DISCOUNT' ? ' EGP' : '% ');
    final formatted =
        value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
    return '$formatted$suffix';
  }

  String _youGetText(BuildContext context, ReferralData data, bool isAr) {
    final reward = _rewardValueLabel(data.rewardType, data.rewardValue,
        isAr ? 'ar' : 'en');
    if (isAr) return 'تحصل على $reward عند إتمام صديقك أول رحلة مدفوعة.';
    return L10n.t(context, 'referralYouGet').replaceAll('{reward}', reward);
  }

  String _friendGetText(BuildContext context, ReferralData data, bool isAr) {
    final base = L10n.t(context, 'referralFriendGets');
    if (!data.refereeRewardEnabled) return base;
    final reward = _rewardValueLabel(
        data.refereeRewardType, data.refereeRewardValue, isAr ? 'ar' : 'en');
    return base.replaceAll('{reward}', reward);
  }

  Widget _heroCard(BuildContext context, ReferralData data) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF1A1A1F), const Color(0xFF101013)]
              : [const Color(0xFF1E1E24), const Color(0xFF0B0B0D)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.25),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.redeem_rounded,
                  color: AppColors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  L10n.t(context, 'referralInviteTitle'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data.appliedReferrerName != null
                ? L10n.t(context, 'referralJoinedBy').replaceAll('{name}', data.appliedReferrerName!)
                : L10n.t(context, 'referralSub'),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Text(
              data.hasCode ? data.code : '—',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _heroButton(
                  icon: Icons.copy_rounded,
                  label: L10n.t(context, 'copy'),
                  onTap: data.hasCode ? _copyCode : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _heroButton(
                  icon: Icons.share_outlined,
                  label: L10n.t(context, 'share'),
                  loading: _sharing,
                  onTap: data.hasCode ? _share : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _applyCard(BuildContext context, Color surface) {
    return _card(
      context,
      surface,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              L10n.t(context, 'referralHaveCode'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeText,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: L10n.t(context, 'referralCode'),
                      prefixIcon: const Icon(Icons.card_giftcard_rounded, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _applying
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : FilledButton(
                        onPressed: _applyCode,
                        child: Text(L10n.t(context, 'referralApply')),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Color surface, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.dividerDark
              : AppColors.divider,
        ),
      ),
      child: child,
    );
  }

  Widget _benefitRow(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rewardRow(BuildContext context, Color surface, ReferralReward reward) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = dark ? AppColors.textTertiary : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? AppColors.dividerDark : AppColors.divider,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: CircleAvatar(
          radius: 19,
          backgroundColor: (reward.earned ? AppColors.success : AppColors.accent)
              .withValues(alpha: 0.14),
          child: Icon(
            reward.earned ? Icons.check_rounded : Icons.schedule_rounded,
            size: 20,
            color: reward.earned ? AppColors.success : AppColors.accent,
          ),
        ),
        title: Text(
          reward.refereeName,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            reward.earned
                ? (reward.rewardLabel ?? L10n.t(context, 'referralRewardEarned'))
                : L10n.t(context, 'referralRewardPending'),
            style: TextStyle(fontSize: 12, height: 1.3, color: secondary),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              reward.status == 'EARNED' ? L10n.t(context, 'referralRewardEarnedShort') : '',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.success,
              ),
            ),
            Text(
              _formatDate(reward.createdAt),
              style: TextStyle(fontSize: 10.5, color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? AppColors.dividerDark : AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.2,
              color: dark ? AppColors.textTertiary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(L10n.t(context, 'retry')),
            ),
          ],
        ),
      ),
    );
  }
}