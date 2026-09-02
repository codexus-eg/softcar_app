import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../core/utils/egypt_time.dart';
import '../models/shuttle.dart';

/// Drag handle shown on top of modal bottom sheets.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white24
            : Colors.black12,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

/// Circle avatar for drivers / users with deterministic colors.
class SoftAvatar extends StatelessWidget {
  final String seed;
  final String? text;
  final double size;
  final Color? backgroundColor;
  final bool verified;

  const SoftAvatar({
    super.key,
    required this.seed,
    this.text,
    this.size = 44,
    this.backgroundColor,
    this.verified = false,
  });

  @override
  Widget build(BuildContext context) {
    final initials = text ??
        seed
            .split(' ')
            .map((p) => p.isNotEmpty ? p[0] : '')
            .take(2)
            .join()
            .toUpperCase();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor ??
                Color.lerp(
                    Colors.black, AppColors.accent, (seed.hashCode % 100) / 100),
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.36,
            ),
          ),
        ),
        if (verified)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 12, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

/// Empty state used across lists (activity, bookings, notifications).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: AppColors.accent),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// Small section label row used above lists, with SoftCar's signature
/// red accent tick on the left.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentDark],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// SoftCar's signature card: rounded on three corners with a "swoosh"
/// cut corner bottom-left — a distinctive shape that avoids the generic
/// Uber/rounded-rect look. Pass [accent] to draw the red edge stripe.
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool accent;
  final VoidCallback? onTap;
  final double radius;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.accent = false,
    this.onTap,
    this.radius = 20,
  });

  /// Path that cuts the bottom-left corner at a 45° angle.
  static Path swoosh(Size size, double r, double cut) {
    return Path()
      ..moveTo(0, r)
      ..arcToPoint(Offset(r, 0),
          radius: Radius.circular(r), clockwise: false)
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r),
          radius: Radius.circular(r), clockwise: false)
      ..lineTo(size.width, size.height - r)
      ..arcToPoint(Offset(size.width - r, size.height),
          radius: Radius.circular(r), clockwise: false)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height - cut)
      ..close();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = color ??
        (dark ? AppColors.surfaceDarkElevated : AppColors.surface);
    final card = ClipPath(
      clipper: _SwooshClipper(radius: radius),
      child: Container(
        color: bg,
        padding: padding,
        child: Stack(
          children: [
            if (accent)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.accentDark],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            child,
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

class _SwooshClipper extends CustomClipper<Path> {
  final double radius;
  const _SwooshClipper({required this.radius});

  @override
  Path getClip(Size size) {
    return SoftCard.swoosh(size, radius, radius);
  }

  @override
  bool shouldReclip(covariant _SwooshClipper oldClipper) =>
      oldClipper.radius != radius;
}

/// Horizontal strip of every calendar day a reserve [tier] covers for
/// [trip]: starts on the trip's start date and spans `durationDays`.
/// Days whose weekday is in `excludedWeekdays` are greyed out.
class TierCoveredDays extends StatelessWidget {
  final ReservationTier tier;
  final ShuttleTrip trip;
  const TierCoveredDays({super.key, required this.tier, required this.trip});

  @override
  Widget build(BuildContext context) {
    final count = tier.durationDays > 0 ? tier.durationDays : 1;
    final start = DateTime(
      trip.startTime.year,
      trip.startTime.month,
      trip.startTime.day,
    );
    final days = List.generate(count, (i) => start.add(Duration(days: i)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.event_available_rounded,
              size: 15,
              color: AppColors.accent,
            ),
            const SizedBox(width: 6),
            Text(
              L10n.t(context, 'validDates'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              L10n.t(context, 'daysCount').replaceFirst('{n}', '$count'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final day = days[i];
              final excluded = tier.excludedWeekdays.contains(day.weekday % 7);
              return Container(
                width: 40,
                decoration: BoxDecoration(
                  color: excluded
                      ? AppColors.inkSoft
                      : AppColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: excluded
                        ? AppColors.divider
                        : AppColors.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE').format(day),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: excluded
                            ? AppColors.textTertiary
                            : AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: excluded
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Outbound + return leg blocks for a round-trip [trip], shown inside a
/// reserve-tier card. Highlights that booking the tier reserves both legs.
class TierLegsSection extends StatelessWidget {
  final ShuttleTrip trip;
  const TierLegsSection({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final ret = trip.returnTrip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TierLegRow(label: L10n.t(context, 'outboundLeg'), leg: trip),
        if (ret != null) ...[
          const SizedBox(height: 6),
          _TierLegRow(
            label: L10n.t(context, 'returnLeg'),
            leg: ret,
            isReturn: true,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.swap_horiz_rounded,
                size: 14,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                L10n.t(context, 'bothLegs'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TierLegRow extends StatelessWidget {
  final String label;
  final ShuttleTrip leg;
  final bool isReturn;
  const _TierLegRow({
    required this.label,
    required this.leg,
    this.isReturn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isReturn ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 15,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · ${egFormat(leg.startTime, 'EEE, HH:mm')}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${leg.fromName} → ${leg.toName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.currency(leg.price),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppColors.accent,
                ),
              ),
              Text(
                '${leg.seatsRemaining} ${L10n.t(context, 'seatsRemaining')}',
                style: TextStyle(
                  fontSize: 10,
                  color: leg.seatsRemaining > 0
                      ? AppColors.success
                      : AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
