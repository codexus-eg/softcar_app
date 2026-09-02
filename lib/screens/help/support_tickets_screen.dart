import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../services/support_service.dart';
import '../../widgets/common_widgets.dart';

/// Support tickets backed by the real support-tickets API.
class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final support = context.read<SupportService>();
      if (support.tickets.isEmpty) support.syncTickets();
    });
  }

  Future<void> _openNew() async {
    final created = await showModalBottomSheet<SupportTicket>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewTicketSheet(),
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${L10n.t(context, 'openTicket')} — ${created.subject}'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'ticketsSupport')),
        actions: [
          IconButton(
            onPressed: _openNew,
            icon: const Icon(Icons.add_rounded, color: AppColors.accent),
            tooltip: L10n.t(context, 'newTicket'),
          ),
        ],
      ),
      body: Consumer<SupportService>(
        builder: (context, support, _) {
          if (support.loading && support.tickets.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          if (support.tickets.isEmpty) {
            return _EmptyTickets(onNew: _openNew);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: support.tickets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = support.tickets[i];
              return SoftCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.subject,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                        _StatusPill(status: t.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${L10n.t(context, 'priority')}: ${t.priority} · ${L10n.t(context, 'category')}: ${t.category}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _date(t.createdAt),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _date(DateTime dt) => [
        dt.day.toString().padLeft(2, '0'),
        dt.month.toString().padLeft(2, '0'),
        dt.year.toString(),
      ].join('/');
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  Color get _color {
    switch (status.toUpperCase()) {
      case 'CLOSED':
      case 'RESOLVED':
        return AppColors.success;
      case 'DEALING':
      case 'IN_PROGRESS':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: dark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label(context),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: _color,
        ),
      ),
    );
  }

  String _label(BuildContext context) {
    switch (status.toUpperCase()) {
      case 'OPEN':
        return L10n.t(context, 'ticketStatusOpen');
      case 'IN_PROGRESS':
      case 'DEALING':
        return L10n.t(context, 'ticketStatusInProgress');
      case 'CLOSED':
        return L10n.t(context, 'ticketStatusClosed');
      case 'RESOLVED':
        return L10n.t(context, 'ticketStatusResolved');
      default:
        return status.toUpperCase();
    }
  }
}

class _EmptyTickets extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyTickets({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.confirmation_number_outlined,
            size: 64, color: AppColors.textTertiary),
        const SizedBox(height: 16),
        Center(
          child: Text(L10n.t(context, 'noTickets'),
              style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            L10n.t(context, 'noTicketsSub'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(height: 28),
        SoftCard(
          accent: true,
          onTap: onNew,
          child: Center(
            child: Text(
              L10n.t(context, 'newTicket'),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class _NewTicketSheet extends StatefulWidget {
  const _NewTicketSheet();

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _category = 'GENERAL';
  String _priority = 'NORMAL';
  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10n.t(context, 'fillAllFields')),
      ));
      return;
    }
    setState(() => _sending = true);
    final ticket = await context.read<SupportService>().submitTicket(
          subject: subject,
          message: message,
          category: _category,
          priority: _priority,
        );
    if (mounted) Navigator.of(context).pop(ticket);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _handle()),
              const SizedBox(height: 14),
              Text(L10n.t(context, 'newTicket'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _label(L10n.t(context, 'category')),
              const SizedBox(height: 6),
              _chips(
                [
                  (L10n.t(context, 'ticketCatGeneral'), 'GENERAL'),
                  (L10n.t(context, 'ticketCatTechnical'), 'TECHNICAL'),
                  (L10n.t(context, 'ticketCatBilling'), 'BILLING'),
                  (L10n.t(context, 'ticketCatOther'), 'OTHER'),
                ],
                _category,
                (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 14),
              _label(L10n.t(context, 'priority')),
              const SizedBox(height: 6),
              _chips(
                [
                  (L10n.t(context, 'priorityNormal'), 'NORMAL'),
                  (L10n.t(context, 'priorityHigh'), 'HIGH'),
                  (L10n.t(context, 'priorityUrgent'), 'URGENT'),
                ],
                _priority,
                (v) => setState(() => _priority = v),
              ),
              const SizedBox(height: 14),
              _label(L10n.t(context, 'subject')),
              const SizedBox(height: 6),
              TextField(
                controller: _subject,
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _label(L10n.t(context, 'message')),
              const SizedBox(height: 6),
              TextField(
                controller: _message,
                maxLines: 4,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SoftCard(
                accent: true,
                onTap: _sending ? null : _submit,
                child: Center(
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accent))
                      : Text(
                          L10n.t(context, 'openTicket'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle() => Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textTertiary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      );

  Widget _chips(
      List<(String, String)> options,
      String selected,
      ValueChanged<String> onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          GestureDetector(
            onTap: () => onPick(o.$2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected == o.$2
                    ? AppColors.accent
                    : AppColors.surfaceDarkElevated,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                o.$1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color:
                      selected == o.$2 ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}