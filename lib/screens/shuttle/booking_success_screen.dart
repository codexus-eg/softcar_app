import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../models/shuttle.dart';
import '../../widgets/primary_button.dart';

/// Celebratory confirmation shown right after a successful booking, before
/// the boarding pass. The checkmark scales/fades in and the summary confirms
/// the reservation; "View ticket" swaps this route for the boarding pass.
class BookingSuccessScreen extends StatefulWidget {
  const BookingSuccessScreen({super.key});

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final ticket = args is Ticket ? args : null;
    if (ticket == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scale = CurvedAnimation(
        parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOutBack));
    final fade = CurvedAnimation(
        parent: _controller, curve: const Interval(0.3, 1, curve: Curves.easeOut));
    final stripColor = ticket.vehicleClass?.color ?? AppColors.accent;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              ScaleTransition(
                scale: scale,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: AppColors.success, size: 60),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: fade,
                child: Column(
                  children: [
                    Text(
                      L10n.t(context, 'bookingConfirmed'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.t(context, 'bookingConfirmedSub'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FadeTransition(
                opacity: fade,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.surfaceDarkElevated
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: stripColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(ticket.vehicleClass?.icon ??
                                Icons.airport_shuttle_rounded,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${ticket.from} → ${ticket.to}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(
                                  ticket.tripTitle.isEmpty
                                      ? ticket.ticketCode
                                      : ticket.tripTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${ticket.seats} ${L10n.t(context, 'seatsAbbr')}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: fade,
                child: PrimaryButton(
                  label: L10n.t(context, 'viewTicket'),
                  icon: Icons.confirmation_number_outlined,
                  accent: true,
                  onPressed: () {
                    Navigator.of(context)
                        .pushReplacementNamed('/ticket', arguments: ticket);
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: Text(L10n.t(context, 'done')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
