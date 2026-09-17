import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/egypt_time.dart';

bool _symbolsLoaded = false;

/// Loads the embedded CLDR date symbols once so [DateFormat] can render
/// weekday/month names for every app locale (en / ar), not just en_US.
void _ensureDateSymbols() {
  if (!_symbolsLoaded) {
    initializeDateFormatting();
    _symbolsLoaded = true;
  }
}

/// Calendar labels ('EEE' / 'd' / 'MMM') for one day, read in Egypt
/// wall-clock time and rendered for the current app locale.
class DayLabels {
  final String weekday;
  final String dayNumber;
  final String month;

  const DayLabels(this.weekday, this.dayNumber, this.month);
}

/// Resolves the [DayLabels] for [date] — the single source of the
/// weekday / day-number / month wording shared by the home day carousel
/// and every [DateBadge].
DayLabels dayLabels(BuildContext context, DateTime date) {
  _ensureDateSymbols();
  final locale = Localizations.localeOf(context).languageCode;
  final wall = egDate(date) ?? date;
  return DayLabels(
    DateFormat('EEE', locale).format(wall),
    DateFormat('d', locale).format(wall),
    DateFormat('MMM', locale).format(wall),
  );
}

/// Compact calendar-style date tile shown on trip and ticket cards:
/// weekday abbreviation on top, big day number centre, small month below —
/// the same visual language as the home day carousel. The date is rendered
/// in Egypt wall-clock time so the day always matches the backend schedule
/// regardless of the device timezone.
class DateBadge extends StatelessWidget {
  final DateTime date;
  final double width;
  final double height;

  const DateBadge({
    super.key,
    required this.date,
    this.width = 46,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labels = dayLabels(context, date);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            labels.weekday,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            labels.dayNumber,
            style: TextStyle(
              fontSize: 20,
              height: 1.0,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            labels.month,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact stacked time tile (e.g. "5:30" over "PM") used inside trip
/// cards. Splitting the meridiem onto its own smaller line keeps the tile
/// perfectly centered and avoids the cramped, unbalanced look of a single
/// "h:mm a" string squeezed into a fixed-size box.
class TimeBadge extends StatelessWidget {
  final DateTime date;
  final double width;
  final double height;
  final Color background;

  const TimeBadge({
    super.key,
    required this.date,
    this.width = 52,
    this.height = 52,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final wall = egWall(date)!;
    final hour12 = switch (wall.hour % 12) {
      0 => 12,
      final h => h,
    };
    final minute = wall.minute.toString().padLeft(2, '0');
    final period = wall.hour < 12 ? 'AM' : 'PM';
    final onColor = background.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: background.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$hour12:$minute',
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onColor,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            period,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onColor.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.4,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
