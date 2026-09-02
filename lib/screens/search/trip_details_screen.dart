import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/egypt_time.dart';
import '../../models/shuttle.dart';
import '../../services/auth_service.dart';
import '../../services/shuttle_service.dart';
import '../../widgets/call_chooser_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/primary_button.dart';

/// Full trip details: route, time, live seats and the assigned driver
/// (name, phone, car model, plate). The primary action continues to seat
/// selection for booking. Reserve tiers for this line are listed so riders
/// can apply a subscription package.
class TripDetailsScreen extends StatefulWidget {
  const TripDetailsScreen({super.key});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  ShuttleTrip? _trip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_trip == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is ShuttleTrip) {
        _trip = args;
        final shuttle = context.read<ShuttleService>();
        Future.microtask(shuttle.loadTiers);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    if (trip == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final free = trip.seatsRemaining;
    final full = free <= 0;
    final canBook = context.watch<AuthService>().isLoggedIn;
    final shuttle = context.watch<ShuttleService>();
    final tierPacks = shuttle.tiersFor(trip);

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'tripDetails'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: PrimaryButton(
            label: full
                ? L10n.t(context, 'full')
                : trip.tripType.isRecurring
                    ? L10n.t(context, 'bookRecurring')
                    : trip.tripType.isRoundTrip
                        ? L10n.t(context, 'roundTrip')
                        : L10n.t(context, 'book'),
            accent: !full,
            onPressed: full || !canBook
                ? null
                : () => Navigator.of(context)
                    .pushNamed('/seat-selection', arguments: trip),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: trip.vehicle?.color ?? AppColors.accent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(trip.vehicle?.icon ?? Icons.directions_bus,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(trip.vehicle?.name ?? 'Shuttle',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                              const SizedBox(width: 8),
                              _TripTypeBadge(trip: trip),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            egFormat(trip.startTime, 'EEE, MMM d · HH:mm'),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Formatters.currency(trip.fareForBooking),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          trip.tripType.isRoundTrip
                              ? L10n.t(context, 'roundTripTotal')
                              : L10n.t(context, 'priceInfo'),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SeatStatus(free: free, total: trip.totalSeats),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L10n.t(context, 'route'),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                for (var i = 0; i < trip.pickupPoints.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(
                          i == 0
                              ? Icons.trip_origin
                              : i == trip.pickupPoints.length - 1
                                  ? Icons.fmd_good_rounded
                                  : Icons.circle,
                          size: i == 0 || i == trip.pickupPoints.length - 1
                              ? 16
                              : 8,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            trip.pickupPoints[i].name,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              i == 0
                                  ? L10n.t(context, 'pickup')
                                  : i == trip.pickupPoints.length - 1
                                      ? L10n.t(context, 'dropoff')
                                      : '${L10n.t(context, 'stop')} '
                                          '${trip.pickupPoints[i].stopOrder}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            Text(
                              egFormat(
                                trip.pickupPoints[i].arrivalAt(trip.startTime),
                                'HH:mm',
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _DriverDetails(trip: trip),
          const SizedBox(height: 14),
          if (tierPacks.isNotEmpty) ...[
            _TiersSection(
              tiers: tierPacks,
              trip: trip,
              onApply: (tier) => Navigator.of(context).pushNamed(
                '/seat-selection',
                arguments: SeatSelectionArgs(trip: trip, tier: tier),
              ),
            ),
            const SizedBox(height: 14),
          ],
          SoftCard(
            child: Row(
              children: [
                const Icon(Icons.event_seat_outlined,
                    color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    full
                        ? L10n.t(context, 'full')
                        : '$free / ${trip.totalSeats} '
                            '${L10n.t(context, 'seatsRemaining')}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.circle,
                    color: AppColors.accent, size: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatStatus extends StatelessWidget {
  final int free;
  final int total;
  const _SeatStatus({required this.free, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? free / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(L10n.t(context, 'liveSeats'),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const Spacer(),
            Text(
              free > 0 ? '$free / $total' : L10n.t(context, 'full'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: free > 0 ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.inkSoft,
            valueColor: const AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
      ],
    );
  }
}

class _DriverDetails extends StatelessWidget {
  final ShuttleTrip trip;
  const _DriverDetails({required this.trip});

  @override
  Widget build(BuildContext context) {
    final driver = trip.driver;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.t(context, 'assignedDriver'),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (driver == null || !driver.isAssigned)
            Row(
              children: [
                const Icon(Icons.person_outline,
                    color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    L10n.t(context, 'driverNotAssigned'),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.accentSoft,
                  backgroundImage:
                      driver.photoUrl != null && driver.photoUrl!.isNotEmpty
                          ? NetworkImage(Formatters.imageUrl(driver.photoUrl))
                          : null,
                  child: driver.photoUrl == null || driver.photoUrl!.isEmpty
                      ? const Icon(Icons.person, color: AppColors.accent)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driver.name ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      if (driver.phone != null && driver.phone!.isNotEmpty)
                        Text(driver.phone!,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      if (driver.carModel != null &&
                          driver.carModel!.isNotEmpty)
                        Text(driver.carModel!,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if ((driver.userId?.isNotEmpty ?? false) ||
                    (driver.phone?.isNotEmpty ?? false))
                  InkWell(
                    onTap: () => showCallChooser(
                      context,
                      targetUserId: driver.userId ?? 'DRIVER',
                      displayName:
                          driver.name ?? L10n.t(context, 'assignedDriver'),
                      phone: driver.phone,
                      tripId: trip.id,
                    ),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.success.withValues(alpha: 0.12),
                      ),
                      child: const Icon(Icons.call_rounded,
                          size: 20, color: AppColors.success),
                    ),
                  ),
                if (driver.carPhotoUrl != null &&
                    driver.carPhotoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      driver.carPhotoUrl!,
                      width: 64,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
if (driver.carPlateNumber != null &&
                driver.carPlateNumber!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.local_taxi,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  const Text('• '),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      driver.carPlateNumber!,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.2),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Badge that names the trip's booking type (one-time / recurring / round-trip).
class _TripTypeBadge extends StatelessWidget {
  final ShuttleTrip trip;
  const _TripTypeBadge({required this.trip});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (trip.tripType) {
      TripType.recurring => (
          L10n.t(context, 'recurringTrip'),
          AppColors.info,
          Icons.repeat_rounded
        ),
      TripType.roundTrip => (
          L10n.t(context, 'roundTrip'),
          AppColors.warning,
          Icons.swap_horiz_rounded
        ),
      _ => (L10n.t(context, 'oneTimeTrip'), AppColors.success, Icons.event)
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}

/// Reserve tiers available on this trip, each with a primary "apply" action
/// that opens seat selection with the tier pre-selected.
class _TiersSection extends StatelessWidget {
  final ShuttleTrip trip;
  final List<ReservationTier> tiers;
  final ValueChanged<ReservationTier> onApply;
  const _TiersSection({
    required this.trip,
    required this.tiers,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.sell_outlined, color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            Text(L10n.t(context, 'reserveTiers'),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 6),
        Text(L10n.t(context, 'reserveTiersSub'),
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        for (final tier in tiers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TierCard(trip: trip, tier: tier, onApply: onApply),
          ),
      ],
    );
  }
}

class _TierCard extends StatefulWidget {
  final ShuttleTrip trip;
  final ReservationTier tier;
  final ValueChanged<ReservationTier> onApply;
  const _TierCard({
    required this.trip,
    required this.tier,
    required this.onApply,
  });

  @override
  State<_TierCard> createState() => _TierCardState();
}

class _TierCardState extends State<_TierCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tier = widget.tier;
    final trip = widget.trip;
    return SoftCard(
      child: Container(
        decoration: BoxDecoration(
          border: tier.isRecommended
              ? Border.all(color: AppColors.accent, width: 1.4)
              : null,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tier.name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (tier.isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      L10n.t(context, 'recommended'),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
              ],
            ),
            if (tier.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(tier.description,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  tier.packagePrice == 0
                      ? '${tier.packagePrice == tier.originalPrice ? tier.originalPrice : 0}'
                      : '${tier.packagePrice.toInt()}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(L10n.t(context, 'perPass'),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ),
                if (tier.savings > 0) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      L10n.t(context, 'saves')
                          .replaceFirst('{amount}',
                              '${tier.savings.toInt()} EGP'),
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.success,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
                const Spacer(),
                if (tier.durationDays > 0)
                  Text(
                    L10n.t(context, 'daysDuration')
                        .replaceFirst('{days}', '${tier.durationDays}'),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (tier.minimumSeats > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      L10n.t(context, 'minimumSeats')
                          .replaceFirst('{n}', '${tier.minimumSeats}'),
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white70
                              : AppColors.textSecondary),
                    ),
                  ),
                if (tier.maximumSeats > 0)
                  Text(
                    L10n.t(context, 'maximumSeats')
                        .replaceFirst('{n}', '${tier.maximumSeats}'),
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.white70
                            : AppColors.textSecondary),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showTierDetails(context, tier, widget.onApply),
                  child: Row(
                    children: [
                      Text(L10n.t(context, 'tierDetails'),
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right,
                          size: 15, color: AppColors.accent),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded
                          ? L10n.t(context, 'showLess')
                          : L10n.t(context, 'showMore'),
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              if (tier.durationDays > 0)
                TierCoveredDays(tier: tier, trip: trip),
              if (trip.tripType.isRoundTrip && trip.returnTrip != null) ...[
                const SizedBox(height: 12),
                TierLegsSection(trip: trip),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.t(context, 'originalPrice'),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(Formatters.currency(tier.originalPrice),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textTertiary,
                                decoration: TextDecoration.lineThrough)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.t(context, 'packagePrice'),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(Formatters.currency(tier.packagePrice),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: AppColors.accent)),
                      ],
                    ),
                  ),
                  if (tier.validFrom != null ||
                      tier.validUntil != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(L10n.t(context, 'validDates'),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            tier.validFrom != null
                                ? egFormat(tier.validFrom!, 'MMM d')
                                : '—',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                          if (tier.validUntil != null)
                            Text(
                              '→ ${egFormat(tier.validUntil!, 'MMM d')}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => widget.onApply(tier),
                icon: const Icon(Icons.workspace_premium, size: 18),
                label: Text(
                  L10n.t(context, 'reserveFullPackage'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the full reserve-tier detail sheet (all `ReservationTier` fields)
/// with a bottom "Reserve full package" action that applies the tier.
Future<void> _showTierDetails(
  BuildContext context,
  ReservationTier tier,
  ValueChanged<ReservationTier> onApply,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (ctx) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.84,
          ),
          child: _TierDetailSheet(tier: tier, onApply: onApply),
        ),
  );
}

class _TierDetailSheet extends StatelessWidget {
  final ReservationTier tier;
  final ValueChanged<ReservationTier> onApply;
  const _TierDetailSheet({required this.tier, required this.onApply});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(tier.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                ),
                if (tier.isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      L10n.t(context, 'recommended'),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tier.description.isNotEmpty)
                    _DetailRow(
                      icon: Icons.notes_rounded,
                      label: '',
                      value: tier.description,
                      standalone: true,
                    ),
                  _DetailRow(
                    icon: Icons.tag_rounded,
                    label: L10n.t(context, 'tierCode'),
                    value: tier.code,
                  ),
                  if (tier.durationDays > 0)
                    _DetailRow(
                      icon: Icons.event_available_rounded,
                      label: L10n.t(context, 'daysDuration').replaceFirst(
                          '{days}', '${tier.durationDays}'),
                      value: L10n.t(context, 'perPass'),
                    ),
                  if (tier.originalPrice > 0)
                    _DetailRow(
                      icon: Icons.price_check_rounded,
                      label: L10n.t(context, 'originalPrice'),
                      value: Formatters.currency(tier.originalPrice),
                    ),
                  if (tier.packagePrice > 0)
                    _DetailRow(
                      icon: Icons.sell_outlined,
                      label: L10n.t(context, 'packagePrice'),
                      value: Formatters.currency(tier.packagePrice),
                    ),
                  if (tier.savings > 0)
                    _DetailRow(
                      icon: Icons.savings_rounded,
                      label: L10n.t(context, 'saves').replaceFirst(
                          '{amount}', '${tier.savings.toInt()} EGP'),
                      value: '',
                      standalone: true,
                    ),
                  if (tier.minimumSeats > 1)
                    _DetailRow(
                      icon: Icons.event_seat_outlined,
                      label: L10n.t(context, 'minimumSeats').replaceFirst(
                          '{n}', '${tier.minimumSeats}'),
                      value: '',
                    ),
                  if (tier.maximumSeats > 0)
                    _DetailRow(
                      icon: Icons.event_seat_rounded,
                      label: L10n.t(context, 'maximumSeats').replaceFirst(
                          '{n}', '${tier.maximumSeats}'),
                      value: '',
                    ),
                  if (tier.excludedWeekdays.isNotEmpty)
                    _DetailRow(
                      icon: Icons.calendar_today_rounded,
                      label: L10n.t(context, 'excludedWeekdays'),
                      value: tier.excludedWeekdays.join(', '),
                    ),
                  if (tier.discountPercent != null && tier.discountPercent! > 0)
                    _DetailRow(
                      icon: Icons.percent_rounded,
                      label: L10n.t(context, 'tierDiscount'),
                      value: '${tier.discountPercent!.toInt()}%',
                    ),
                  if (tier.walletBonusAmount != null &&
                      tier.walletBonusAmount! > 0)
                    _DetailRow(
                      icon: Icons.account_balance_wallet_rounded,
                      label: L10n.t(context, 'walletBonus'),
                      value:
                          Formatters.currency(tier.walletBonusAmount!.toDouble()),
                    ),
                  if (tier.priorityBooking)
                    _DetailRow(
                      icon: Icons.priority_high_rounded,
                      label: L10n.t(context, 'priorityBooking'),
                      value: '',
                      standalone: true,
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
                  if (tier.validFrom != null)
                    _DetailRow(
                      icon: Icons.event_rounded,
                      label: L10n.t(context, 'validFrom'),
                      value: egFormat(tier.validFrom!, 'MMM d, yyyy'),
                    ),
                  if (tier.validUntil != null)
                    _DetailRow(
                      icon: Icons.event_rounded,
                      label: L10n.t(context, 'validUntil'),
                      value: egFormat(tier.validUntil!, 'MMM d, yyyy'),
                    ),
                  if (tier.reservationCount > 0)
                    _DetailRow(
                      icon: Icons.confirmation_number_rounded,
                      label: L10n.t(context, 'reservationCount'),
                      value: '${tier.reservationCount}',
                    ),
                  if (tier.isActive)
                    _DetailRow(
                      icon: Icons.check_circle_rounded,
                      label: L10n.t(context, 'active'),
                      value: '',
                      standalone: true,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                onApply(tier);
              },
              child: Text(
                L10n.t(context, 'reserveFullPackage'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
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
  final bool standalone;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.standalone = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: standalone
                ? Text(
                    value.isEmpty ? label : value,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w700)),
                      if (value.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(value,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
