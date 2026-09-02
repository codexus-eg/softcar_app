import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/route_service.dart';

/// Draws a road-following route polyline on a [FlutterMap] between the trip's
/// ordered geo stops. Fetches the real driving path from the SoftCar route
/// service in the background and renders a straight line while it loads, so
/// the map never blinks and always shows a line.
class RoadRoutePolyline extends StatefulWidget {
  final List<LatLng> points;
  final Color color;
  final double strokeWidth;

  const RoadRoutePolyline({
    super.key,
    required this.points,
    required this.color,
    this.strokeWidth = 4,
  });

  @override
  State<RoadRoutePolyline> createState() => _RoadRoutePolylineState();
}

class _RoadRoutePolylineState extends State<RoadRoutePolyline> {
  List<LatLng>? _road;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RoadRoutePolyline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePoints(oldWidget.points, widget.points)) {
      _road = null;
      _load();
    }
  }

  static bool _samePoints(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude ||
          a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  Future<void> _load() async {
    final points = widget.points;
    if (points.length < 2) return;
    final road = await RouteService.fetchRoadRoute(points);
    if (!mounted || !_samePoints(points, widget.points)) return;
    setState(() => _road = road);
  }

  @override
  Widget build(BuildContext context) {
    final draw = _road ?? widget.points;
    if (draw.length < 2) return const SizedBox.shrink();
    return PolylineLayer(
      polylines: [
        Polyline(
          points: draw,
          color: widget.color,
          strokeWidth: widget.strokeWidth,
        ),
      ],
    );
  }
}