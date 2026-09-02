import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_time.dart';
import '../../core/utils/formatters.dart';
import '../../models/shuttle.dart';
import '../../services/reservation_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/date_badge.dart';
import '../../widgets/ticket_review_sheet.dart';
import '../shuttle/ticket_detail_screen.dart';

/// Tickets tab: the passenger's live reservations grouped by trip in
/// expandable sections. Each section header shows the trip title, date/time,
/// the number of reserved tickets and a status icon; expanded rows open the
/// full ticket detail. A counts header (upcoming / completed / cancelled)
/// sits on top and pull-to-refresh reloads from the live backend.
class TicketsTab extends StatefulWidget {
  const TicketsTab({super.key});

  @override
  State<TicketsTab> createState() => _TicketsTabState();
}

class _TicketsTabState extends State<TicketsTab> {
  @override
  Widget build(BuildContext context) {
    final reservations = context.watch<ReservationService>();
    final tickets = reservations.tickets;
    final groups = _groupTickets(tickets);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Text(
              L10n.t(context, 'myTickets'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              L10n.t(context, 'groupedTickets'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
            child: _CountsRow(tickets: tickets),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: reservations.syncFromLive,
              child: groups.isEmpty
                  ? _emptyList(context)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: groups.length,
                      itemBuilder: (context, i) =>
                          _TripSection(group: groups[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyList(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 70),
        EmptyState(
          icon: Icons.confirmation_number_outlined,
          title: L10n.t(context, 'noTicketsYet'),
          subtitle: L10n.t(context, 'noTicketsYetSub'),
        ),
      ],
    );
  }
}

/// One expandable trip section: a stable key, the display title, the trip's
/// departure and the reserved tickets that belong to it.
class _TripGroup {
  final String key;
  final String title;
  final DateTime departure;
  final List<Ticket> tickets;

  const _TripGroup({
    required this.key,
    required this.title,
    required this.departure,
    required this.tickets,
  });

  /// Representative ticket for the status badge: the next upcoming one, or
  /// the first ticket when the trip has no upcoming reservations.
  Ticket get primary {
    for (final t in tickets) {
      if (t.isUpcoming) return t;
    }
    return tickets.first;
  }

  /// L10n key for the group's trip-type chip: "Round trip" when any ticket
  /// is a round-trip leg, "Recurring" when any ticket is recurring, else
  /// "One-time". Null never happens for an empty list (guarded by callers).
  String? get typeKey {
    if (tickets.any((t) => t.isRoundTrip)) return 'roundTrip';
    if (tickets.any((t) => t.isRecurring)) return 'recurring';
    return 'oneTime';
  }
}

List<_TripGroup> _groupTickets(List<Ticket> tickets) {
  final order = <String>[];
  final map = <String, List<Ticket>>{};
  for (final t in tickets) {
    // Round-trip outbound + return legs are grouped under their shared
    // roundTripGroupId even when each leg rides on a different tripId.
    final key = t.roundTripGroupId.isNotEmpty
        ? t.roundTripGroupId
        : t.tripId.isNotEmpty
        ? t.tripId
        : t.tripTitle.isNotEmpty
        ? t.tripTitle
        : t.ticketCode;
    if (!map.containsKey(key)) order.add(key);
    map.putIfAbsent(key, () => []).add(t);
  }
  final groups = <_TripGroup>[];
  for (final key in order) {
    final list = map[key]!..sort((a, b) => a.departure.compareTo(b.departure));
    final first = list.first;
    groups.add(
      _TripGroup(
        key: key,
        title: first.tripTitle.isNotEmpty ? first.tripTitle : first.ticketCode,
        departure: first.departure,
        tickets: list,
      ),
    );
  }
  groups.sort((a, b) {
    final aUp = a.primary.isUpcoming;
    final bUp = b.primary.isUpcoming;
    if (aUp != bUp) return aUp ? -1 : 1;
    if (aUp) return a.departure.compareTo(b.departure);
    return b.departure.compareTo(a.departure);
  });
  return groups;
}

/// App-bar-ish header: upcoming / completed / cancelled reservation counts.
class _CountsRow extends StatelessWidget {
  final List<Ticket> tickets;
  const _CountsRow({required this.tickets});

  @override
  Widget build(BuildContext context) {
    final upcoming = tickets.where((t) => t.isUpcoming).length;
    final completed = tickets.where((t) => t.isCompleted).length;
    final cancelled = tickets.where((t) => t.isCancelled).length;
    return Row(
      children: [
        Expanded(
          child: _CountChip(
            count: upcoming,
            label: L10n.t(context, 'upcomingCount'),
            color: AppColors.success,
            icon: Icons.schedule_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CountChip(
            count: completed,
            label: L10n.t(context, 'completedCount'),
            color: AppColors.textSecondary,
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CountChip(
            count: cancelled,
            label: L10n.t(context, 'cancelledCount'),
            color: AppColors.error,
            icon: Icons.cancel_outlined,
          ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final IconData icon;

  const _CountChip({
    required this.count,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final text = label.replaceFirst('{count}', '$count');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small neutral pill showing the trip's booking type (round-trip /
/// recurring / one-time) on a grouped-trip header.
class _GroupTypeChip extends StatelessWidget {
  final String labelKey;
  const _GroupTypeChip({required this.labelKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.category_outlined, size: 12, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(
            L10n.t(context, labelKey),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible card for one trip: header carries the trip title, departure,
/// the reserved-ticket count and a status pill; expanding reveals each ticket.
class _TripSection extends StatelessWidget {
  final _TripGroup group;
  const _TripSection({required this.group});

  @override
  Widget build(BuildContext context) {
    final ticket = group.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? AppColors.dividerDark : AppColors.divider;
    final statusColor = ticket.isCancelled
        ? AppColors.error
        : ticket.isCompleted
            ? AppColors.textSecondary
            : AppColors.success;
    final statusIcon = ticket.isCancelled
        ? Icons.cancel_outlined
        : ticket.isCompleted
            ? Icons.check_circle_outline
            : Icons.schedule_rounded;
    final statusText = ticket.isCancelled
        ? L10n.t(context, 'cancelled')
        : ticket.isCompleted
            ? L10n.t(context, 'completed')
            : L10n.t(context, 'upcoming');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(statusIcon, size: 21, color: statusColor),
            ),
            title: Text(
              group.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${egFormat(group.departure, 'EEE, MMM d · HH:mm')} · '
                          '${group.tickets.length} ${L10n.t(context, 'tickets')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (group.typeKey != null) ...[
                    const SizedBox(height: 6),
                    _GroupTypeChip(labelKey: group.typeKey!),
                  ],
                ],
              ),
            ),
            children: [
              Divider(height: 1, color: dividerColor),
              for (var i = 0; i < group.tickets.length; i++) ...[
                _TicketRow(ticket: group.tickets[i]),
                if (i < group.tickets.length - 1)
                  Divider(height: 1, color: dividerColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One reserved ticket inside a trip section. Tapping opens the detail
/// screen; completed trips show a quick rate-this-trip action.
class _TicketRow extends StatelessWidget {
  final Ticket ticket;
  const _TicketRow({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stripColor =
        ticket.vehicleClass?.color ?? (isDark ? Colors.white : AppColors.ink);
    final statusColor = ticket.isCancelled
        ? AppColors.error
        : ticket.isCompleted
            ? AppColors.textSecondary
            : AppColors.success;

    return InkWell(
      onTap: () => Navigator.of(
        context,
      ).pushNamed('/ticket-detail', arguments: ticket),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DateBadge(date: ticket.departure, height: 48),
                const SizedBox(width: 10),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: stripColor,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    ticket.vehicleClass?.icon ??
                        Icons.confirmation_number_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ticket.from} → ${ticket.to}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        egFormat(ticket.departure, 'EEE, MMM d · HH:mm'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.currency(ticket.total),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      paymentStatusLabel(context, ticket.paymentStatus),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.event_seat_outlined,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    ticket.seatNumbers.isEmpty
                        ? '${ticket.seats} '
                            '${ticket.seats == 1 ? L10n.t(context, 'seatAbbr') : L10n.t(context, 'seatsAbbr')}'
                        : ticket.seatNumbers,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            _ticketBadges(context),
            if (ticket.isCompleted && !ticket.reviewed)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showTicketReviewSheet(context, ticket),
                  icon: const Icon(Icons.star_border_rounded, size: 17),
                  label: Text(L10n.t(context, 'rateThisTrip')),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Badges for this ticket: an Outbound/Return chip for round-trip legs, a
  /// Recurring chip (with its service date when the backend sends one) for
  /// recurring reservations, and nothing for plain one-time rides.
  Widget _ticketBadges(BuildContext context) {
    final chips = <Widget>[];
    if (ticket.isRoundTrip) {
      if (ticket.isOutboundLeg) {
        chips.add(
          _BadgeChip(
            label: L10n.t(context, 'outbound'),
            color: AppColors.accent,
            icon: Icons.north_east_rounded,
          ),
        );
      } else if (ticket.isReturnLeg) {
        chips.add(
          _BadgeChip(
            label: L10n.t(context, 'returnLeg'),
            color: AppColors.info,
            icon: Icons.south_west_rounded,
          ),
        );
      }
    }
    if (ticket.isRecurring) {
      final date = ticket.serviceDate;
      chips.add(
        _BadgeChip(
              label: date == null
                  ? L10n.t(context, 'recurring')
                  : '${L10n.t(context, 'recurring')} · '
                        '${egFormat(date, 'MMM d')}',
          color: AppColors.success,
          icon: Icons.repeat_rounded,
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: chips,
      ),
    );
  }
}

/// Small pill badge used on ticket rows (round-trip leg / recurring).
class _BadgeChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _BadgeChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}