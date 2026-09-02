import 'package:intl/intl.dart';

/// Fixed wall-clock offset used to render backend timestamps as Egypt time
/// (Egypt Standard Time, UTC+3).
const Duration kEgyptOffset = Duration(hours: 3);

/// Re-bases a parsed backend [dt] onto Egypt wall clock, exactly once.
///
/// Backend instants arrive as ISO-8601 strings that may carry `Z` / an
/// explicit offset or be offset-naive; in both cases the parsed wall-clock
/// fields are read as UTC-instant fields, shifted by [kEgyptOffset], and
/// returned as a naive local-kind `DateTime` holding Cairo wall time so that
/// `intl` renders those components verbatim on any device timezone.
DateTime? egWall(DateTime? dt) {
  if (dt == null) return null;
  final shifted = DateTime.utc(
    dt.year,
    dt.month,
    dt.day,
    dt.hour,
    dt.minute,
    dt.second,
    dt.millisecond,
    dt.microsecond,
  ).add(kEgyptOffset);
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
    shifted.millisecond,
    shifted.microsecond,
  );
}

/// Formats [dt] as Egypt wall-clock time using [pattern]; '' when null.
String egFormat(DateTime? dt, String pattern) =>
    dt == null ? '' : DateFormat(pattern).format(egWall(dt)!);

/// Returns [dt] re-based to Egypt wall-clock components (e.g. for day/month
/// extraction); null passthrough.
DateTime? egDate(DateTime? dt) => egWall(dt);

/// Deprecated alias for [egWall]; kept only so stale call-sites compile.
@Deprecated('Use egWall / egFormat instead')
DateTime? toEgyptTime(DateTime? dt) => egWall(dt);
