import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// A result from the Nominatim places search.
class PlaceResult {
  final String displayName;
  final LatLng position;

  const PlaceResult({required this.displayName, required this.position});
}

/// Overlay search bar for Nominatim place search, designed to sit on top
/// of a [FlutterMap]. Debounces input at 350 ms and returns the selected
/// [PlaceResult] via [onSelected].
class PlacesSearchOverlay extends StatefulWidget {
  final ValueChanged<PlaceResult> onSelected;
  final VoidCallback? onClose;

  const PlacesSearchOverlay({
    super.key,
    required this.onSelected,
    this.onClose,
  });

  @override
  State<PlacesSearchOverlay> createState() => _PlacesSearchOverlayState();
}

class _PlacesSearchOverlayState extends State<PlacesSearchOverlay> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<PlaceResult> _results = [];

  static const _endpoint = 'https://nominatim.openstreetmap.org/search';
  static const _ua = 'SoftCarShuttle/1.0';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    try {
      final uri = Uri.parse(
        '$_endpoint?q=${Uri.encodeQueryComponent(q)}'
        '&format=json&limit=6&accept-language=ar',
      );
      final res = await http.get(uri, headers: {'User-Agent': _ua});
      final json = jsonDecode(res.body);
      if (json is! List) {
        setState(() {
          _results = [];
        });
        return;
      }
      final places = json.map<PlaceResult>((e) {
        return PlaceResult(
          displayName: e['display_name']?.toString() ?? '',
          position: LatLng(
            double.tryParse(e['lat']?.toString() ?? '') ?? 0,
            double.tryParse(e['lon']?.toString() ?? '') ?? 0,
          ),
        );
      }).toList();
      if (mounted) setState(() => _results = places);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search bar
          Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'ابحث عن مكان...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _results = []);
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          // Results list
          if (_results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _results.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (_, i) {
                  final p = _results[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place, size: 20),
                    title: Text(
                      p.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    onTap: () {
                      widget.onSelected(p);
                      _ctrl.clear();
                      setState(() => _results = []);
                      _focusNode.unfocus();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
