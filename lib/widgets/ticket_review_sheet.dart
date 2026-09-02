import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import '../models/shuttle.dart';
import '../services/passenger_api.dart';
import 'common_widgets.dart';

/// Opens the shared rate-your-trip bottom sheet for [ticket] and returns true
/// when a review was successfully submitted.
Future<bool> showTicketReviewSheet(BuildContext context, Ticket ticket) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TicketReviewSheet(ticket: ticket),
  );
  if (ok == true && context.mounted) {
    Haptics.success();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.t(context, 'thanksForFeedback'))),
    );
  }
  return ok == true;
}

/// Bottom sheet where a passenger rates a completed trip and optionally files
/// a complaint. Mirrors the ticket detail action of the same name.
class TicketReviewSheet extends StatefulWidget {
  final Ticket ticket;
  const TicketReviewSheet({super.key, required this.ticket});

  @override
  State<TicketReviewSheet> createState() => _TicketReviewSheetState();
}

class _TicketReviewSheetState extends State<TicketReviewSheet> {
  int _rating = 5;
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  bool _complaint = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await passengerApi.submitReview(
        reservationId: widget.ticket.id,
        rating: _rating,
        title: _title.text,
        body: _body.text,
        complaint: _complaint ? _body.text : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.t(context, 'couldNotSubmit').replaceFirst('{error}', '$e'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 14),
              Text(
                L10n.t(context, 'rateThisTrip'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                widget.ticket.tripTitle.isEmpty
                    ? '${widget.ticket.from} → ${widget.ticket.to}'
                    : widget.ticket.tripTitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var s = 1; s <= 5; s++)
                    GestureDetector(
                      onTap: () => setState(() => _rating = s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          s <= _rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 42,
                          color: s <= _rating
                              ? const Color(0xFFF5A623)
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: L10n.t(context, 'shortReviewTitle'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _body,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: _complaint
                      ? L10n.t(context, 'describeWhatWentWrong')
                      : L10n.t(context, 'tellUsAboutTrip'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(
                    value: _complaint,
                    onChanged: (v) =>
                        setState(() => _complaint = v ?? false),
                    activeColor: AppColors.accent,
                  ),
                  Expanded(
                    child: Text(
                      L10n.t(context, 'thisWasAComplaint'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SoftCard(
                accent: true,
                onTap: _busy ? null : _submit,
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        )
                      : Text(
                          L10n.t(context, 'submitReview'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
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