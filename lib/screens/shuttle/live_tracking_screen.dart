import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/shuttle.dart';
import '../../services/live_tracking_service.dart';
import '../../services/passenger_api.dart';
import '../../services/passenger_location_service.dart';
import '../../widgets/google_map_kit.dart';
import 'dart:math' as math;

import '../../widgets/map_markers.dart';
import '../../widgets/user_location_marker.dart';

/// Full-screen live minibus tracking. A fresh driver GPS fix from the backend
/// is preferred; the timetable estimate is used only while GPS is unavailable.
class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with SingleTickerProviderStateMixin {
  Ticket? _ticket;
  LiveTripTracker? _tracker;
  ShuttleStop? _pickup;

  Timer? _timer;
  bool _refreshing = false;
  late final AnimationController _move;

  gm.GoogleMapController? _map;
  bool _mapReady = false;
  bool _cameraFitted = false;
  bool _locating = false;

  LatLng? _from;
  LatLng? _to;

  // Preloaded marker icons so the animated bus marker can be rebuilt cheaply
  // on every animation tick without awaiting platform calls inside build().
  gm.BitmapDescriptor? _originIcon;
  gm.BitmapDescriptor? _destIcon;
  gm.BitmapDescriptor? _wayIcon;
  gm.BitmapDescriptor? _userIcon;
  gm.BitmapDescriptor? _vehicleIcon;
  Set<gm.Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _move = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(() {
      if (mounted) setState(() {});
    });
    final location = PassengerLocationService.instance;
    location.addListener(_onLocationChanged);
    unawaited(location.start());
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveTicket());
  }

  void _onLocationChanged() {
    if (!mounted) return;
    setState(() {});
    final pos = PassengerLocationService.instance.currentPosition;
    if (!_cameraFitted && pos != null && _mapReady) {
      _cameraFitted = true;
      final pts = _tracker?.path.points ?? const <LatLng>[];
      if (pts.isEmpty) {
        _moveCamera(pos, 16);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _map == null) return;
        _map!.moveCamera(
          cameraForBounds(
            [...pts, pos],
            padding: 120,
          ),
        );
      });
    }
  }

  void _moveCamera(LatLng target, double zoom) {
    final controller = _map;
    if (controller == null) return;
    controller.moveCamera(
      gm.CameraUpdate.newCameraPosition(
        gm.CameraPosition(target: toGm(target), zoom: zoom),
      ),
    );
  }

  /// Requests permission, grabs a fix and snaps the camera to the
  /// passenger so they always know where they are on the route.
  Future<void> _locateMe() async {
    final location = PassengerLocationService.instance;
    setState(() => _locating = true);
    try {
      if (!await location.ensurePermission()) {
        if (mounted) _toast(L10n.t(context, 'locationDenied'));
        return;
      }
      final pos = await location.getSingleFix();
      if (!mounted) return;
      if (pos == null) {
        _toast(L10n.t(context, 'locationUnavailable'));
        return;
      }
      _moveCamera(pos, 16);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _resolveTicket() {
    final args = ModalRoute.of(context)?.settings.arguments;
    final ticket =
        args is Ticket
            ? args
            : args is LiveTrackingArgs
            ? args.ticket
            : null;
    if (ticket == null || !mounted) return;
    setState(() {
      _ticket = ticket;
      _tracker = LiveTripTracker.fromTicket(ticket);
      _pickup = pickupStopFor(ticket);
      final now = DateTime.now();
      final pos = ticket.driver?.livePosition(now) ?? _tracker!.positionAt(now);
      _from = pos;
      _to = pos;
    });
    unawaited(_setupMaps(ticket));
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshAndTick(),
    );
  }

  /// Resolves the self-gesture icons:
  ///   RecognizerKind.singleTap default taps the live map.
  Future<void> _setupMaps(Ticket ticket) async {
    final seats = ticket.vehicleClass?.seats ?? 14;
    final pts = ticket.vehicleClass == null
        ? const <LatLng>[]
        : _tracker?.path.points ?? const <LatLng>[];
    final results = await Future.wait(<Future<Object>>[
      originDot(AppColors.accent),
      destinationPin(AppColors.accent),
      waypointDot(AppColors.textTertiary),
      userDot(const Color(0xFF1E88E5)),
      vehicleIconForSeats(seats),
    ]);
    if (!mounted) return;
    setState(() {
      _originIcon = results[0] as gm.BitmapDescriptor;
      _destIcon = results[1] as gm.BitmapDescriptor;
      _wayIcon = results[2] as gm.BitmapDescriptor;
      _userIcon = results[3] as gm.BitmapDescriptor;
      _vehicleIcon = results[4] as gm.BitmapDescriptor;
    });
    if (pts.length < 2) return;
    final stripColor = ticket.vehicleClass?.color ?? AppColors.accent;
    final polylines = await routePolylines(
      id: 'track-route',
      points: pts,
      color: stripColor,
    );
    if (!mounted) return;
    setState(() => _polylines = {...polylines});
  }

  void _fitCameraToRoute() {
    final controller = _map;
    if (controller == null) return;
    final pts = _tracker?.path.points ?? const <LatLng>[];
    if (pts.isEmpty) return;
    controller.moveCamera(cameraForBounds(pts, padding: 120));
  }

  /// Builds the live map markers synchronously from preloaded icons: the
  /// route stops, the animated bus and the passenger's dot.
  Set<gm.Marker> _buildMarkers(List<LatLng> pts, LatLng? busPos) {
    final markers = <gm.Marker>{};
    for (var i = 0; i < pts.length; i++) {
      final icon = i == 0
          ? _originIcon
          : i == pts.length - 1
          ? _destIcon
          : _wayIcon;
      if (icon == null) continue;
      markers.add(
        gm.Marker(
          markerId: gm.MarkerId('stop-$i'),
          position: toGm(pts[i]),
          icon: icon,
          anchor: Offset(0.5, i == pts.length - 1 ? 0.95 : 0.5),
          zIndexInt: 2,
        ),
      );
    }
    final vehicleIcon = _vehicleIcon;
    if (busPos != null && vehicleIcon != null) {
      markers.add(
        gm.Marker(
          markerId: const gm.MarkerId('bus'),
          position: toGm(busPos),
          icon: vehicleIcon,
          rotation: _busBearing,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 20,
        ),
      );
    }
    final userIcon = _userIcon;
    final userPos = PassengerLocationService.instance.currentPosition;
    if (userPos != null && userIcon != null) {
      markers.add(
        gm.Marker(
          markerId: const gm.MarkerId('me'),
          position: toGm(userPos),
          icon: userIcon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 30,
        ),
      );
    }
    return markers;
  }

  Future<void> _refreshAndTick() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final ticketId = _ticket?.id;
      if (ticketId != null && passengerApi.isLoggedIn) {
        final rows = await passengerApi.getReservations();
        for (final row in rows.whereType<Map>()) {
          if (row['id']?.toString() != ticketId) continue;
          final refreshed = Ticket.fromJson(Map<String, dynamic>.from(row));
          if (!mounted) return;
          _ticket = refreshed;
          _tracker = LiveTripTracker.fromTicket(refreshed);
          _pickup = pickupStopFor(refreshed);
          break;
        }
      }
    } catch (_) {
      // Keep the last known fix and continue with the timetable estimate.
    } finally {
      _refreshing = false;
    }

    final tracker = _tracker;
    if (tracker == null || !mounted) return;
    final now = DateTime.now();
    final next = _ticket?.driver?.livePosition(now) ?? tracker.positionAt(now);
    if (next == null) {
      setState(() {});
      return;
    }
    if (_to == null) {
      setState(() {
        _from = next;
        _to = next;
      });
      return;
    }
    _from = _to;
    _to = next;
    _move.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _move.dispose();
    PassengerLocationService.instance.stop();
    PassengerLocationService.instance.removeListener(_onLocationChanged);
    _map?.dispose();
    super.dispose();
  }

  double _busBearing = 0;

  LatLng? get _displayPos {
    if (_from == null || _to == null) return null;
    final t = Curves.easeOutCubic.transform(_move.value);
    return LatLng(
      _from!.latitude + (_to!.latitude - _from!.latitude) * t,
      _from!.longitude + (_to!.longitude - _from!.longitude) * t,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    if (ticket == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'liveTrack'))),
        body: Center(child: Text(L10n.t(context, 'noTicketToDisplay'))),
      );
    }
    final tracker = _tracker!;
    final path = tracker.path;
    final pts = path.points;
    final now = DateTime.now();
    final eta = tracker.eta(now);
    final liveGps = ticket.driver?.livePosition(now);
    final remaining =
        liveGps == null
            ? tracker.remainingStops(now)
            : tracker.remainingStopsFromPosition(liveGps);
    final km =
        liveGps == null
            ? tracker.kmToPickup(now, _pickup)
            : path.kmFromPositionToStop(liveGps, _pickup);
    final departed = tracker.hasDeparted(now);
    final busPos = _displayPos ?? (pts.isNotEmpty ? pts.first : null);
    if (_from != null && _to != null && (_from!.latitude != _to!.latitude || _from!.longitude != _to!.longitude)) {
      final dy = _to!.latitude - _from!.latitude;
      final dx = _to!.longitude - _from!.longitude;
      _busBearing = (math.atan2(dx, dy) * 180 / math.pi);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'liveTrack')),
        actions: [
          if (_pickup != null &&
              (_pickup!.latitude != 0 || _pickup!.longitude != 0))
            IconButton(
              icon: const Icon(Icons.navigation_outlined),
              tooltip: L10n.t(context, 'navigate'),
              onPressed: () =>
                  launchNavigation(_pickup!.latitude, _pickup!.longitude),
            ),
          IconButton(
            icon: const Icon(Icons.headset_mic_outlined),
            tooltip: L10n.t(context, 'contactSupport'),
            onPressed: () => Navigator.of(context).pushNamed('/call-center'),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map fills the screen; the info panel floats on top.
          if (pts.length >= 2)
            Positioned.fill(
              child: gm.GoogleMap(
                initialCameraPosition: gm.CameraPosition(
                  target: toGm(pts.first),
                  zoom: 12,
                ),
                onMapCreated: (c) {
                  _map = c;
                  setState(() => _mapReady = true);
                  _fitCameraToRoute();
                },
                markers: _buildMarkers(pts, busPos),
                polylines: _polylines,
                style: googleMapStyle(),
                zoomControlsEnabled: false,
                compassEnabled: true,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                myLocationEnabled: false,
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
              ),
            ),
          // Info panel --------------------------------------------------------
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? AppColors.surfaceDarkElevated
                          : AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                liveGps != null
                                    ? L10n.t(context, 'liveGps')
                                    : departed
                                    ? L10n.t(context, 'onTheMove')
                                    : L10n.t(context, 'liveNow'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${ticket.from} → ${ticket.to}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _stat(
                          icon: Icons.schedule_rounded,
                          value: _countdown(context, eta),
                          label: L10n.t(context, 'arrivingIn'),
                          accent: true,
                        ),
                        _divider(),
                        _stat(
                          icon: Icons.alt_route_rounded,
                          value: '$remaining',
                          label: L10n.t(context, 'remainingStops'),
                        ),
                        _divider(),
                        _stat(
                          icon: Icons.near_me_rounded,
                          value: km == null ? '—' : Formatters.distanceKm(km),
                          label: L10n.t(context, 'yourPickup'),
                        ),
                      ],
                    ),
                    if (ticket.driver != null &&
                        (ticket.driver!.isAssigned)) ...[
                      const SizedBox(height: 14),
                      Divider(color: AppColors.divider, height: 1),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.accentSoft,
                            backgroundImage:
                                (ticket.driver!.photoUrl != null &&
                                        ticket.driver!.photoUrl!.isNotEmpty)
                                    ? NetworkImage(
                                      Formatters.imageUrl(
                                        ticket.driver!.photoUrl,
                                      ),
                                    )
                                    : null,
                            child:
                                (ticket.driver!.photoUrl == null ||
                                        ticket.driver!.photoUrl!.isEmpty)
                                    ? const Icon(
                                      Icons.person,
                                      size: 18,
                                      color: AppColors.accent,
                                    )
                                    : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ticket.driver!.name ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                if (ticket.driver!.carModel != null &&
                                    ticket.driver!.carModel!.isNotEmpty)
                                  Text(
                                    ticket.driver!.carModel!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (ticket.driver!.carPhotoUrl != null &&
                              ticket.driver!.carPhotoUrl!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  Formatters.imageUrl(
                                    ticket.driver!.carPhotoUrl,
                                  ),
                                  width: 44,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          if (ticket.driver!.carPlateNumber != null &&
                              ticket.driver!.carPlateNumber!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.ink,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                ticket.driver!.carPlateNumber!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
Center(
                        child: Text(
                          L10n.t(
                            context,
                            liveGps != null
                                ? 'liveGpsPositionNote'
                                : 'estimatedPositionNote',
                          ),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Locate me --------------------------------------------------------
          Positioned(
            right: 16,
            bottom: 165,
            child: SafeArea(
              top: false,
              child: LocateMeButton(
                busy: _locating,
                tooltip: L10n.t(context, 'locateMe'),
                onTap: _locateMe,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required String value,
    required String label,
    bool accent = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(
            icon,
            size: 18,
            color: accent ? AppColors.accent : AppColors.textTertiary,
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: accent ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 40, color: AppColors.divider);
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

/// Route arguments for the live tracking screen.
class LiveTrackingArgs {
  final Ticket ticket;
  const LiveTrackingArgs({required this.ticket});
}
