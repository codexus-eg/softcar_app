import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_time.dart';
import '../../models/shuttle.dart';
import '../../services/reservation_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/date_badge.dart';

/// The passenger's live tickets, tapping one opens the boarding pass.
class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reservations = context.watch<ReservationService>();

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'myTickets'))),
      body: RefreshIndicator(
        onRefresh: () => reservations.syncFromLive(),
        child: reservations.tickets.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.confirmation_number_outlined,
                    title: L10n.t(context, 'noTicketsYet'),
                    subtitle: L10n.t(context, 'noTicketsYetSub'),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: reservations.tickets.length,
                itemBuilder: (context, i) =>
                    _TicketRow(ticket: reservations.tickets[i]),
              ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  final Ticket ticket;
  const _TicketRow({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = ticket.isCancelled
        ? AppColors.error
        : ticket.isCompleted
            ? AppColors.textSecondary
            : AppColors.success;
    final stripColor =
        ticket.vehicleClass?.color ?? (isDark ? Colors.white : AppColors.ink);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SoftCard(
        padding: EdgeInsets.zero,
        onTap: () => Navigator.of(context)
            .pushNamed('/ticket', arguments: ticket),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: stripColor,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.tripTitle.isEmpty
                          ? ticket.ticketCode
                          : ticket.tripTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      ticket.statusLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      DateBadge(date: ticket.departure),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ticket.from,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 2),
                            Text(
                              egFormat(ticket.departure, 'EEE, MMM d · HH:mm'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            '${ticket.total.toStringAsFixed(2)} EGP',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          Text(
                            '${L10n.t(context, 'seat')} ${ticket.seatNumbers}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: statusColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}