import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/passenger_location_service.dart';
import '../../widgets/google_map_kit.dart';
import 'place_map_picker_screen.dart';

/// Add / edit a saved place. In add mode the passenger picks a category
/// (Home / Work / Other), names the place and pins it either with the map
/// picker or their current location. Saving a Home/Work when one already
/// exists simply replaces the old one — there is never more than a single
/// Home or Work entry on the account.
class PlaceEditorScreen extends StatefulWidget {
  const PlaceEditorScreen({super.key, this.place, this.placeType});

  /// Existing place being edited; null when creating a new one.
  final SavedPlace? place;

  /// Suggested category for new places (HOME / WORK / OTHER).
  final String? placeType;

  @override
  State<PlaceEditorScreen> createState() => _PlaceEditorScreenState();
}

class _PlaceEditorScreenState extends State<PlaceEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late String _placeType;
  LatLng? _coords;
  bool _locating = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.place;
    _placeType = p?.placeType ?? widget.placeType ?? 'OTHER';
    _name = TextEditingController(text: p?.name ?? '');
    _address = TextEditingController(text: p?.address ?? '');
    if (p != null) _coords = LatLng(p.lat, p.lng);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  SavedPlace? _existingOfCurrentType(AuthService auth) {
    if (widget.place != null || _placeType == 'OTHER') return null;
    for (final p in auth.profile.savedPlaces) {
      if (p.placeType == _placeType) return p;
    }
    return null;
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final granted =
        await PassengerLocationService.instance.ensurePermission();
    LatLng? fix;
    if (granted) {
      fix = await PassengerLocationService.instance.getSingleFix();
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (fix != null) _coords = fix;
    });
    if (fix == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'whereToLocationError'))),
      );
    }
  }

  Future<void> _pickOnMap() async {
    final start =
        _coords ??
        PassengerLocationService.instance.currentPosition ??
        const LatLng(30.0444, 31.2357);
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => PlaceMapPickerScreen(initial: start),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _coords = picked);
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast(L10n.t(context, 'savedPlaceRequired'));
      return;
    }
    if (_coords == null) {
      _toast(L10n.t(context, 'chooseLocationRequired'));
      return;
    }
    final address = _address.text.trim();
    final lat = _coords!.latitude;
    final lng = _coords!.longitude;

    setState(() => _saving = true);
    String? err;
    final existing =
        widget.place ?? _existingOfCurrentType(auth);
    if (existing != null) {
      err = await auth.updatePlace(existing.id, {
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'placeType': _placeType,
      });
    } else {
      err = await auth.savePlace(
        label: name,
        name: name,
        address: address,
        lat: lat,
        lng: lng,
        placeType: _placeType,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      _toast(err);
      return;
    }
    Haptics.selection();
    Navigator.of(context).pop(true);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppColors.surfaceDarkElevated : AppColors.surface;
    final isEdit = widget.place != null;
    final replacing = !isEdit && _existingOfCurrentType(auth) != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? L10n.t(context, 'editSavedPlace') : L10n.t(context, 'addPlace')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isEdit) ...[
            Text(
              L10n.t(context, 'savedPlacesSub'),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.accent,
                selectedForegroundColor: Colors.white,
              ),
              segments: [
                ButtonSegment(
                  value: 'HOME',
                  label: Text(L10n.t(context, 'homePlace')),
                  icon: const Icon(Icons.home_rounded, size: 16),
                ),
                ButtonSegment(
                  value: 'WORK',
                  label: Text(L10n.t(context, 'workPlace')),
                  icon: const Icon(Icons.work_outline_rounded, size: 16),
                ),
              ],
              selected: {_placeType == 'OTHER' ? 'HOME' : _placeType},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() => _placeType = s.first);
              },
            ),
            const SizedBox(height: 8),
            _OtherToggle(
              selected: _placeType == 'OTHER',
              onTap: () => setState(() => _placeType = 'OTHER'),
            ),
            if (replacing) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync_alt_rounded,
                        size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _placeType == 'HOME'
                            ? L10n.t(context, 'replaceExistingPlace')
                            : L10n.t(context, 'replaceExistingWork'),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _name,
            autofocus: !isEdit,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: L10n.t(context, 'savedPlaceName'),
              prefixIcon: const Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: L10n.t(context, 'savedPlaceAddress'),
              hintText: L10n.t(context, 'savedPlaceHint'),
              prefixIcon: const Icon(Icons.alt_route_rounded),
            ),
          ),
          const SizedBox(height: 16),
          if (_coords != null)
            _MapPreview(
              coords: _coords!,
              surface: surface,
              onOpen: _pickOnMap,
              onChanged: (c) => setState(() => _coords = c),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickOnMap,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: Text(L10n.t(context, 'pickOnMap')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _locate,
                  icon: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(L10n.t(context, 'savedPlaceUseCurrent')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _saving ? L10n.t(context, 'saving') : L10n.t(context, 'save'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small live Google Map preview with a draggable pin; tapping it opens the
/// full-screen [PlaceMapPickerScreen].
class _MapPreview extends StatefulWidget {
  const _MapPreview({
    required this.coords,
    required this.surface,
    required this.onOpen,
    required this.onChanged,
  });

  final LatLng coords;
  final Color surface;
  final VoidCallback onOpen;
  final ValueChanged<LatLng> onChanged;

  @override
  State<_MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends State<_MapPreview> {
  gm.GoogleMapController? _controller;

  @override
  void didUpdateWidget(_MapPreview old) {
    super.didUpdateWidget(old);
    if (old.coords != widget.coords) {
      _controller?.moveCamera(
        gm.CameraUpdate.newCameraPosition(
          gm.CameraPosition(target: toGm(widget.coords), zoom: 15),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            gm.GoogleMap(
              initialCameraPosition: gm.CameraPosition(
                target: toGm(widget.coords),
                zoom: 15,
              ),
              onMapCreated: (c) {
                _controller = c;
              },
              style: googleMapStyle(),
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              markers: {
                gm.Marker(
                  markerId: const gm.MarkerId('place-preview-pin'),
                  position: toGm(widget.coords),
                  draggable: true,
                  onDragEnd: (pos) => widget.onChanged(
                    LatLng(pos.latitude, pos.longitude),
                  ),
                ),
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: widget.surface.withValues(alpha: 0.94),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onOpen,
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(Icons.open_in_full_rounded,
                        size: 18, color: AppColors.accent),
                  ),
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onOpen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Third category chip for places that are neither home nor work.
class _OtherToggle extends StatelessWidget {
  const _OtherToggle({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.accent;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: selected ? AppColors.accent : AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_outline_rounded, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  L10n.t(context, 'placeOther'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}