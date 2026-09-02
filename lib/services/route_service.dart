import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A decoded road route with distance + duration.
class GeoRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final int durationSeconds;

  const GeoRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

/// Road-route helper: fetches a driving polyline from the SoftCar maps API
/// (`POST https://softcarshuttle.com/api/maps/route`) and decodes the
/// returned Google-encoded polyline into [LatLng] points.
///
/// No auth is required, but the endpoint is rate-limited (~90 req/min) so
/// every result is cached in memory and callers fall back to straight lines
/// whenever the fetch fails.
class RouteService {
  RouteService._();

  static const _base = 'https://softcarshuttle.com/api/maps/route';

  static final Map<String, List<LatLng>> _cache = {};

  /// Decodes a Google encoded polyline string into a list of [LatLng].
  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    final len = encoded.length;
    var lat = 0;
    var lng = 0;

    while (index < len) {
      var b = 0;
      var shift = 0;
      var result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < len);
      final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < len);
      final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  /// Fetches a road-following route between the ordered [points] (the trip's
  /// geo stops). Returns null on any failure so callers can render a straight
  /// line instead. Cached in memory per point-set.
  static Future<List<LatLng>?> fetchRoadRoute(List<LatLng> points) async {
    if (points.length < 2) return null;
    final key =
        points.map((p) => '${p.latitude},${p.longitude}').join('|');
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final res = await http
          .post(
            Uri.parse(_base),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'points': [
                for (final p in points)
                  {'lat': p.latitude, 'lng': p.longitude},
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 400) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final data = decoded['data'];
      final poly =
          data is Map ? data['polyline'] : decoded['polyline'];
      if (poly is! String || poly.isEmpty) return null;
      final route = decodePolyline(poly);
      if (route.length < 2) return null;
      _cache[key] = route;
      return route;
    } catch (_) {
      return null;
    }
  }

  // ---- OSRM alternative routes (M3) -----------------------------------------

  static const _osrmBase = 'https://router.project-osrm.org/route/v1/driving';

  /// Fetches alternative routes directly from OSRM public API.
  /// Returns a list of [GeoRoute] (at least one — the primary).
  Future<List<GeoRoute>> fetchAlternatives(
    LatLng origin,
    LatLng destination,
  ) async {
    if (origin == destination) return [];
    final coords = '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';
    final uri = Uri.parse(
      '$_osrmBase/$coords'
      '?alternatives=true&overview=full&geometries=polyline&steps=false',
    );
    try {
      final res = await http.get(uri);
      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic> || json['code'] != 'Ok') return [];
      final routesRaw = json['routes'];
      if (routesRaw is! List) return [];
      return routesRaw.map<GeoRoute>((r) {
        final polyline = r['geometry']?.toString() ?? '';
        return GeoRoute(
          points: decodePolyline(polyline),
          distanceMeters: (r['distance'] as num?)?.toDouble() ?? 0,
          durationSeconds: ((r['duration'] as num?)?.toDouble() ?? 0).round(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
