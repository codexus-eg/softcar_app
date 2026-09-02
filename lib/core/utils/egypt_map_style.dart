/// Cairo local time helpers and day/night tile switching for the passenger app.
///
/// Egypt does not observe daylight saving — the clock is fixed at UTC+2
/// year-round.  Daylight hours are 06:00 – 17:45 Cairo local time.
library;

/// Fixed UTC offset for Egypt Standard Time.
const Duration kEgyptOffset = Duration(hours: 2);

/// Returns the current Cairo wall-clock [DateTime].
DateTime cairoNow() => DateTime.now().toUtc().add(kEgyptOffset);

/// Whether [dt] falls in the daylight window (06:00–17:45 Cairo time).
///
/// When [dt] is null the current moment is evaluated.
bool isEgyptDaylight([DateTime? dt]) {
  final cairo = dt ?? cairoNow();
  final minutes = cairo.hour * 60 + cairo.minute;
  return minutes >= 360 && minutes < 1065; // 06:00 – 17:45
}

/// Light (day) tile URL template — standard OSM.
const String kDayTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Dark (night) tile URL template — CartoDB dark with subdomains.
const String kNightTileUrl =
    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

/// CartoDB dark tile subdomains.
const List<String> kNightSubdomains = ['a', 'b', 'c', 'd'];

/// Returns the appropriate tile URL template for the given Cairo moment.
String tileUrlForTime([DateTime? cairo]) =>
    isEgyptDaylight(cairo) ? kDayTileUrl : kNightTileUrl;

/// Returns the subdomains for the tile URL (only relevant for night tiles).
List<String>? subdomainsForTime([DateTime? cairo]) =>
    isEgyptDaylight(cairo) ? null : kNightSubdomains;

/// Smooth angular interpolation for bearing animations.
double lerpAngle(double a, double b, double t) {
  final diff = (b - a + 540) % 360 - 180;
  return a + diff * t;
}
