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
import '../../widgets/board_pass_qr.dart';
import '../../widgets/live_bus_widgets.dart';

/// Digital ticket shown right after booking and from the tickets list.
/// It shows the assigned seat, the fare breakdown and the ticket code. For
/// upcoming trips a live-tracking card renders the estimated minibus position.
class TicketScreen extends StatelessWidget {
  const TicketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ticket =
        ModalRoute.of(context)?.settings.arguments is Ticket
            ? ModalRoute.of(context)?.settings.arguments as Ticket
            : null;
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
    final showLive = ticket.isUpcoming && ticket.liveStops.length >= 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'ticket')),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Container(
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        L10n.t(context, 'confirmed'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Pickup & dropoff points dropdown
                _pointsDropdown(context, ticket),
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
                      child: Icon(ticket.vehicleClass?.icon ??
                          Icons.airport_shuttle_rounded,
                          color: Colors.white, size: 22),
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
                      value: '',
                      date: ticket.to,
                      alignEnd: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Boarding pass centre: QR + code --------------------------------
          SoftCard2(
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
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
          ),
          if (showLive) ...[
            const SizedBox(height: 16),
            LiveBusCard(ticket: ticket),
          ],
          if (ticket.driver != null && ticket.driver!.isAssigned) ...[
            const SizedBox(height: 16),
            SoftCard2(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.accentSoft,
                    backgroundImage:
                        (ticket.driver!.photoUrl != null &&
                                ticket.driver!.photoUrl!.isNotEmpty)
                            ? NetworkImage(
                                Formatters.imageUrl(ticket.driver!.photoUrl),
                              )
                            : null,
                    child:
                        (ticket.driver!.photoUrl == null ||
                                ticket.driver!.photoUrl!.isEmpty)
                            ? const Icon(
                                Icons.person,
                                color: AppColors.accent,
                              )
                            : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.driver!.name ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        if (ticket.driver!.carModel != null &&
                            ticket.driver!.carModel!.isNotEmpty)
                          Text(
                            ticket.driver!.carModel!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (ticket.driver!.carPhotoUrl != null &&
                      ticket.driver!.carPhotoUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        Formatters.imageUrl(ticket.driver!.carPhotoUrl),
                        width: 56,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (ticket.driver!.carPlateNumber != null &&
                      ticket.driver!.carPlateNumber!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ticket.driver!.carPlateNumber!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SoftCard2(
            child: Column(
              children: [
                _Row(label: L10n.t(context, 'from'), value: ticket.from),
                const Divider(height: 16),
                _Row(label: L10n.t(context, 'to'), value: ticket.to),
                const Divider(height: 16),
                _Row(
                  label: L10n.t(context, 'seat'),
                  value: ticket.seatNumbers.isEmpty
                      ? '${ticket.seats} ${L10n.t(context, 'seat')}'
                      : '${L10n.t(context, 'seat')} ${ticket.seatNumbers}',
                  valueColor: seatColor,
                ),
                const Divider(height: 16),
                _Row(
                  label: L10n.t(context, 'passenger'),
                  value: auth.profile.name.isEmpty
                      ? '—'
                      : auth.profile.name,
                ),
                const Divider(height: 16),
                _Row(label: L10n.t(context, 'ticketCode'), value: ticket.ticketCode),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard2(
            child: Column(
              children: [
                _row(
                  L10n.t(context, 'subtotal'),
                  '${ticket.subtotal.toStringAsFixed(2)} EGP',
                ),
                const SizedBox(height: 8),
                _row(
                  L10n.t(context, 'taxVat'),
                  '${ticket.tax.toStringAsFixed(2)} EGP',
                ),
                const Divider(height: 20),
                _row(
                  L10n.t(context, 'total'),
                  '${ticket.total.toStringAsFixed(2)} EGP',
                  strong: true,
                ),
                const SizedBox(height: 12),
                Text(
                  '${L10n.t(context, 'payment')}: ${L10n.t(context, 'paidCash')}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            L10n.t(context, 'ticketBoardHint'),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
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
        Text(label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            )),
        const SizedBox(height: 4),
        if (value.isNotEmpty)
          Text(value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              )),
        if (date != null && date!.isNotEmpty)
          Text(date!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
      ],
    );
  }
}

class SoftCard2 extends StatelessWidget {
  final Widget child;
  const SoftCard2({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _Row({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 14, color: AppColors.textSecondary)),
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

Widget _pointsDropdown(BuildContext context, Ticket ticket) {
    final allStops = [...ticket.pickupPoints];
    final pickupLabel = L10n.t(context, 'pickup');
    final dropoffLabel = L10n.t(context, 'dropoff');

    // Find the main pickup and dropoff points from the ticket from/to
    final mainPickup = ticket.pickupPoints.isNotEmpty
        ? ticket.pickupPoints.first
        : null;
    final mainDropoff = ticket.pickupPoints
        .where((s) => s.pointType == 'DROPOFF')
        .isNotEmpty
        ? ticket.pickupPoints
            .where((s) => s.pointType == 'DROPOFF')
            .last
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.surfaceDarkElevated
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.t(context, 'pickupAndDropoffPoints'),
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 12),
          // Pickup points dropdown button
          _PointDropdownButton(
            label: mainPickup != null
                ? '${mainPickup.name} (${_arrivalTime(ticket, mainPickup)})'
                : pickupLabel,
            onTap: () => _showStopSelectionDialog(
              context,
              allStops,
              pointType: 'PICKUP',
              ticket: ticket,
              selectedStop: mainPickup,
            ),
          ),
          const SizedBox(height: 8),
          // Dropoff points dropdown button
          _PointDropdownButton(
            label: mainDropoff != null
                ? '${mainDropoff.name} (${_arrivalTime(ticket, mainDropoff)})'
                : dropoffLabel,
            onTap: () => _showStopSelectionDialog(
              context,
              allStops,
              pointType: 'DROPOFF',
              ticket: ticket,
              selectedStop: mainDropoff,
            ),
          ),
        ],
      ),
    );
  }

  /// Expected arrival clock time for [stop]: trip departure + the per-point
  /// offset set by admin when creating the trip. Drop-off points without an
  /// explicit offset fall back to the ticket's estimated end time.
  String _arrivalTime(Ticket ticket, ShuttleStop stop) {
    if (stop.isDropoff && stop.arrivalOffsetMin <= 0) {
      final end = ticket.estimatedEndTime;
      if (end != null) return egFormat(end, 'HH:mm');
    }
    return egFormat(stop.arrivalAt(ticket.departure), 'HH:mm');
  }

  void _showStopSelectionDialog(
      BuildContext context,
      List<ShuttleStop> allStops,
      {required String pointType,
      required Ticket ticket,
      ShuttleStop? selectedStop}) {
    final filteredStops = pointType == 'PICKUP'
        ? allStops.where((s) => s.pointType == 'PICKUP').toList()
        : allStops.where((s) => s.pointType == 'DROPOFF').toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            pointType == 'PICKUP'
                ? L10n.t(context, 'selectPickupPoint')
                : L10n.t(context, 'selectDropoffPoint')),
        content: SingleChildScrollView(
          child: Column(
            children: [
              for (final stop in filteredStops)
                ListTile(
                  title: Text(stop.name),
                  subtitle: Text(
                    _arrivalTime(ticket, stop),
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  leading: Icon(
                    stop.pointType == 'PICKUP'
                        ? Icons.location_on
                        : Icons.location_off,
                  ),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'close')),
          ),
        ],
      ),
    );
  }

// Helper method for displaying row information
  _row(String label, String value, {bool strong = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
            )),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

// Point dropdown button widget
  class _PointDropdownButton extends StatelessWidget {
    final String label;
    final VoidCallback onTap;

    const _PointDropdownButton({
      required this.label,
      required this.onTap,
    });

    @override
    Widget build(BuildContext context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surfaceDarkElevated
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? AppColors.divider : AppColors.divider.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.ink : AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }