import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_time.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../models/shuttle.dart';
import '../../services/reservation_service.dart';
import '../../services/shuttle_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/primary_button.dart';

/// Lets a passenger move a RESERVED ticket to another SCHEDULED trip of the
/// same vehicle class on a chosen day. Fetches live alternatives via
/// [ShuttleService.searchTrips] and, on confirm, calls the backend's transfer
/// endpoint so the seats move to the new trip in one step.
class ChangeTripDayScreen extends StatefulWidget {
  const ChangeTripDayScreen({super.key});

  @override
  State<ChangeTripDayScreen> createState() => _ChangeTripDayScreenState();
}

class _ChangeTripDayScreenState extends State<ChangeTripDayScreen> {
  Ticket? _ticket;
  DateTime? _day;
  bool _searching = false;
  bool _transferring = false;
  String? _selectedTripId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  void _resolve() {
    final args = ModalRoute.of(context)?.settings.arguments;
    final ticket = args is Ticket ? args : null;
    if (ticket == null || !mounted) return;
    setState(() {
      _ticket = ticket;
      _day = ticket.serviceDate ?? ticket.departure;
    });
    _search();
  }

  Future<void> _pickDate() async {
    final ticket = _ticket;
    if (ticket == null) return;
    final now = DateTime.now();
    final current = _day ?? ticket.serviceDay;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked == null || !mounted) return;
    Haptics.selection();
    setState(() {
      _day = picked;
      _selectedTripId = null;
    });
    await _search();
  }

  Future<void> _search() async {
    final ticket = _ticket;
    final day = _day;
    if (ticket == null || day == null) return;
    setState(() => _searching = true);
    final shuttle = context.read<ShuttleService>();
    await shuttle.searchTrips(
      from: ticket.from,
      to: ticket.to,
      date: egFormat(day, 'yyyy-MM-dd'),
    );
    if (!mounted) return;
    setState(() => _searching = false);
  }

  /// Whether an alternative trip can host this reservation: same vehicle
  /// class and enough free seats for the ticket's party.
  bool _eligible(ShuttleTrip trip) {
    final ticket = _ticket;
    if (ticket == null) return false;
    final cls = ticket.vehicleClass;
    if (cls != null && trip.vehicle != cls) return false;
    return trip.seatsRemaining >= ticket.seats;
  }

  Future<void> _confirm() async {
    final ticket = _ticket;
    final tripId = _selectedTripId;
    if (ticket == null || tripId == null) return;
    setState(() => _transferring = true);
    final err = await context
        .read<ReservationService>()
        .transfer(ticket.id, tripId);
    if (!mounted) return;
    setState(() => _transferring = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.t(context, 'changeTripFailed').replaceFirst('{error}', err),
          ),
        ),
      );
      return;
    }
    final shuttle = context.read<ShuttleService>();
    final newTrip = shuttle.byTripId(tripId);
    final day = _day;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          L10n.t(context, 'tripChanged')
              .replaceFirst('{title}', newTrip?.title ?? ticket.tripTitle)
              .replaceFirst(
                '{date}',
                day == null ? '' : egFormat(day, 'EEE, MMM d'),
              ),
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    if (ticket == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'changeTripDay'))),
        body: Center(child: Text(L10n.t(context, 'noTicketToDisplay'))),
      );
    }
    final shuttle = context.watch<ShuttleService>();
    final alternatives = shuttle.trips
        .where((t) => t.id != ticket.tripId)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'changeTripDay'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: PrimaryButton(
            label: L10n.t(context, 'confirmChange'),
            icon: Icons.event_available_outlined,
            onPressed:
                _selectedTripId == null || _transferring ? null : _confirm,
            loading: _transferring,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          _currentTicketCard(context, ticket),
          const SizedBox(height: 16),
          _datePickerCard(context, ticket),
          const SizedBox(height: 16),
          Text(
            L10n.t(context, 'alternativeTrips'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            L10n.t(context, 'alternativeTripsSub'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (alternatives.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: EmptyState(
                icon: Icons.route_outlined,
                title: L10n.t(context, 'noAlternativeTrips'),
                subtitle: L10n.t(context, 'noAlternativeTripsSub'),
              ),
            )
          else
            for (var i = 0; i < alternatives.length; i++) ...[
              _AlternativeTripCard(
                trip: alternatives[i],
                selected: _selectedTripId == alternatives[i].id,
                enabled: _eligible(alternatives[i]),
                onTap: () {
                  if (!_eligible(alternatives[i])) return;
                  Haptics.selection();
                  setState(() => _selectedTripId = alternatives[i].id);
                },
              ),
              if (i < alternatives.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _currentTicketCard(BuildContext context, Ticket ticket) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.t(context, 'currentTrip'),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _routeLine(ticket.from, ticket.to),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.event_available_outlined,
                size: 15,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                '${DateFormat('EEE, MMM d · HH:mm').format(ticket.serviceDay)}'
                '${ticket.isRecurring ? ' · ${L10n.t(context, 'recurring')}' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _routeLine(String from, String to) {
    return Row(
      children: [
        const Icon(Icons.trip_origin, size: 14, color: AppColors.accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            from,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(width: 22, height: 1, color: AppColors.divider),
        ),
        const Icon(
          Icons.location_on,
          size: 14,
          color: AppColors.textTertiary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            to,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _datePickerCard(BuildContext context, Ticket ticket) {
    final day = _day ?? ticket.serviceDay;
    return SoftCard(
      child: InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: AppColors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.t(context, 'chooseNewDay'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      egFormat(day, 'EEEE, MMM d, yyyy'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.edit_calendar_outlined,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One alternative trip the passenger can move the reservation to. Disabled
/// trips (full / different vehicle class) are shown greyed out with a note.
class _AlternativeTripCard extends StatelessWidget {
  final ShuttleTrip trip;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _AlternativeTripCard({
    required this.trip,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final free = trip.seatsRemaining;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SoftCard(
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    trip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      L10n.t(context, 'selected'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  trip.vehicle?.icon ?? Icons.airport_shuttle_rounded,
                  size: 15,
                  color: trip.vehicle?.color ?? AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  trip.vehicle?.name ?? L10n.t(context, 'shuttle'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  egFormat(trip.startTime, 'EEE, MMM d · HH:mm'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  Formatters.currency(trip.fareForOne),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.event_seat_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    free > 0
                        ? '$free ${L10n.t(context, 'seatsRemaining')}'
                        : L10n.t(context, 'full'),
                    style: TextStyle(
                      fontSize: 12,
                      color: free > 0
                          ? AppColors.textSecondary
                          : AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!enabled)
                  Text(
                    _disabledNote(context),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _disabledNote(BuildContext context) {
    if (trip.seatsRemaining < 1) return L10n.t(context, 'insufficientSeats');
    return L10n.t(context, 'differentClass');
  }
}
