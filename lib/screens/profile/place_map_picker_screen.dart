import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../services/passenger_location_service.dart';
import '../../widgets/google_map_kit.dart';

/// Full-screen Google Map where the passenger drags a pin onto the exact spot
/// of a saved place. Pops with a `LatLng` when "Use this location" is tapped.
class PlaceMapPickerScreen extends StatefulWidget {
  const PlaceMapPickerScreen({super.key, required this.initial});

  /// Where the map should start (the place being edited, or the device's
  /// current location when creating a brand-new place).
  final LatLng initial;

  @override
  State<PlaceMapPickerScreen> createState() => _PlaceMapPickerScreenState();
}

class _PlaceMapPickerScreenState extends State<PlaceMapPickerScreen> {
  gm.GoogleMapController? _controller;
  late LatLng _pick;
  bool _locating = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pick = widget.initial;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDragEnd(gm.LatLng pos) {
    setState(() => _pick = LatLng(pos.latitude, pos.longitude));
    Haptics.selection();
  }

  Future<void> _fromCurrentLocation() async {
    setState(() => _locating = true);
    final ok =
        await PassengerLocationService.instance.ensurePermission();
    var fix = ok
        ? await PassengerLocationService.instance.getSingleFix()
        : null;
    if (!mounted) return;
    setState(() => _locating = false);
    if (fix == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'whereToLocationError'))),
      );
      return;
    }
    setState(() => _pick = fix);
    await _controller?.moveCamera(
      gm.CameraUpdate.newCameraPosition(
        gm.CameraPosition(target: toGm(fix), zoom: 17),
      ),
    );
  }

  void _confirm() {
    if (_busy) return;
    _busy = true;
    Haptics.selection();
    Navigator.of(context).pop(_pick);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'mapPickerTitle'))),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: gm.GoogleMap(
              initialCameraPosition: gm.CameraPosition(
                target: toGm(_pick),
                zoom: 16,
              ),
              onMapCreated: (c) => _controller = c,
              mapType: gm.MapType.normal,
              style: googleMapStyle(),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              compassEnabled: true,
              markers: {
                gm.Marker(
                  markerId: const gm.MarkerId('place-pin'),
                  position: toGm(_pick),
                  draggable: true,
                  onDragEnd: _onDragEnd,
                  infoWindow: gm.InfoWindow(
                    title: L10n.t(context, 'dragPinHint'),
                  ),
                ),
              },
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Material(
                  color:
                      dark
                          ? AppColors.surfaceDarkElevated.withValues(alpha: 0.94)
                          : Colors.white.withValues(alpha: 0.94),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _fromCurrentLocation,
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: _locating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.my_location_rounded,
                              size: 20,
                              color: AppColors.accent,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color:
                      dark
                          ? AppColors.surfaceDarkElevated.withValues(alpha: 0.96)
                          : Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.pin_drop_outlined,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            L10n.t(context, 'dragPinHint'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_pick.latitude.toStringAsFixed(6)}, '
                      '${_pick.longitude.toStringAsFixed(6)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: dark ? Colors.white54 : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _confirm,
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: Text(L10n.t(context, 'useThisLocation')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}