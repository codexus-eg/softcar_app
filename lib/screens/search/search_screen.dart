import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/egypt_time.dart';
import '../../models/shuttle.dart';
import '../../services/shuttle_service.dart';
import '../../widgets/common_widgets.dart';

/// From -> to trip search. Optionally uses the device's current location as
/// the "from" point, searches live trips on the production backend and shows
/// results with live seat availability + assigned driver. Tapping a result
/// opens the trip-details screen and then seat selection.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  DateTime? _date;
  bool _locating = false;
  double? _lat;
  double? _lng;
  ShuttleClass? _fleetFilter;
  bool _fleetInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_fleetInitialized) {
      _fleetInitialized = true;
      _fleetFilter = context.read<ShuttleService>().fleetFilter;
    }
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _setFleetFilter(ShuttleClass? filter) {
    Haptics.selection();
    context.read<ShuttleService>().setFleetFilter(filter);
    setState(() => _fleetFilter = filter);
  }

  /// Fleet filter match. null = All; luxury = the 3-seat sedan; any other
  /// sentinel value ([ShuttleService.standardFleet]) = the merged 14 + 28
  /// seat standard fleet.
  bool _matchesFilter(ShuttleTrip trip, ShuttleClass? filter) {
    if (filter == null) return true;
    if (filter == ShuttleClass.luxury) {
      return trip.vehicle == ShuttleClass.luxury || trip.totalSeats == 3;
    }
    return trip.vehicle != ShuttleClass.luxury &&
        (trip.vehicle != null || trip.totalSeats != 3);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final hasPermission = await Geolocator.checkPermission();
      var granted = hasPermission == LocationPermission.always ||
          hasPermission == LocationPermission.whileInUse;
      if (!granted) {
        final requested = await Geolocator.requestPermission();
        granted = requested == LocationPermission.always ||
            requested == LocationPermission.whileInUse;
      }
      if (!granted) {
        if (mounted) _toast(L10n.t(context, 'locationDenied'));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _from.text = L10n.t(context, 'currentLocation');
      });
      Haptics.success();
    } catch (_) {
      if (mounted) _toast(L10n.t(context, 'locationFailed'));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _swap() {
    Haptics.selection();
    setState(() {
      final f = _from.text;
      _from.text = _to.text;
      _to.text = f;
      _lat = null;
      _lng = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _search() async {
    final from = _from.text.trim();
    final to = _to.text.trim();
    if (from.isEmpty || to.isEmpty) {
      _toast(L10n.t(context, 'fillFromTo'));
      return;
    }
    FocusScope.of(context).unfocus();
    final shuttle = context.read<ShuttleService>();
    final ok = await shuttle.searchTrips(
      from: from,
      to: to,
      date: _date == null
          ? null
          : DateFormat('yyyy-MM-dd').format(_date!),
      lat: _lat,
      lng: _lng,
    );
    if (!mounted) return;
    if (!ok) {
      if (shuttle.error != null && shuttle.error.toString().contains('sign')) {
        _toast(L10n.t(context, 'signInToBook'));
        return;
      }
      _toast(L10n.t(context, 'searchFailed'));
      return;
    }
    Haptics.success();
    setState(() {});
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final shuttle = context.watch<ShuttleService>();
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'searchTitle'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SoftCard(
              child: Column(
                children: [
                  _locationField(
                    controller: _from,
                    label: L10n.t(context, 'from'),
                    icon: Icons.trip_origin,
                    onTrailing: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.my_location,
                                color: AppColors.accent, size: 20),
                            tooltip: L10n.t(context, 'useCurrentLocation'),
                            onPressed: _useCurrentLocation,
                          ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 40),
                          color: AppColors.divider,
                        ),
                      ),
                      GestureDetector(
                        onTap: _swap,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.swap_vert,
                              color: AppColors.accent, size: 18),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 40),
                          color: AppColors.divider,
                        ),
                      ),
                    ],
                  ),
                  _locationField(
                    controller: _to,
                    label: L10n.t(context, 'to'),
                    icon: Icons.location_on,
                    onTrailing: IconButton(
                      icon: const Icon(Icons.event, size: 20),
                      tooltip: L10n.t(context, 'chooseDate'),
                      onPressed: _pickDate,
                    ),
                  ),
                  if (_date != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 40),
                          Expanded(
                            child: Text(
                              '${L10n.t(context, 'date')}: '
                              '${DateFormat('EEE, MMM d').format(_date!)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _date = null),
                            child: const Icon(Icons.close,
                                size: 16,
                                color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: shuttle.loading ? null : _search,
                      icon: shuttle.loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search, size: 20),
                      label: Text(
                          shuttle.loading
                              ? L10n.t(context, 'searching')
                              : L10n.t(context, 'search'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _PopularRoutes(
            onPick: (from, to) {
              setState(() {
                _from.text = from;
                _to.text = to;
                _lat = null;
                _lng = null;
              });
              Haptics.selection();
            },
          ),
          Expanded(
            child: Column(
              children: [
                if (shuttle.trips.isNotEmpty) _fleetFilterBar(shuttle.trips),
                Expanded(child: _results(context, shuttle)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    Widget? onTrailing,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: L10n.t(context, 'searchHint'),
        prefixIcon: Icon(icon, size: 18, color: AppColors.accent),
        suffixIcon: onTrailing,
        isDense: true,
      ),
    );
  }

  Widget _fleetFilterBar(List<ShuttleTrip> trips) {
    final luxury = trips
        .where((t) => _matchesFilter(t, ShuttleClass.luxury))
        .length;
    final standard = trips
        .where((t) => _matchesFilter(t, ShuttleService.standardFleet))
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          _FilterPill(
            label: L10n.t(context, 'allTrips'),
            selected: _fleetFilter == null,
            onTap: () => _setFleetFilter(null),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: '${L10n.t(context, 'luxury3')} ($luxury)',
            selected: _fleetFilter == ShuttleClass.luxury,
            onTap: () => _setFleetFilter(
              _fleetFilter == ShuttleClass.luxury ? null : ShuttleClass.luxury,
            ),
          ),
          const SizedBox(width: 8),
          _FilterPill(
            label: '${L10n.t(context, 'standard14to28')} ($standard)',
            selected:
                _fleetFilter != null && _fleetFilter != ShuttleClass.luxury,
            onTap: () => _setFleetFilter(
              _fleetFilter != null && _fleetFilter != ShuttleClass.luxury
                  ? null
                  : ShuttleService.standardFleet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, ShuttleService shuttle) {
    if (shuttle.loading && shuttle.trips.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    final trips = _fleetFilter == null
        ? shuttle.trips
        : shuttle.trips.where((t) => _matchesFilter(t, _fleetFilter)).toList();
    if (trips.isEmpty) {
      return EmptyState(
        icon: Icons.route_outlined,
        title: L10n.t(context, 'noTripsFound'),
        subtitle: L10n.t(context, 'noTripsFoundSub'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: trips.length,
      itemBuilder: (context, i) {
        final trip = trips[i];
        return _SearchResultCard(
          trip: trip,
          tiers: shuttle.tiersFor(trip),
        );
      },
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Flexible(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                selected
                    ? AppColors.accent
                    : isDark
                    ? AppColors.surfaceDarkElevated
                    : AppColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.divider,
            ),
            boxShadow:
                selected
                    ? [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                  child: Icon(Icons.check, size: 13, color: Colors.white),
                ),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color:
                        selected
                            ? Colors.white
                            : isDark
                            ? Colors.white70
                            : AppColors.textPrimary,
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

class _SearchResultCard extends StatefulWidget {
  final ShuttleTrip trip;
  final List<ReservationTier> tiers;
  const _SearchResultCard({required this.trip, this.tiers = const []});

  @override
  State<_SearchResultCard> createState() => _SearchResultCardState();
}

class _SearchResultCardState extends State<_SearchResultCard> {
  bool _expanded = false;

  bool get _expandable =>
      widget.tiers.isNotEmpty ||
      (widget.trip.tripType.isRoundTrip && widget.trip.returnTrip != null);

  void _openDetails() =>
      Navigator.of(context).pushNamed('/trip-details', arguments: widget.trip);

  void _openSeatSelection([ReservationTier? tier]) {
    Navigator.of(context).pushNamed(
      '/seat-selection',
      arguments:
          tier == null
              ? widget.trip
              : SeatSelectionArgs(trip: widget.trip, tier: tier),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final free = trip.seatsRemaining;
    final hasTiers = widget.tiers.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: SoftCard(
        accent: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasTiers) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      size: 14,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        L10n.t(context, 'packageAvailable'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            GestureDetector(
              onTap: _openDetails,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          egFormat(trip.startTime, 'HH:mm'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${trip.vehicle?.name ?? 'Shuttle'} · '
                              '${egFormat(trip.startTime, 'EEE, MMM d')}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Formatters.currency(trip.price),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            free > 0
                                ? '$free ${L10n.t(context, 'seatsRemaining')}'
                                : L10n.t(context, 'full'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color:
                                      free > 0
                                          ? AppColors.success
                                          : AppColors.error,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _RouteSummary(from: trip.fromName, to: trip.toName),
                  if (trip.driver != null && trip.driver!.isAssigned) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 14,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${L10n.t(context, 'assignedDriver')}: '
                              '${trip.driver!.name ?? ''}'
                              '${trip.driver!.name != null && trip.driver!.carPlateNumber != null ? ' · ' : ''}'
                              '${trip.driver!.carPlateNumber ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_expandable) ...[
              const Divider(height: 20),
              Center(
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _expanded
                            ? L10n.t(context, 'showLess')
                            : L10n.t(context, 'showMore'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                if (hasTiers)
                  for (final tier in widget.tiers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ExpandableTierCard(
                        trip: trip,
                        tier: tier,
                        onReserve: () => _openSeatSelection(tier),
                      ),
                    ),
                if (trip.tripType.isRoundTrip && trip.returnTrip != null) ...[
                  const SizedBox(height: 4),
                  _ReturnLegRow(
                    trip: trip,
                    onReserve: () => _openSeatSelection(),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Reserve-tier card that expands in place to the full package detail: the
/// covered-day strip, price → package price + savings, both round-trip legs
/// and a "Reserve with this tier" action.
class _ExpandableTierCard extends StatefulWidget {
  final ShuttleTrip trip;
  final ReservationTier tier;
  final VoidCallback onReserve;
  const _ExpandableTierCard({
    required this.trip,
    required this.tier,
    required this.onReserve,
  });

  @override
  State<_ExpandableTierCard> createState() => _ExpandableTierCardState();
}

class _ExpandableTierCardState extends State<_ExpandableTierCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tier = widget.tier;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tier.isRecommended ? AppColors.accent : AppColors.divider,
          width: tier.isRecommended ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    tier.isRecommended
                        ? Icons.workspace_premium
                        : Icons.workspace_premium_outlined,
                    size: 18,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                tier.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (tier.isRecommended) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  L10n.t(context, 'recommended'),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              Formatters.currency(tier.packagePrice),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                tier.durationDays > 0
                                    ? '${L10n.t(context, 'perPass')} · '
                                          '${L10n.t(context, 'daysCount').replaceFirst('{n}', '${tier.durationDays}')}'
                                    : L10n.t(context, 'perPass'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tier.description.isNotEmpty) ...[
                    Text(
                      tier.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (tier.durationDays > 0) ...[
                    TierCoveredDays(tier: tier, trip: widget.trip),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Text(
                        L10n.t(context, 'originalPrice'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        Formatters.currency(tier.originalPrice),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (tier.savings > 0)
                        Text(
                          L10n.t(context, 'saves').replaceFirst(
                            '{amount}',
                            '${tier.savings.toInt()} EGP',
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  if (widget.trip.tripType.isRoundTrip &&
                      widget.trip.returnTrip != null) ...[
                    const SizedBox(height: 10),
                    TierLegsSection(trip: widget.trip),
                  ],
                  if (tier.validFrom != null || tier.validUntil != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${L10n.t(context, 'validFrom')}: '
                      '${tier.validFrom != null ? egFormat(tier.validFrom!, 'MMM d, yyyy') : '—'}'
                      ' · ${L10n.t(context, 'validUntil')}: '
                      '${tier.validUntil != null ? egFormat(tier.validUntil!, 'MMM d, yyyy') : '—'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: widget.onReserve,
                      icon: const Icon(Icons.workspace_premium, size: 17),
                      label: Text(
                        L10n.t(context, 'reserveWithTier'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Expanded round-trip leg row inside the search result card: the return
/// trip (time, route, price) plus a "Both legs" reservation affordance.
class _ReturnLegRow extends StatelessWidget {
  final ShuttleTrip trip;
  final VoidCallback onReserve;
  const _ReturnLegRow({required this.trip, required this.onReserve});

  @override
  Widget build(BuildContext context) {
    final ret = trip.returnTrip;
    if (ret == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.swap_horiz_rounded,
              size: 15,
              color: AppColors.accent,
            ),
            const SizedBox(width: 6),
            Text(
              '${L10n.t(context, 'returnLeg')} · '
              '${egFormat(ret.startTime, 'EEE, HH:mm')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
            const Spacer(),
            Text(
              Formatters.currency(ret.fareForBooking),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _RouteSummary(from: ret.fromName, to: ret.toName),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onReserve,
            icon: const Icon(Icons.confirmation_number_outlined, size: 17),
            label: Text(
              '${L10n.t(context, 'bothLegs')} · ${L10n.t(context, 'book')}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteSummary extends StatelessWidget {
  final String from;
  final String to;
  const _RouteSummary({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.trip_origin, size: 13, color: AppColors.accent),
        const SizedBox(width: 5),
        Expanded(
          child: Text(from,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Container(width: 18, height: 1, color: AppColors.divider),
        ),
        const Icon(Icons.location_on, size: 13, color: AppColors.textTertiary),
        const SizedBox(width: 5),
        Expanded(
          child: Text(to,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// Quick-pick popular route buttons that pre-fill the From/To fields.
class _PopularRoutes extends StatelessWidget {
  final void Function(String from, String to) onPick;
  const _PopularRoutes({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final routes = [
      (icon: Icons.flight, from: 'New Cairo', to: 'Cairo Airport'),
      (icon: Icons.location_city, from: 'Downtown', to: 'Nasr City'),
      (icon: Icons.apartment, from: 'New Cairo', to: 'Downtown'),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: routes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final r = routes[i];
          return ActionChip(
            avatar: Icon(r.icon, size: 16, color: AppColors.accent),
            label: Text(
              '${r.from} \u2192 ${r.to}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent),
            ),
            backgroundColor: AppColors.accentSoft,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(99)),
            onPressed: () => onPick(r.from, r.to),
          );
        },
      ),
    );
  }
}
