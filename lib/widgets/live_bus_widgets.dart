import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../core/l10n/l10n.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/egypt_map_style.dart';
import '../core/utils/formatters.dart';
import '../models/shuttle.dart';
import '../services/live_tracking_service.dart';
import '../services/passenger_location_service.dart';
import 'road_route_layer.dart';
import 'user_location_marker.dart';

/// Compact live-status strip used on the home "boarding next" card. Polls a
/// timer every ~5s to refresh the displayed bus position along the route and
/// shows the distance to the passenger's stop plus the ETA countdown. Tapping
/// opens the full-screen live tracking map.
class LiveBusStrip extends StatefulWidget {
  final Ticket ticket;
  const LiveBusStrip({super.key, required this.ticket});

  @override
  State<LiveBusStrip> createState() => _LiveBusStripState();
}

class _LiveBusStripState extends State<LiveBusStrip> {
  Timer? _timer;
  late final LiveTripTracker _tracker;
  late final ShuttleStop? _stop;

  @override
  void initState() {
    super.initState();
    _tracker = LiveTripTracker.fromTicket(widget.ticket);
    _stop = pickupStopFor(widget.ticket);
    if (_tracker.path.isNotEmpty) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tracker.path.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final liveGps = widget.ticket.driver?.livePosition(now);
    final position = liveGps ?? _tracker.positionAt(now);
    if (position == null) return const SizedBox.shrink();
    final km =
        liveGps == null
            ? _tracker.kmToPickup(now, _stop)
            : _tracker.path.kmFromPositionToStop(liveGps, _stop);
    final eta = _tracker.eta(now);
    final fraction = _tracker.fractionAt(now);
    final departed = _tracker.hasDeparted(now);

    return GestureDetector(
      onTap:
          () => Navigator.of(
            context,
          ).pushNamed('/live-tracking', arguments: widget.ticket),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _PulseDot(),
                const SizedBox(width: 6),
                Text(
                  departed
                      ? L10n.t(context, 'onTheMove')
                      : '${L10n.t(context, 'arrivingIn')} ${_countdown(context, eta)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
                const Spacer(),
                if (km != null)
                  Text(
                    L10n.t(
                      context,
                      'kmToStop',
                    ).replaceFirst('{km}', Formatters.distanceKm(km)),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 5,
                color: AppColors.accent,
                backgroundColor: AppColors.accent.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _countdown(BuildContext context, Duration d) {
    final min = d.inMinutes;
    final h = min ~/ 60;
    final m = min % 60;
    if (min < 1) return L10n.t(context, 'nowShort');
    if (h > 0) {
      return '$h${L10n.t(context, 'hoursShort')} '
          '$m${L10n.t(context, 'minutesShort')}';
    }
    return '$m${L10n.t(context, 'minutesShort')}';
  }
}

/// Full live-tracking card used on the ticket screen: a mini map with the
/// route polyline + moving bus marker, ETA, remaining stops and distance to
/// the passenger's pickup. Tapping opens the full-screen live tracking map.
class LiveBusCard extends StatefulWidget {
  final Ticket ticket;
  const LiveBusCard({super.key, required this.ticket});

  @override
  State<LiveBusCard> createState() => _LiveBusCardState();
}

class _LiveBusCardState extends State<LiveBusCard> {
  Timer? _timer;
  late final LiveTripTracker _tracker;
  late final ShuttleStop? _stop;
  final MapController _map = MapController();
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _tracker = LiveTripTracker.fromTicket(widget.ticket);
    _stop = pickupStopFor(widget.ticket);
    if (_tracker.path.isNotEmpty) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) setState(() {});
      });
    }
    final location = PassengerLocationService.instance;
    location.addListener(_onLocationChanged);
    unawaited(location.start());
  }

  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    final location = PassengerLocationService.instance;
    location.removeListener(_onLocationChanged);
    location.stop();
    _map.dispose();
    super.dispose();
  }

  /// Recenters the mini map on the passenger's current device position.
  Future<void> _locateMe() async {
    final location = PassengerLocationService.instance;
    setState(() => _locating = true);
    try {
      final pos = await location.getSingleFix();
      if (!mounted) return;
      if (pos == null) {
        _snack(L10n.t(context, 'locationUnavailable'));
        return;
      }
      _map.move(pos, 15);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_tracker.path.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final liveGps = widget.ticket.driver?.livePosition(now);
    final position = liveGps ?? _tracker.positionAt(now);
    if (position == null) return const SizedBox.shrink();
    final km =
        liveGps == null
            ? _tracker.kmToPickup(now, _stop)
            : _tracker.path.kmFromPositionToStop(liveGps, _stop);
    final eta = _tracker.eta(now);
    final remaining =
        liveGps == null
            ? _tracker.remainingStops(now)
            : _tracker.remainingStopsFromPosition(liveGps);
    final pts = _tracker.path.points;
    final stripColor = widget.ticket.vehicleClass?.color ?? AppColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 170,
            child: Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(pts),
                        padding: const EdgeInsets.all(30),
                      ),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: tileUrlForTime(),
                        subdomains: subdomainsForTime() ?? const [],
                        userAgentPackageName: 'com.softcar.shuttle',
                      ),
                      RoadRoutePolyline(
                        points: pts,
                        color: stripColor,
                        strokeWidth: 3.5,
                      ),
                      MarkerLayer(
                        markers: [
                          for (var i = 0; i < pts.length; i++)
                            Marker(
                              point: pts[i],
                              width: 28,
                              height: 28,
                              child: Icon(
                                i == 0
                                    ? Icons.trip_origin
                                    : i == pts.length - 1
                                    ? Icons.fmd_good_rounded
                                    : Icons.circle,
                                size: i == 0 || i == pts.length - 1 ? 22 : 10,
                                color:
                                    i == 0 || i == pts.length - 1
                                        ? stripColor
                                        : AppColors.textTertiary,
                              ),
                            ),
                          Marker(
                            point: position,
                            width: 34,
                            height: 34,
                            child: _BusMarker(color: stripColor),
                          ),
                          if (PassengerLocationService
                                  .instance.currentPosition !=
                              null)
                            UserLocationMarker(
                              point: PassengerLocationService
                                  .instance.currentPosition!,
                              size: 22,
                            ).toMarker(),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: LocateMeButton(
                    busy: _locating,
                    tooltip: L10n.t(context, 'locateMe'),
                    onTap: _locateMe,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const _PulseDot(),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${L10n.t(context, 'arrivingIn')} '
                '${_countdown(context, eta)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ),
            Text(
              '$remaining ${L10n.t(context, 'remainingStops')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        if (km != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.near_me_rounded,
                size: 15,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                L10n.t(
                  context,
                  'kmToStop',
                ).replaceFirst('{km}', Formatters.distanceKm(km)),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                L10n.t(
                  context,
                  liveGps == null
                      ? 'estimatedPositionNote'
                      : 'liveGpsPositionNote',
                ),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed:
                () => Navigator.of(
                  context,
                ).pushNamed('/live-tracking', arguments: widget.ticket),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(
              L10n.t(context, 'trackLive'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  static String _countdown(BuildContext context, Duration d) {
    final min = d.inMinutes;
    final h = min ~/ 60;
    final m = min % 60;
    if (min < 1) return L10n.t(context, 'nowShort');
    if (h > 0) {
      return '$h${L10n.t(context, 'hoursShort')} '
          '$m${L10n.t(context, 'minutesShort')}';
    }
    return '$m${L10n.t(context, 'minutesShort')}';
  }
}

/// The animated "live" dot used by both widgets.
class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

/// Minibus marker rendered on top of the map at the latest known position.
class _BusMarker extends StatelessWidget {
  final Color color;
  const _BusMarker({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(
        Icons.airport_shuttle_rounded,
        color: Colors.white,
        size: 18,
      ),
    );
  }
}
