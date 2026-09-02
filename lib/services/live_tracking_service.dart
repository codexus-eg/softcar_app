import 'package:latlong2/latlong.dart';

import '../core/utils/formatters.dart';
import '../models/shuttle.dart';

/// The passenger app has no live GPS feed from the driver, so the minibus
/// position is *estimated*: the bus is assumed to travel along the trip's
/// pickupPoints polyline from the departure time to the estimated end time.
/// [TripLivePath] turns the ordered stops into a measurable polyline.
class TripLivePath {
  final List<ShuttleStop> stops;
  final List<LatLng> points;
  final List<double> cumulativeKm;

  TripLivePath._(this.stops, this.points, this.cumulativeKm);

  /// Builds a path from stops that carry real coordinates, preserving order.
  factory TripLivePath.fromStops(List<ShuttleStop> stops) {
    final pts = <LatLng>[];
    for (final s in stops) {
      if (s.latitude != 0 || s.longitude != 0) {
        pts.add(LatLng(s.latitude, s.longitude));
      }
    }
    final cum = <double>[];
    var acc = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) {
        acc += Formatters.haversineKm(
          pts[i - 1].latitude,
          pts[i - 1].longitude,
          pts[i].latitude,
          pts[i].longitude,
        );
      }
      cum.add(acc);
    }
    return TripLivePath._(stops, pts, cum);
  }

  double get totalKm => cumulativeKm.isEmpty ? 0 : cumulativeKm.last;

  bool get isEmpty => points.length < 2;

  bool get isNotEmpty => !isEmpty;

  /// Point at [fraction] (0..1) along the polyline, or null when there are
  /// no mapped stops.
  LatLng? at(double fraction) {
    if (points.isEmpty) return null;
    if (points.length == 1) return points.first;
    final target = totalKm * fraction.clamp(0.0, 1.0);
    for (var i = 1; i < cumulativeKm.length; i++) {
      if (cumulativeKm[i] >= target) {
        final seg = cumulativeKm[i] - cumulativeKm[i - 1];
        if (seg <= 0) return points[i];
        final f = (target - cumulativeKm[i - 1]) / seg;
        final a = points[i - 1];
        final b = points[i];
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * f,
          a.longitude + (b.longitude - a.longitude) * f,
        );
      }
    }
    return points.last;
  }

  /// Straight-line distance from the bus position at [fraction] to [stop].
  /// Returns null when [stop] carries no coordinates.
  double? kmToStop(double fraction, ShuttleStop? stop) {
    if (stop == null || (stop.latitude == 0 && stop.longitude == 0)) {
      return null;
    }
    final bus = at(fraction);
    if (bus == null) return null;
    return Formatters.haversineKm(
      bus.latitude,
      bus.longitude,
      stop.latitude,
      stop.longitude,
    );
  }

  /// Straight-line distance from a real GPS position to [stop].
  double? kmFromPositionToStop(LatLng position, ShuttleStop? stop) {
    if (stop == null || (stop.latitude == 0 && stop.longitude == 0)) {
      return null;
    }
    return Formatters.haversineKm(
      position.latitude,
      position.longitude,
      stop.latitude,
      stop.longitude,
    );
  }

  /// Index (into [stops]) of the furthest mapped stop the bus has reached.
  int stopIndexAt(double fraction) {
    if (points.isEmpty) return 0;
    final target = totalKm * fraction.clamp(0.0, 1.0);
    var idx = 0;
    for (var i = 0; i < cumulativeKm.length && i < stops.length; i++) {
      if (cumulativeKm[i] <= target + 0.05) idx = i;
    }
    return idx;
  }

  /// Index of the route stop nearest to an observed GPS position.
  int stopIndexNear(LatLng position) {
    if (points.isEmpty) return 0;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = Formatters.haversineKm(
        position.latitude,
        position.longitude,
        points[i].latitude,
        points[i].longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex.clamp(0, stops.isEmpty ? 0 : stops.length - 1);
  }
}

/// Drives the live-tracking estimate for a [Ticket]: the interpolated bus
/// position, remaining stops and ETA countdown at any moment in time.
class LiveTripTracker {
  final TripLivePath path;
  final DateTime departure;
  final DateTime end;

  LiveTripTracker({required this.path, required this.departure, DateTime? end})
    : end = end ?? departure.add(const Duration(hours: 2));

  factory LiveTripTracker.fromTicket(Ticket ticket) => LiveTripTracker(
    path: TripLivePath.fromStops(ticket.pickupPoints),
    departure: ticket.departure,
    end: ticket.liveEndTime,
  );

  double get _durationSeconds => end.difference(departure).inSeconds.toDouble();

  /// How far along the route the bus is (0..1) at [now], clamped so the bus
  /// waits at the first stop before departure and stops at the last one.
  double fractionAt(DateTime now) {
    final dur = _durationSeconds;
    if (dur <= 0) return now.isBefore(departure) ? 0 : 1;
    return (now.difference(departure).inSeconds / dur).clamp(0.0, 1.0);
  }

  bool hasDeparted(DateTime now) => now.isAfter(departure);

  LatLng? positionAt(DateTime now) => path.at(fractionAt(now));

  Duration eta(DateTime now) {
    final remaining = end.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  int remainingStops(DateTime now) {
    final idx = path.stopIndexAt(fractionAt(now));
    final total = path.stops.length;
    return total > idx ? total - idx - 1 : 0;
  }

  /// The distance from the bus to the passenger's pickup stop at [now].
  double? kmToPickup(DateTime now, ShuttleStop? stop) =>
      path.kmToStop(fractionAt(now), stop);

  int remainingStopsFromPosition(LatLng position) {
    final idx = path.stopIndexNear(position);
    return path.stops.length > idx ? path.stops.length - idx - 1 : 0;
  }
}

/// Finds the passenger's pickup stop on a ticket: first the stop whose name
/// matches the ticket's pickup label, then the first mapped pickup stop.
ShuttleStop? pickupStopFor(Ticket ticket) {
  for (final s in ticket.pickupPoints) {
    if (s.name == ticket.from) return s;
  }
  for (final s in ticket.liveStops) {
    if (!s.isDropoff) return s;
  }
  return ticket.liveStops.isNotEmpty ? ticket.liveStops.first : null;
}
