import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_time.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../models/shuttle.dart';
import '../../services/auth_service.dart';
import '../../services/reservation_service.dart';
import '../../widgets/board_pass_qr.dart';
import '../../widgets/call_chooser_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/live_bus_widgets.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/ticket_review_sheet.dart';

/// Full ticket detail opened from the grouped tickets list: boarding code,
/// route, date/time, seats, price breakdown, payment method + status, trip
/// title, driver info and the QR block. Action buttons depend on the ticket
/// status — "Track live" for upcoming trips, "Leave review" for completed.
class TicketDetailScreen extends StatelessWidget {
  const TicketDetailScreen({super.key});

  /// Arrival time at the final (dropoff) stop. Uses the admin-set per-point
  /// offset from the trip's scheduled start when available, otherwise the
  /// backend's estimated end time.
  static String dropoffArrival(Ticket ticket) {
    for (final stop in ticket.pickupPoints.reversed) {
      if (stop.isDropoff) {
        return egFormat(stop.arrivalAt(ticket.departure), 'HH:mm');
      }
    }
    return egFormat(ticket.liveEndTime, 'HH:mm');
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final ticket = args is Ticket ? args : null;
    if (ticket == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(L10n.t(context, 'noTicketToDisplay'))),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthService>();
    final seatColor = GenderColor.forGender(auth.profile.gender);
    final stripColor =
        ticket.vehicleClass?.color ?? (isDark ? Colors.white : AppColors.ink);
    final statusColor = ticket.isCancelled
        ? AppColors.error
        : ticket.isCompleted
        ? AppColors.textSecondary
        : AppColors.success;
    final statusText = ticket.isCancelled
        ? L10n.t(context, 'cancelled')
        : ticket.isCompleted
        ? L10n.t(context, 'completed')
        : L10n.t(context, 'upcoming');
    final showLive = ticket.isUpcoming && ticket.liveStops.length >= 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'ticketDetail')),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: L10n.t(context, 'copyTicketCode'),
            onPressed: () async {
              Haptics.light();
              await Clipboard.setData(ClipboardData(text: ticket.ticketCode));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(L10n.t(context, 'ticketCodeCopied'))),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: _actions(context, ticket),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          _HeaderStrip(
            ticket: ticket,
            statusColor: statusColor,
            statusText: statusText,
            stripColor: stripColor,
          ),
          const SizedBox(height: 16),
          _QrBlock(ticket: ticket),
          if (showLive) ...[
            const SizedBox(height: 16),
            LiveBusCard(ticket: ticket),
          ],
          const SizedBox(height: 16),
          _TripCard(
            ticket: ticket,
            seatColor: seatColor,
            passengerName: auth.profile.name,
          ),
          const SizedBox(height: 16),
          _PriceCard(ticket: ticket, statusColor: statusColor),
          const SizedBox(height: 16),
          _DriverCard(driver: ticket.driver, stripColor: stripColor),
          const SizedBox(height: 20),
          Text(
            L10n.t(context, 'ticketBoardHint'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, Ticket ticket) {
    Future<void> confirmCancel() async {
      final reservations = context.read<ReservationService>();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L10n.t(ctx, 'cancelTicketTitle')),
          content: Text(L10n.t(ctx, 'cancelTicketBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(L10n.t(ctx, 'keepTicket')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                L10n.t(ctx, 'cancelAndRefund'),
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      final err = await reservations.cancel(ticket.id);
      if (!context.mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.t(
                context,
                'cancelFailed',
              ).replaceFirst('{error}', err),
            ),
          ),
        );
        return;
      }
      final refund = reservations.lastRefundedAmount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            refund != null && refund > 0
                ? L10n.t(
                    context,
                    'ticketCancelledRefund',
                  ).replaceFirst('{amount}', Formatters.currency(refund))
                : L10n.t(context, 'ticketCancelled'),
          ),
        ),
      );
      Navigator.of(context).pop();
    }

    void openChangeDay() {
      Navigator.of(
        context,
      ).pushNamed('/change-trip-day', arguments: ticket);
    }

    if (ticket.isUpcoming) {
      final body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: L10n.t(context, 'trackLive'),
            icon: Icons.near_me_outlined,
            accent: true,
            onPressed: () => Navigator.of(
              context,
            ).pushNamed('/live-tracking', arguments: ticket),
          ),
          if (ticket.isReserved) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: openChangeDay,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text(
                      L10n.t(context, 'changeTripDay'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: BorderSide(
                        color: AppColors.accent.withValues(alpha: 0.45),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: confirmCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(
                      L10n.t(context, 'cancelAndRefund'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(
                        color: AppColors.error.withValues(alpha: 0.45),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: body,
        ),
      );
    } else if (ticket.isCompleted && !ticket.reviewed) {
      final button = PrimaryButton(
        label: L10n.t(context, 'reviewTrip'),
        icon: Icons.star_border_rounded,
        onPressed: () => showTicketReviewSheet(context, ticket),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: button,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Colored masthead with trip title, status pill and the departure/arrival
/// time blocks — mirrors the boarding-pass header used across the app.
class _HeaderStrip extends StatelessWidget {
  final Ticket ticket;
  final Color statusColor;
  final String statusText;
  final Color stripColor;

  const _HeaderStrip({
    required this.ticket,
    required this.statusColor,
    required this.statusText,
    required this.stripColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: stripColor,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ticket.tripTitle.isEmpty
                      ? L10n.t(context, 'softcarShuttle')
                      : ticket.tripTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _headerTypeChips(context),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _TimeBlock(
                label: L10n.t(context, 'departure'),
                value: egFormat(ticket.departure, 'HH:mm'),
                date: egFormat(ticket.departure, 'EEE, MMM d'),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.4),
                    height: 1,
                  ),
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  ticket.vehicleClass?.icon ?? Icons.airport_shuttle_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.4),
                    height: 1,
                  ),
                ),
              ),
              _TimeBlock(
                label: L10n.t(context, 'arrival'),
                value: TicketDetailScreen.dropoffArrival(ticket),
                date: ticket.to,
                alignEnd: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// White-on-strip pills describing the reservation type (round trip +
  /// leg / recurring / one-time) and its concrete service date when it
  /// differs from the trip template's departure day.
  Widget _headerTypeChips(BuildContext context) {
    final chips = <Widget>[];
    if (ticket.isRoundTrip) {
      chips.add(
        _HeaderChip(
          label: L10n.t(context, 'roundTrip'),
          icon: Icons.swap_horiz_rounded,
        ),
      );
      if (ticket.isOutboundLeg) {
        chips.add(
          _HeaderChip(
            label: L10n.t(context, 'outbound'),
            icon: Icons.north_east_rounded,
          ),
        );
      } else if (ticket.isReturnLeg) {
        chips.add(
          _HeaderChip(
            label: L10n.t(context, 'returnLeg'),
            icon: Icons.south_west_rounded,
          ),
        );
      }
    } else if (ticket.isRecurring) {
      chips.add(
        _HeaderChip(
          label: L10n.t(context, 'recurring'),
          icon: Icons.repeat_rounded,
        ),
      );
    } else {
      chips.add(
        _HeaderChip(
          label: L10n.t(context, 'oneTime'),
          icon: Icons.trip_origin,
        ),
      );
    }
    final sd = ticket.serviceDate;
    if (sd != null) {
      final sameDay =
          sd.year == ticket.departure.year &&
          sd.month == ticket.departure.month &&
          sd.day == ticket.departure.day;
      if (!sameDay) {
        chips.add(
          _HeaderChip(
            label:
                '${L10n.t(context, 'serviceDate')} · '
                '${egFormat(sd, 'EEE, MMM d')}',
            icon: Icons.event_available_outlined,
          ),
        );
      }
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

/// Small translucent pill shown on the colored header strip.
class _HeaderChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _HeaderChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final String label;
  final String value;
  final String? date;
  final bool alignEnd;

  const _TimeBlock({
    required this.label,
    required this.value,
    this.date,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        if (value.isNotEmpty)
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        if (date != null && date!.isNotEmpty)
          Text(
            date!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// QR-style code block with the boarding hint and the copyable ticket code.
class _QrBlock extends StatelessWidget {
  final Ticket ticket;
  const _QrBlock({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        children: [
          BoardPassQr(seed: ticket.ticketCode, size: 168),
          const SizedBox(height: 14),
          Text(
            L10n.t(context, 'scanAtBoarding'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.inkSoft,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              ticket.ticketCode,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Route, timing, seats and passenger identity for this ticket.
class _TripCard extends StatelessWidget {
  final Ticket ticket;
  final Color seatColor;
  final String passengerName;

  const _TripCard({
    required this.ticket,
    required this.seatColor,
    required this.passengerName,
  });

  @override
  Widget build(BuildContext context) {
    final type = _ticketTypeValue(context, ticket);
    return SoftCard(
      child: Column(
        children: [
          _TripRow(label: L10n.t(context, 'tripTitle'), value: ticket.tripTitle),
          const Divider(height: 16),
          _TripRow(label: L10n.t(context, 'tripTypeLabel'), value: type),
          if (ticket.isRecurring &&
              ticket.recurringReservationId.isNotEmpty) ...[
            const Divider(height: 16),
            _TripRow(
              label: L10n.t(context, 'recurringPlan'),
              value: ticket.recurringReservationId,
            ),
          ],
          if (ticket.serviceDate != null) ...[
            const Divider(height: 16),
            _TripRow(
              label: L10n.t(context, 'serviceDate'),
              value: egFormat(ticket.serviceDate!, 'EEE, MMM d · HH:mm'),
            ),
          ],
          const Divider(height: 16),
          _RouteRow(from: ticket.from, to: ticket.to),
          const Divider(height: 16),
          _TripRow(
            label: L10n.t(context, 'date'),
            value: egFormat(ticket.departure, 'EEE, MMM d · HH:mm'),
          ),
          const Divider(height: 16),
          _TripRow(
            label: L10n.t(context, 'seatNumbers'),
            value: ticket.seatNumbers.isEmpty
                ? '${ticket.seats} ${L10n.t(context, 'seatAbbr')}'
                : ticket.seatNumbers,
            valueColor: seatColor,
          ),
          const Divider(height: 16),
          _TripRow(
            label: L10n.t(context, 'passenger'),
            value: passengerName.isEmpty ? '—' : passengerName,
          ),
          const Divider(height: 16),
          _TripRow(
            label: L10n.t(context, 'ticketCode'),
            value: ticket.ticketCode,
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final String from;
  final String to;

  const _RouteRow({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
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
}

class _TripRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _TripRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Price breakdown (subtotal, tax, total) plus the payment method and its
/// live status.
class _PriceCard extends StatelessWidget {
  final Ticket ticket;
  final Color statusColor;

  const _PriceCard({required this.ticket, required this.statusColor});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.t(context, 'priceBreakdown'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _priceRow(L10n.t(context, 'subtotal'), ticket.subtotal),
          const SizedBox(height: 8),
          _priceRow(L10n.t(context, 'taxVat'), ticket.tax),
          Divider(color: AppColors.divider, height: 20),
          _priceRow(L10n.t(context, 'total'), ticket.total, strong: true),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.payments_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                '${L10n.t(context, 'paymentMethod')}: '
                '${paymentStatusLabel(context, ticket.paymentMethod)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Icon(
                ticket.isCompleted
                    ? Icons.check_circle_outline
                    : ticket.isCancelled
                    ? Icons.cancel_outlined
                    : Icons.schedule,
                size: 15,
                color: statusColor,
              ),
              const SizedBox(width: 4),
              Text(
                paymentStatusLabel(context, ticket.paymentStatus),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _priceRow(String label, double value, {bool strong = false}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      Text(
        Formatters.currency(value),
        style: TextStyle(
          fontSize: 14,
          fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
    ],
  );
}

/// The driver assigned to the reservation's trip: name, car model, plate and
/// phone — each row only when the backend provides it.
class _DriverCard extends StatelessWidget {
  final TripDriver? driver;
  final Color stripColor;

  const _DriverCard({required this.driver, required this.stripColor});

  @override
  Widget build(BuildContext context) {
    if (driver == null || !driver!.isAssigned) {
      return SoftCard(
        child: Row(
          children: [
            Icon(Icons.person_outline, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context, 'driver'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    L10n.t(context, 'driverNotAssigned'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final d = driver!;
    final canCall =
        (d.userId?.isNotEmpty ?? false) || (d.phone?.isNotEmpty ?? false);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.accentSoft,
                backgroundImage:
                    d.photoUrl != null && d.photoUrl!.isNotEmpty
                        ? NetworkImage(Formatters.imageUrl(d.photoUrl))
                        : null,
                child:
                    d.photoUrl == null || d.photoUrl!.isEmpty
                        ? const Icon(Icons.person, color: AppColors.accent)
                        : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.t(context, 'driver'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.name ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              if (canCall)
                InkWell(
                  onTap: () => showCallChooser(
                    context,
                    targetUserId: d.userId ?? 'DRIVER',
                    displayName: d.name ?? L10n.t(context, 'driver'),
                    phone: d.phone,
                  ),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.success.withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.call_rounded,
                        size: 19, color: AppColors.success),
                  ),
                ),
              if (canCall) const SizedBox(width: 8),
              Icon(
                Icons.airport_shuttle_rounded,
                size: 20,
                color: stripColor,
              ),
            ],
          ),
          if (d.carModel != null && d.carModel!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _driverRow(
              icon: Icons.local_taxi,
              label: L10n.t(context, 'carModel'),
              value: d.carModel!,
            ),
          ],
          if (d.carPlateNumber != null && d.carPlateNumber!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _driverRow(
              icon: Icons.confirmation_number_outlined,
              label: L10n.t(context, 'plate'),
              value: d.carPlateNumber!,
              valueWidget: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  d.carPlateNumber!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
          if (d.phone != null && d.phone!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _driverRow(
              icon: Icons.phone_outlined,
              label: L10n.t(context, 'phoneNumber'),
              value: d.phone!,
            ),
          ],
          if (d.carPhotoUrl != null && d.carPhotoUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                Formatters.imageUrl(d.carPhotoUrl),
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _driverRow({
  required IconData icon,
  required String label,
  required String value,
  Widget? valueWidget,
}) {
  return Row(
    children: [
      Icon(icon, size: 16, color: AppColors.textSecondary),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(width: 8),
      valueWidget ??
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
    ],
  );
}

/// Localized trip-type label for a ticket: "Round trip · Outbound",
/// "Round trip · Return", "Recurring" or "One-time".
String _ticketTypeValue(BuildContext context, Ticket ticket) {
  if (ticket.isRoundTrip) {
    final leg = ticket.isOutboundLeg
        ? L10n.t(context, 'outbound')
        : ticket.isReturnLeg
        ? L10n.t(context, 'returnLeg')
        : '';
    return leg.isEmpty
        ? L10n.t(context, 'roundTrip')
        : '${L10n.t(context, 'roundTrip')} · $leg';
  }
  if (ticket.isRecurring) return L10n.t(context, 'recurring');
  return L10n.t(context, 'oneTime');
}

/// Resolves a backend payment status code to a friendly localized label.
String paymentStatusLabel(BuildContext context, String raw) {
  const map = {
    'PENDING_CASH_COLLECTION': 'cashOnArrival',
    'CASH': 'cashOnArrival',
    'AUTHORIZED': 'paid',
    'PAID': 'paid',
    'PENDING': 'pending',
    'FAILED': 'paymentFailed',
    'REFUNDED': 'refunded',
    'WALLET': 'wallet',
  };
  final key = map[raw];
  if (key != null) return L10n.t(context, key);
  return raw.split('_').map((w) => w.toLowerCase()).join(' ');
}