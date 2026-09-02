import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_time.dart';
import '../../core/utils/formatters.dart';
import '../../models/shuttle.dart';
import '../../services/auth_service.dart';
import '../../services/shuttle_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/primary_button.dart';

/// Full-screen detail for a reserve tier (admin package), reached from the
/// home tier carousel. Shows the tier photograph, pricing with any discount,
/// benefits parsed from `benefitsJson`, seat limits, excluded weekdays,
/// payment methods and cancellation policy. The bottom CTA ("احجز الشريحة")
/// routes to the existing booking flow with this tier pre-selected.
class TierDetailScreen extends StatefulWidget {
  const TierDetailScreen({super.key});

  @override
  State<TierDetailScreen> createState() => _TierDetailScreenState();
}

class _TierDetailScreenState extends State<TierDetailScreen> {
  ReservationTier? _tier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tier == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is ReservationTier) _tier = args;
    }
  }

  /// Routes the CTA to the existing booking flow. When the tier maps to a
  /// live trip it opens seat selection with the tier pre-selected; otherwise
  /// it drops into the search flow so the passenger can pick the ride.
  void _book(BuildContext context) {
    final tier = _tier;
    if (tier == null) return;
    final shuttle = context.read<ShuttleService>();
    final trip =
        tier.tripId != null && tier.tripId!.isNotEmpty
            ? shuttle.byTripId(tier.tripId!)
            : null;
    if (trip != null) {
      Navigator.of(
        context,
      ).pushNamed('/seat-selection', arguments: SeatSelectionArgs(trip: trip, tier: tier));
    } else {
      Navigator.of(context).pushNamed('/search');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = _tier;
    if (tier == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final canBook = context.watch<AuthService>().isLoggedIn && tier.isActive;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final img = Formatters.imageUrl(tier.imageUrl);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
            leading: const BackButton(),
            flexibleSpace: FlexibleSpaceBar(
              background: img.isEmpty
                  ? _fallbackGradient()
                  : Image.network(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallbackGradient(),
                    ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tier.name,
                            style: Theme.of(
                              context,
                            ).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (tier.code.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              tier.code,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (tier.discountPercent != null &&
                        tier.discountPercent! > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '-${tier.discountPercent!.toInt()}%',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.currency(tier.packagePrice),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (tier.originalPrice > tier.packagePrice) ...[
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          Formatters.currency(tier.originalPrice),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (tier.validUntil != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${L10n.t(context, 'validUntil')} '
                    '${egFormat(tier.validUntil, 'MMM d, yyyy')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (tier.description.isNotEmpty) ...[
                  _Section(
                    title: L10n.t(context, 'aboutTier'),
                    child: Text(
                      tier.description,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (tier.benefits.isNotEmpty) ...[
                  _Section(
                    title: L10n.t(context, 'tierBenefits'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final b in tier.benefits)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: AppColors.success,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    b,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _DetailsGrid(tier: tier),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: PrimaryButton(
            label: L10n.t(context, 'bookTier'),
            accent: canBook,
            icon: Icons.workspace_premium,
            onPressed: canBook ? () => _book(context) : null,
          ),
        ),
      ),
    );
  }

  Widget _fallbackGradient() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent, AppColors.accentDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.workspace_premium_rounded,
          size: 64,
          color: Colors.white38,
        ),
      ),
    );
  }
}

/// A titled block of content on the tier detail page.
class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// Grid of the tier's factual rows (seats, excluded weekdays, payment
/// methods, cancellation policy) mirroring the trip-details sheet style.
class _DetailsGrid extends StatelessWidget {
  final ReservationTier tier;
  const _DetailsGrid({required this.tier});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        children: [
          if (tier.minimumSeats > 1)
            _DetailRow(
              icon: Icons.event_seat_outlined,
              label: L10n.t(context, 'minimumSeats').replaceFirst(
                '{n}',
                '${tier.minimumSeats}',
              ),
            ),
          if (tier.maximumSeats > 0)
            _DetailRow(
              icon: Icons.event_seat_rounded,
              label: L10n.t(context, 'maximumSeats').replaceFirst(
                '{n}',
                '${tier.maximumSeats}',
              ),
            ),
          if (tier.excludedWeekdays.isNotEmpty)
            _DetailRow(
              icon: Icons.calendar_today_rounded,
              label: L10n.t(context, 'excludedWeekdays'),
              value: tier.excludedWeekdays.join(', '),
            ),
          if (tier.paymentMethods.isNotEmpty)
            _DetailRow(
              icon: Icons.payment_rounded,
              label: L10n.t(context, 'paymentMethods'),
              value: tier.paymentMethods.join(', '),
            ),
          if (tier.cancellationPolicy.isNotEmpty)
            _DetailRow(
              icon: Icons.fact_check_rounded,
              label: L10n.t(context, 'cancellationPolicy'),
              value: tier.cancellationPolicy,
            ),
          if (tier.isRecommended)
            _DetailRow(
              icon: Icons.recommend_rounded,
              label: L10n.t(context, 'recommended'),
              value: '',
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, this.value = ''});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isEmpty ? label : '$label · $value',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
