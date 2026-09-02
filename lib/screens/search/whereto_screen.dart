import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_time.dart';
import '../../core/utils/formatters.dart';
import '../../models/shuttle.dart';
import '../../services/auth_service.dart';
import '../../services/passenger_api.dart';
import '../../services/passenger_location_service.dart';

/// "Where to?" smart search: the user types a destination (or pins one) and
/// the backend ranks every upcoming trip by total walking distance to the
/// nearest board/alight stop pair, plus a convenience bonus. Tapping a row
/// deep-links straight into seat selection pre-selected on those stops.
class WhereToScreen extends StatefulWidget {
  const WhereToScreen({super.key});

  @override
  State<WhereToScreen> createState() => _WhereToScreenState();
}

class _WhereToResult {
  _WhereToResult.fromJson(Map<String, dynamic> json)
      : scoreM = (json['scoreM'] as num?)?.toDouble() ?? 0,
        fromWalkM = (json['fromWalkM'] as num?)?.toDouble(),
        toWalkM = (json['toWalkM'] as num?)?.toDouble(),
        stopMatched = json['stopMatched'] == true,
        withinRadius = json['withinRadius'] == true,
        price = (json['price'] as num?)?.toDouble(),
        boardAt = _StopAt.fromJson(
          (json['boardAt'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        alightAt = _StopAt.fromJson(
          (json['alightAt'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        trip = (json['trip'] as Map?)?.cast<String, dynamic>() ?? const {};

  final double scoreM;
  final double? fromWalkM;
  final double? toWalkM;
  final bool stopMatched;
  final bool withinRadius;
  final double? price;
  final _StopAt boardAt;
  final _StopAt alightAt;
  final Map<String, dynamic> trip;

  String get tripId => trip['id'] as String? ?? '';
  DateTime? get tripStart {
    final raw = trip['startTime'];
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  int get seatsRemaining => (trip['seatsRemaining'] as num?)?.toInt() ?? 0;

  /// Combined outbound walking (meters) — what the sort ordering represents.
  double get totalWalk => scoreM;
}

class _StopAt {
  _StopAt.fromJson(Map<String, dynamic> json)
      : pointId = json['pointId'] as String? ?? '',
        name = json['name'] as String? ?? '',
        address = json['address'] as String? ?? '',
        lat = (json['lat'] as num?)?.toDouble(),
        lng = (json['lng'] as num?)?.toDouble(),
        stopOrder = (json['stopOrder'] as num?)?.toInt() ?? 0;

  final String pointId;
  final String name;
  final String address;
  final double? lat;
  final double? lng;
  final int stopOrder;
}

class _WhereToScreenState extends State<WhereToScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  String? _error;
  List<_WhereToResult> _results = const [];
  Map<String, dynamic> _meta = const {};
  LatLng? _from;
  bool _locating = false;
  bool _opened = false;

  int _requestSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _from = PassengerLocationService.instance.currentPosition;
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final text = value.trim();
      if (text.length < 2) {
        setState(() {
          _searching = false;
          _results = const [];
          _error = null;
        });
        return;
      }
      _search(text);
    });
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    if (!await PassengerLocationService.instance.ensurePermission()) {
      if (mounted) {
        setState(() {
          _locating = false;
          _error = 'no_location';
        });
      }
      return;
    }
    try {
      final fix = await PassengerLocationService.instance.getSingleFix();
      if (mounted && fix != null) {
        setState(() {
          _from = fix;
          _locating = false;
        });
        final text = _controller.text.trim();
        if (text.length >= 2) _search(text);
      } else if (mounted) {
        setState(() {
          _locating = false;
          _error = 'no_location';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locating = false;
          _error = 'no_location';
        });
      }
    }
  }

  Future<void> _search(String text) async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      _promptSignIn();
      return;
    }
    final from = _from ?? PassengerLocationService.instance.currentPosition;
    if (from == null) {
      if (mounted) {
        setState(() {
          _error = 'no_location';
          _searching = false;
        });
      }
      return;
    }
    final seq = ++_requestSeq;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final json = await passengerApi.whereTo(
        lat: from.latitude,
        lng: from.longitude,
        to: text,
        maxResults: 30,
      );
      if (!mounted || seq != _requestSeq) return;
      final trips = (json['trips'] as List?) ?? const [];
      setState(() {
        _searching = false;
        _results =
            trips
                .whereType<Map>()
                .map((e) => _WhereToResult.fromJson(e.cast<String, dynamic>()))
                .toList();
        _meta = json;
      });
    } catch (_) {
      if (mounted && seq == _requestSeq) {
        setState(() {
          _searching = false;
          _results = const [];
          _error = 'failed';
        });
      }
    }
  }

  void _promptSignIn() {
    final auth = context.read<AuthService>();
    if (auth.isLoggedIn) return;
    Navigator.of(context).pushNamed('/auth');
  }

  Future<void> _openTrip(_WhereToResult result) async {
    if (_opened) return;
    try {
      final detail = await passengerApi.fetchTripDetail(result.tripId);
      if (detail == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.t(context, 'whereToNoResults'))),
          );
        }
        return;
      }
      if (!mounted) return;
      _opened = true;
      final trip = ShuttleTrip.fromJson(detail);
      await Navigator.of(context).pushNamed('/seat-selection', arguments: SeatSelectionArgs(
        trip: trip,
        preferredPickupPointId: result.boardAt.pointId,
        preferredDropoffPointId: result.alightAt.pointId,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'whereToNoResultsSub'))),
        );
      }
    } finally {
      _opened = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppColors.surfaceDarkElevated : AppColors.surface;
    final textColor = dark ? Colors.white : AppColors.textPrimary;
    final subColor = dark ? Colors.white54 : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'whereTo'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.my_location_rounded,
                      size: 20,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        L10n.t(context, 'whereToFrom'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                    _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: L10n.t(context, 'whereToUseLocation'),
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            onPressed: _useMyLocation,
                          ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _controller,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (v) {
                    final text = v.trim();
                    if (text.length >= 2) _search(text);
                  },
                  decoration: InputDecoration(
                    hintText: L10n.t(context, 'whereToHint'),
                    prefixIcon: const Icon(Icons.travel_explore_rounded),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _controller.clear();
                              _debounce?.cancel();
                              _requestSeq++;
                              setState(() {
                                _results = const [];
                                _error = null;
                                _searching = false;
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.accent,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildBody(surface, textColor, subColor)),
        ],
      ),
    );
  }

  Widget _buildBody(
    Color surface,
    Color textColor,
    Color subColor,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final to = _meta['to'] as Map?;

    if (_error != null) {
      final msg = _error == 'no_location'
          ? L10n.t(context, 'whereToLocationError')
          : L10n.t(context, 'whereToNoResultsSub');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_off_rounded,
                size: 40,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 12),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: subColor, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                L10n.t(context, 'whereToNoResultsSub'),
                textAlign: TextAlign.center,
                style: TextStyle(color: subColor, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_searching && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 14),
            Text(
              L10n.t(context, 'whereToSearching'),
              style: TextStyle(color: subColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      final hasQuery = _controller.text.trim().length >= 2;
      final isWelcome = !hasQuery;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isWelcome
                    ? Icons.map_outlined
                    : Icons.search_off_rounded,
                size: 42,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 12),
              Text(
                isWelcome
                    ? L10n.t(context, 'whereToSub')
                    : L10n.t(context, 'whereToNoResults'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: subColor,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final header = StringBuffer(L10n.t(context, 'whereToResults'));
    final convenience = _meta['convenience'] as Map?;
    final count = (convenience?['convenientCount'] as num?)?.toInt();
    if (to != null) {
      final name = to['name'] as String?;
      if (name != null && name.isNotEmpty) header.write(' · $name');
    }
    if (count != null && count > 0) header.write(' · $count');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (to != null && (to['name'] as String?) != null)
          _DestinationBanner(to: to, surface: surface),
        if ((to != null && (to['name'] as String?) != null))
          const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Text(
                header.toString(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const Spacer(),
              Text(
                '${_results.length}/${_meta['totalScored'] ?? _results.length}',
                style: TextStyle(fontSize: 12, color: subColor),
              ),
            ],
          ),
        ),
        for (var i = 0; i < _results.length; i++)
          _ResultCard(
            index: i,
            result: _results[i],
            dark: dark,
            onTap: () => _openTrip(_results[i]),
          ),
      ],
    );
  }
}

/// Small mirror of the resolved destination the backend geocoded.
class _DestinationBanner extends StatelessWidget {
  const _DestinationBanner({required this.to, required this.surface});

  final Map to;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final subColor = dark ? Colors.white54 : AppColors.textSecondary;
    final name = to['name'] as String? ?? '';
    final address = to['address'] as String?;
    final source = to['source'] as String? ?? '';
    final IconData icon = source == 'stop'
        ? Icons.directions_bus_filled
        : source == 'coords'
        ? Icons.place_rounded
        : Icons.location_on_outlined;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (address != null && address.isNotEmpty)
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: subColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.index,
    required this.result,
    required this.dark,
    required this.onTap,
  });

  final int index;
  final _WhereToResult result;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subColor = dark ? Colors.white54 : AppColors.textSecondary;
    final surface = dark ? AppColors.surfaceDarkElevated : AppColors.surface;
    final start = result.tripStart;
    final dest = result.trip['mainDestination'] as String? ?? '';
    final title = result.trip['title'] as String? ?? dest;
    final boardName = result.boardAt.name.isEmpty
        ? L10n.t(context, 'whereToBoardAt').replaceFirst('{name}', dest)
        : result.boardAt.name;
    final alightName = result.alightAt.name.isEmpty
        ? L10n.t(context, 'whereToAlightAt').replaceFirst('{name}', dest)
        : result.alightAt.name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (start != null)
                      Text(
                        egFormat(start, 'HH:mm'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  dest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: subColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.circle, size: 7, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        boardName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        alightName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: subColor),
                      ),
                    ),
                  ],
                ),
                if (result.boardAt.address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 15, top: 3),
                    child: Text(
                      result.boardAt.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (index == 0 && result.withinRadius)
                      _Badge(
                        label: L10n.t(context, 'whereToBestMatch'),
                        icon: Icons.bolt_rounded,
                        highlight: true,
                      ),
                    if (result.withinRadius)
                      _Badge(
                        label: L10n.t(context, 'whereToNearby'),
                        icon: Icons.near_me_rounded,
                      ),
                    if (result.stopMatched)
                      _Badge(
                        label: L10n.t(context, 'whereToStopMatch'),
                        icon: Icons.directions_bus_filled,
                      ),
                    if (result.price != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Text(
                          Formatters.currency(result.price!),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.icon, this.highlight = false});

  final String label;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final bg = highlight
        ? AppColors.accent
        : AppColors.accent.withValues(alpha: 0.12);
    final fg = highlight ? Colors.white : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}