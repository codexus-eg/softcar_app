import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../services/passenger_api.dart';
import '../../services/passenger_location_service.dart';
import '../../widgets/google_map_kit.dart';

/// A result from the server-proxied Google Places search.
class SuggestPlace {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;

  const SuggestPlace({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  factory SuggestPlace.fromJson(Map<String, dynamic> json) {
    return SuggestPlace(
      placeId: json['placeId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'name': name,
    'address': address,
    'latitude': lat,
    'longitude': lng,
  };

  LatLng get position => LatLng(lat, lng);
}

/// "Suggest a Trip" — the passenger requests an origin/destination pair the
/// service does not yet cover. Origin is picked with a green pin, destination
/// with a red pin. Places autocomplete (server-proxied Google Places),
/// tap-on-map reverse geocoding, recent searches and a confirmation modal
/// wrap the request before it is submitted to
/// `POST /api/mobile/suggest-trip`.
class SuggestTripScreen extends StatefulWidget {
  const SuggestTripScreen({super.key});

  @override
  State<SuggestTripScreen> createState() => _SuggestTripScreenState();
}

class _SuggestTripScreenState extends State<SuggestTripScreen> {
  final _originCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  final _preferenceCtrl = TextEditingController();
  final _originFocus = FocusNode();
  final _destinationFocus = FocusNode();

  Timer? _originDebounce;
  Timer? _destinationDebounce;

  List<SuggestPlace> _originResults = [];
  List<SuggestPlace> _destinationResults = [];
  bool _searchingOrigin = false;
  bool _searchingDestination = false;

  SuggestPlace? _origin;
  SuggestPlace? _destination;
  SuggestPlace? _originPin;
  SuggestPlace? _destinationPin;
  bool _mapBusy = false;
  bool _submitting = false;
  int? _timeChipIndex;

  gm.GoogleMapController? _mapController;
  gm.CameraPosition _camera = const gm.CameraPosition(
    target: gm.LatLng(29.9071, 31.2193), // Cairo
    zoom: 10,
  );
  List<String> _recentSearches = [];
  static const _recentKey = 'softcar.passenger.suggest.recent';

  @override
  void initState() {
    super.initState();
    _originFocus.addListener(_onOriginFocus);
    _destinationFocus.addListener(_onDestinationFocus);
    unawaited(_loadRecent());
  }

  @override
  void dispose() {
    _originDebounce?.cancel();
    _destinationDebounce?.cancel();
    _originCtrl.dispose();
    _destinationCtrl.dispose();
    _preferenceCtrl.dispose();
    _originFocus.dispose();
    _destinationFocus.dispose();
    _mapController?.dispose();
    final loc = PassengerLocationService.instance;
    loc.removeListener(_onLocationChanged);
    loc.stop();
    super.dispose();
  }

  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recentSearches = raw.take(8).toList());
    } catch (_) {}
  }

  Future<void> _saveRecent(SuggestPlace place) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = List<String>.from(_recentSearches)
        ..remove(place.name)
        ..insert(0, place.name);
      final trimmed = list.take(8).toList();
      await prefs.setStringList(_recentKey, trimmed);
      if (mounted) setState(() => _recentSearches = trimmed);
    } catch (_) {}
  }

  void _onOriginFocus() {
    if (!_originFocus.hasFocus) {
      setState(() => _originResults = []);
    }
  }

  void _onDestinationFocus() {
    if (!_destinationFocus.hasFocus) {
      setState(() => _destinationResults = []);
    }
  }

  void _onOriginChanged(String q) {
    _originDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _searchingOrigin = false;
        _originResults = [];
      });
      return;
    }
    setState(() => _searchingOrigin = true);
    _originDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final results = await passengerApi.searchPlaces(q.trim());
        if (!mounted) return;
        setState(() {
          _originResults = results
              .map((e) => SuggestPlace.fromJson(e))
              .where((p) => p.name.isNotEmpty && p.lat != 0)
              .toList();
          _searchingOrigin = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searchingOrigin = false);
      }
    });
  }

  void _onDestinationChanged(String q) {
    _destinationDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _searchingDestination = false;
        _destinationResults = [];
      });
      return;
    }
    setState(() => _searchingDestination = true);
    _destinationDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final results = await passengerApi.searchPlaces(q.trim());
        if (!mounted) return;
        setState(() {
          _destinationResults = results
              .map((e) => SuggestPlace.fromJson(e))
              .where((p) => p.name.isNotEmpty && p.lat != 0)
              .toList();
          _searchingDestination = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searchingDestination = false);
      }
    });
  }

  void _selectOrigin(SuggestPlace place) {
    Haptics.selection();
    _origin = place;
    _originPin = place;
    _originCtrl.text = place.name;
    _originResults = [];
    _originFocus.unfocus();
    _saveRecent(place);
    _goTo(place.position);
    setState(() {});
    if (_destinationPin != null) unawaited(_fitPins());
  }

  void _selectDestination(SuggestPlace place) {
    Haptics.selection();
    _destination = place;
    _destinationPin = place;
    _destinationCtrl.text = place.name;
    _destinationResults = [];
    _destinationFocus.unfocus();
    _saveRecent(place);
    _goTo(place.position);
    setState(() {});
    if (_originPin != null) unawaited(_fitPins());
  }

  void _useCurrentLocation() async {
    final loc = PassengerLocationService.instance;
    loc.addListener(_onLocationChanged);
    setState(() => _mapBusy = true);
    try {
      final pos = await loc.getSingleFix();
      if (!mounted) return;
      if (pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'suggestError'))),
        );
        return;
      }
      final address = await passengerApi.reverseGeocode(
        pos.latitude,
        pos.longitude,
      );
      if (!mounted) return;
      final place = SuggestPlace(
        placeId: '',
        name: address.isEmpty
            ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'
            : address.split(',').first,
        address: address,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (_originFocus.hasFocus) {
        _selectOrigin(place);
      } else {
        _selectDestination(place);
      }
    } finally {
      if (mounted) setState(() => _mapBusy = false);
    }
  }

  void _swap() {
    Haptics.selection();
    setState(() {
      final o = _origin;
      final d = _destination;
      final op = _originPin;
      final dp = _destinationPin;
      final ot = _originCtrl.text;
      final dt = _destinationCtrl.text;
      _origin = d;
      _destination = o;
      _originPin = dp;
      _destinationPin = op;
      _originCtrl.text = dt;
      _destinationCtrl.text = ot;
    });
  }

  void _onTapMap(gm.LatLng position) async {
    final focused = _originFocus.hasFocus || _destinationFocus.hasFocus;
    if (focused) {
      FocusScope.of(context).unfocus();
    }
    setState(() => _mapBusy = true);
    final address = await passengerApi.reverseGeocode(
      position.latitude,
      position.longitude,
    );
    if (!mounted) return;
    final place = SuggestPlace(
      placeId: '',
      name: address.isEmpty
          ? '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}'
          : address.split(',').first,
      address: address,
      lat: position.latitude,
      lng: position.longitude,
    );
    if (focused && _originFocus.hasFocus) {
      _selectOrigin(place);
    } else if (focused && _destinationFocus.hasFocus) {
      _selectDestination(place);
    } else {
      // No field focused: pick the one that is still unset, else overwrite
      // the destination (the least "safe" value).
      if (_originPin == null) {
        _selectOrigin(place);
      } else if (_destinationPin == null) {
        _selectDestination(place);
      } else {
        _destinationPin = place;
        _destination = place;
        _destinationCtrl.text = place.name;
        if (_originPin != null) unawaited(_fitPins());
      }
    }
    setState(() => _mapBusy = false);
  }

  Future<void> _goTo(LatLng point) async {
    final controller = _mapController;
    if (controller == null) {
      setState(() => _camera = gm.CameraPosition(target: toGm(point), zoom: 14));
      return;
    }
    await controller.moveCamera(
      gm.CameraUpdate.newCameraPosition(
        gm.CameraPosition(target: toGm(point), zoom: 14),
      ),
    );
  }

  /// Frames both pins with padding so the route is always fully visible.
  Future<void> _fitPins() async {
    final origin = _originPin;
    final destination = _destinationPin;
    final controller = _mapController;
    if (origin == null || destination == null || controller == null) return;
    final lats = [origin.lat, destination.lat];
    final lngs = [origin.lng, destination.lng];
    final minLat = lats.reduce((a, b) => a < b ? a : b) - 0.02;
    final maxLat = lats.reduce((a, b) => a > b ? a : b) + 0.02;
    final minLng = lngs.reduce((a, b) => a < b ? a : b) - 0.02;
    final maxLng = lngs.reduce((a, b) => a > b ? a : b) + 0.02;
    await controller.animateCamera(
      gm.CameraUpdate.newLatLngBounds(
        gm.LatLngBounds(
          southwest: gm.LatLng(minLat, minLng),
          northeast: gm.LatLng(maxLat, maxLng),
        ),
        90,
      ),
    );
  }

  Set<gm.Polyline> get _polylines {
    final origin = _originPin;
    final destination = _destinationPin;
    if (origin == null || destination == null) return const {};
    return {
      gm.Polyline(
        polylineId: const gm.PolylineId('suggest-route'),
        points: [toGm(origin.position), toGm(destination.position)],
        color: AppColors.accent.withValues(alpha: 0.8),
        width: 4,
        patterns: [gm.PatternItem.dash(22), gm.PatternItem.gap(12)],
      ),
    };
  }

  Set<gm.Marker> get _markers {
    final markers = <gm.Marker>{};
    final origin = _originPin;
    final destination = _destinationPin;
    if (origin != null) {
      markers.add(
        gm.Marker(
          markerId: const gm.MarkerId('suggest-origin'),
          position: toGm(origin.position),
          anchor: const Offset(0.5, 1.0),
          icon: _pinIcon(AppColors.success),
          infoWindow: gm.InfoWindow(title: origin.name),
        ),
      );
    }
    if (destination != null) {
      markers.add(
        gm.Marker(
          markerId: const gm.MarkerId('suggest-destination'),
          position: toGm(destination.position),
          anchor: const Offset(0.5, 1.0),
          icon: _pinIcon(AppColors.error),
          infoWindow: gm.InfoWindow(title: destination.name),
        ),
      );
    }
    return markers;
  }

  gm.BitmapDescriptor _pinIcon(Color color) {
    // Return a colour-only marker using the Google default with the pin
    // header tinted; the default red pin is replaced by our colour.
    return gm.BitmapDescriptor.defaultMarkerWithHue(
      color == AppColors.success ? 120 : 0,
    );
  }

  Future<void> _submit() async {
    final origin = _originPin;
    final destination = _destinationPin;
    if (origin == null || destination == null || _submitting) return;
    Haptics.heavy();
    setState(() => _submitting = true);
    try {
      await passengerApi.suggestTrip(
        origin: origin.toJson(),
        destination: destination.toJson(),
        departureTimePreference: _preferenceCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 44,
          ),
          title: Text(
            L10n.t(context, 'suggestSent'),
            textAlign: TextAlign.center,
          ),
          content: Text(
            L10n.t(context, 'suggestSentSub'),
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context)
                  ..popUntil((route) => route.isFirst)
                  ..pushReplacementNamed('/home');
              },
              child: Text(L10n.t(context, 'suggestSentCta')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is PassengerApiException && e.status == 401
                ? L10n.t(context, 'signInToBook')
                : L10n.t(context, 'suggestError'),
          ),
        ),
      );
    }
  }

  void _onTimeChip(int? index) {
    Haptics.selection();
    setState(() {
      if (index == null || _timeChipIndex == index) {
        _timeChipIndex = null;
      } else {
        _timeChipIndex = index;
      }
    });
    final selected = _timeChipIndex;
    _preferenceCtrl.text = selected == null ? '' : _timeChipLabels[selected];
  }

  static const _timeChipKeys = [
    'suggestTimeAny',
    'suggestTimeMorning',
    'suggestTimeMidday',
    'suggestTimeEvening',
    'suggestTimeNight',
  ];
  List<String> get _timeChipLabels =>
      _timeChipKeys.map((k) => L10n.t(context, k)).toList();

  Future<void> _confirm() async {
    final origin = _originPin;
    final destination = _destinationPin;
    if (origin == null || destination == null) return;
    Haptics.selection();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'suggestConfirmTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfirmRow(label: L10n.t(context, 'suggestOrigin'), value: origin.name),
            const SizedBox(height: 10),
            _ConfirmRow(
              label: L10n.t(context, 'suggestDestination'),
              value: destination.name,
            ),
            const SizedBox(height: 14),
            Text(
              L10n.t(context, 'suggestConfirmSub'),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(context, 'suggestSubmit')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _submit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'suggestTrip')),
        actions: [
          IconButton(
            tooltip: L10n.t(context, 'suggestSwap'),
            onPressed: _swap,
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: gm.GoogleMap(
                    initialCameraPosition: _camera,
                    onMapCreated: (c) => _mapController = c,
                    onTap: _onTapMap,
                    markers: _markers,
                    polylines: _polylines,
                    mapType: gm.MapType.normal,
                    style: googleMapStyle(),
                    zoomControlsEnabled: true,
                    compassEnabled: true,
                    myLocationButtonEnabled: false,
                    myLocationEnabled: false,
                  ),
                ),
                // Bottom hint when dragging on the map.
                if (_mapBusy)
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '…',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Inputs panel.
          _InputPanel(
            originCtrl: _originCtrl,
            destinationCtrl: _destinationCtrl,
            originFocus: _originFocus,
            destinationFocus: _destinationFocus,
            originResults: _originResults,
            destinationResults: _destinationResults,
            searchingOrigin: _searchingOrigin,
            searchingDestination: _searchingDestination,
            recentSearches: _recentSearches,
            onOriginChanged: _onOriginChanged,
            onDestinationChanged: _onDestinationChanged,
            onSelectOrigin: _selectOrigin,
            onSelectDestination: _selectDestination,
            onUseCurrentLocation: _useCurrentLocation,
            onSelectRecent: (text) {
              _originCtrl.text = text;
              _originFocus.requestFocus();
              _onOriginChanged(text);
            },
            preferenceCtrl: _preferenceCtrl,
            timeChip: _timeChipIndex,
            onTimeChip: _onTimeChip,
            onConfirm: _confirm,
            submitting: _submitting,
          ),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  const _ConfirmRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

class _InputPanel extends StatelessWidget {
  final TextEditingController originCtrl;
  final TextEditingController destinationCtrl;
  final FocusNode originFocus;
  final FocusNode destinationFocus;
  final List<SuggestPlace> originResults;
  final List<SuggestPlace> destinationResults;
  final bool searchingOrigin;
  final bool searchingDestination;
  final List<String> recentSearches;
  final ValueChanged<String> onOriginChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<SuggestPlace> onSelectOrigin;
  final ValueChanged<SuggestPlace> onSelectDestination;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<String> onSelectRecent;
  final TextEditingController preferenceCtrl;
  final int? timeChip;
  final ValueChanged<int?> onTimeChip;
  final VoidCallback onConfirm;
  final bool submitting;

  static const _timeChipKeys = [
    'suggestTimeAny',
    'suggestTimeMorning',
    'suggestTimeMidday',
    'suggestTimeEvening',
    'suggestTimeNight',
  ];

  const _InputPanel({
    required this.originCtrl,
    required this.destinationCtrl,
    required this.originFocus,
    required this.destinationFocus,
    required this.originResults,
    required this.destinationResults,
    required this.searchingOrigin,
    required this.searchingDestination,
    required this.recentSearches,
    required this.onOriginChanged,
    required this.onDestinationChanged,
    required this.onSelectOrigin,
    required this.onSelectDestination,
    required this.onUseCurrentLocation,
    required this.onSelectRecent,
    required this.preferenceCtrl,
    required this.timeChip,
    required this.onTimeChip,
    required this.onConfirm,
    required this.submitting,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final timeLabels = _timeChipKeys
        .map((k) => L10n.t(context, k))
        .toList();

    return Material(
      color: panelColor,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SuggestField(
                controller: originCtrl,
                focusNode: originFocus,
                label: L10n.t(context, 'suggestOrigin'),
                hint: L10n.t(context, 'suggestOriginPlaceholder'),
                icon: Icons.trip_origin_rounded,
                iconColor: AppColors.success,
                loading: searchingOrigin,
                onChanged: onOriginChanged,
                results: originResults,
                onSelect: onSelectOrigin,
                onUseCurrent: onUseCurrentLocation,
                recentSearches: recentSearches,
                onSelectRecent: onSelectRecent,
              ),
              const SizedBox(height: 8),
              _SuggestField(
                controller: destinationCtrl,
                focusNode: destinationFocus,
                label: L10n.t(context, 'suggestDestination'),
                hint: L10n.t(context, 'suggestDestinationPlaceholder'),
                icon: Icons.place_rounded,
                iconColor: AppColors.error,
                loading: searchingDestination,
                onChanged: onDestinationChanged,
                results: destinationResults,
                onSelect: onSelectDestination,
                onUseCurrent: onUseCurrentLocation,
                recentSearches: recentSearches,
                onSelectRecent: onSelectRecent,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  L10n.t(context, 'suggestWhenToGo'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(timeLabels.length, (i) {
                  final selected = timeChip == i;
                  return ChoiceChip(
                    label: Text(
                      timeLabels[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: AppColors.accent,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                      color: selected ? AppColors.accent : AppColors.divider,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                    onSelected: (_) => onTimeChip(selected ? null : i),
                  );
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: preferenceCtrl,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: L10n.t(context, 'suggestDeparturePreference'),
                  hintText: L10n.t(context, 'suggestDepartureHint'),
                  prefixIcon: const Icon(Icons.schedule_rounded),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: submitting ? null : onConfirm,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    submitting
                        ? L10n.t(context, 'suggestSubmitting')
                        : L10n.t(context, 'suggestSubmit'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final bool loading;
  final ValueChanged<String> onChanged;
  final List<SuggestPlace> results;
  final ValueChanged<SuggestPlace> onSelect;
  final VoidCallback onUseCurrent;
  final List<String> recentSearches;
  final ValueChanged<String> onSelectRecent;

  const _SuggestField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    required this.iconColor,
    required this.loading,
    required this.onChanged,
    required this.results,
    required this.onSelect,
    required this.onUseCurrent,
    required this.recentSearches,
    required this.onSelectRecent,
  });

  @override
  State<_SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<_SuggestField> {
  @override
  Widget build(BuildContext context) {
    final suggestions = widget.results.isNotEmpty
        ? widget.results
        : (widget.recentSearches.isNotEmpty && widget.controller.text.isEmpty
              ? widget.recentSearches
                  .map(
                    (text) => SuggestPlace(
                      placeId: '',
                      name: text,
                      address: '',
                      lat: 0,
                      lng: 0,
                    ),
                  )
                  .toList()
              : const <SuggestPlace>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: Icon(widget.icon, color: widget.iconColor),
            suffixIcon: widget.loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.my_location_rounded),
                    tooltip: L10n.t(context, 'suggestCurrentLocation'),
                    onPressed: widget.onUseCurrent,
                  ),
            isDense: true,
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.surfaceDarkElevated
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                if (Theme.of(context).brightness == Brightness.dark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final place = suggestions[i];
                final isRecent = place.lat == 0 && place.placeId.isEmpty;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isRecent
                        ? Icons.history_rounded
                        : Icons.place_outlined,
                    size: 20,
                    color: isRecent
                        ? AppColors.textTertiary
                        : widget.iconColor,
                  ),
                  title: Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: place.address.isNotEmpty
                      ? Text(
                          place.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        )
                      : null,
                  onTap: () {
                    if (isRecent) {
                      widget.onSelectRecent(place.name);
                    } else {
                      widget.onSelect(place);
                    }
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}