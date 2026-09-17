import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/egypt_map_style.dart' show isEgyptDaylight;
import '../services/route_service.dart';

/// Google Maps helpers shared by the reservation route map, the live bus
/// card and the full-screen live tracking map. Everything that used to rely
/// on flutter_map / OSM tiles now builds Google Maps primitives instead.

/// Converts a latlong2 [LatLng] to a Google [gm.LatLng].
gm.LatLng toGm(LatLng p) => gm.LatLng(p.latitude, p.longitude);

/// Converts a list of latlong2 points to Google points.
List<gm.LatLng> toGmPoints(List<LatLng> pts) => [for (final p in pts) toGm(p)];

/// Google bounding box around all [pts].
gm.LatLngBounds gmBounds(List<LatLng> pts) {
  var n = -90.0, s = 90.0, e = -180.0, w = 180.0;
  for (final p in pts) {
    if (p.latitude > n) n = p.latitude;
    if (p.latitude < s) s = p.latitude;
    if (p.longitude > e) e = p.longitude;
    if (p.longitude < w) w = p.longitude;
  }
  return gm.LatLngBounds(
    southwest: gm.LatLng(s, w),
    northeast: gm.LatLng(n, e),
  );
}

/// Camera update that frames [pts] (plus optional [extra]) with [padding].
gm.CameraUpdate cameraForBounds(
  List<LatLng> pts, {
  List<LatLng>? extra,
  double padding = 40,
}) {
  final all = [...pts, if (extra != null) ...extra];
  return gm.CameraUpdate.newLatLngBounds(gmBounds(all), padding);
}

/// Fetches the road-following route for [points] and builds a professional
/// two-layer Google [gm.Polyline] set: a soft halo under the crisp route so
/// the path reads cleanly on any map style. Falls back to a straight line
/// when the route service is unreachable, mirroring the previous behaviour.
Future<List<gm.Polyline>> routePolylines({
  required String id,
  required List<LatLng> points,
  required Color color,
  int width = 5,
}) async {
  final road = await RouteService.fetchRoadRoute(points);
  final draw = road ?? points;
  if (draw.length < 2) return const [];
  final gmPoints = toGmPoints(draw);
  final dark = !isEgyptDaylight();
  final halo = dark
      ? Colors.white.withValues(alpha: 0.18)
      : Colors.black.withValues(alpha: 0.12);
  return [
    gm.Polyline(
      polylineId: gm.PolylineId('$id-halo'),
      color: halo,
      width: width + 5,
      points: gmPoints,
    ),
    gm.Polyline(
      polylineId: gm.PolylineId(id),
      color: color,
      width: width,
      points: gmPoints,
    ),
  ];
}

/// Google Map style JSON. Returns a dark theme during Cairo night hours and
/// null (standard styling) during daylight.
String? googleMapStyle([DateTime? cairo]) {
  if (isEgyptDaylight(cairo)) return null;
  return '''
[
  {"elementType":"geometry","stylers":[{"color":"#1d2b3a"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#b8cdd4"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0d1520"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"on"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2a3a4d"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#141f2c"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#203142"}]},
  {"featureType":"poi","elementType":"labels.text","stylers":[{"color":"#6d8494"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2e4257"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#111c28"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"color":"#c9d8e0"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#25415c"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1a26"}]}
]
''';
}

/// Opens Google Maps turn-by-turn navigation to [lat],[lng].
Future<void> launchNavigation(double lat, double lng) async {
  final url =
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
      '&travelmode=driving';
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ---------------------------------------------------------------------------
// Painted marker icons (drawn once on a Canvas, cached, then used by the SDK)
// ---------------------------------------------------------------------------

final Map<String, gm.BitmapDescriptor> _iconCache = {};

/// Paints [painter] onto a square [px] PNG and returns a cached
/// [gm.BitmapDescriptor]. The painter works in a 32x32 logical canvas.
/// Icons are deliberately small (marker pixel size == on-screen dp size), so
/// stops and dots stay compact and professional instead of giant blobs.
Future<gm.BitmapDescriptor> paintIcon({
  required String key,
  required void Function(Canvas c, double s) painter,
  double px = 96,
}) async {
  final cached = _iconCache[key];
  if (cached != null) return cached;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const s = 32.0;
  canvas.scale(px / s);
  painter(canvas, s);
  final pic = recorder.endRecording();
  final img = await pic.toImage(px.toInt(), px.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final d = gm.BitmapDescriptor.bytes(data!.buffer.asUint8List());
  _iconCache[key] = d;
  return d;
}

/// Trip-origin marker: a compact white-ringed dot with a subtle centre.
/// ~36 px on screen; anchor (0.5, 0.5).
Future<gm.BitmapDescriptor> originDot(Color color) =>
    paintIcon(key: 'origin-${color.toARGB32()}', px: 36,
      painter: (c, s) {
        c.drawCircle(Offset(s / 2, s / 2), s * 0.46, Paint()..color = Colors.white);
        c.drawCircle(Offset(s / 2, s / 2), s * 0.32, Paint()..color = color);
        c.drawCircle(Offset(s / 2, s / 2), s * 0.12, Paint()..color = Colors.white);
      });

/// Destination-style teardrop pin. ~44 px tall; anchor (0.5, 0.95) so the
/// tip sits exactly on the stop.
Future<gm.BitmapDescriptor> destinationPin(Color color) =>
    paintIcon(key: 'destination-${color.toARGB32()}', px: 44,
      painter: (c, s) {
        final path = ui.Path()
          ..moveTo(s * 0.5, s * 0.04)
          ..cubicTo(s * 0.9, s * 0.24, s * 0.94, s * 0.58, s * 0.5, s * 0.96)
          ..cubicTo(s * 0.06, s * 0.58, s * 0.1, s * 0.24, s * 0.5, s * 0.04)
          ..close();
        c.drawPath(path, Paint()..color = color);
        c.drawCircle(Offset(s * 0.5, s * 0.34), s * 0.09, Paint()..color = Colors.white);
      });

/// Small intermediate-stop dot. ~18 px on screen; anchor (0.5, 0.5).
Future<gm.BitmapDescriptor> waypointDot(Color color) =>
    paintIcon(key: 'waypoint-${color.toARGB32()}', px: 26,
      painter: (c, s) {
        c.drawCircle(Offset(s / 2, s / 2), s * 0.3, Paint()..color = Colors.white);
        c.drawCircle(Offset(s / 2, s / 2), s * 0.2, Paint()..color = color);
      });

/// "You are here": a compact translucent halo, white ring and a solid
/// [color] centre. ~36 px; anchor (0.5, 0.5).
Future<gm.BitmapDescriptor> userDot(Color color) =>
    paintIcon(key: 'user-${color.toARGB32()}', px: 36,
      painter: (c, s) {
        c.drawCircle(Offset(s / 2, s / 2), s * 0.5,
            Paint()..color = color.withValues(alpha: 0.22));
        c.drawCircle(Offset(s / 2, s / 2), s * 0.36, Paint()..color = Colors.white);
        c.drawCircle(Offset(s / 2, s / 2), s * 0.27, Paint()..color = color);
      });

/// White-ringed badge filled with [bg] and an optional emoji glyph.
Future<gm.BitmapDescriptor> badgeDot(
  String key, {
  required Color bg,
  String? emoji,
}) =>
    paintIcon(key: key, px: 36,
      painter: (c, s) {
        c.drawCircle(Offset(s / 2, s / 2), s * 0.46, Paint()..color = Colors.white);
        c.drawCircle(Offset(s / 2, s / 2), s * 0.36, Paint()..color = bg);
        if (emoji != null && emoji.isNotEmpty) {
          final tp = TextPainter(
            textDirection: TextDirection.ltr,
            text: TextSpan(text: emoji, style: TextStyle(fontSize: s * 0.36)),
          )..layout();
          tp.paint(c, Offset((s - tp.width) / 2, (s - tp.height) / 2));
        }
      });