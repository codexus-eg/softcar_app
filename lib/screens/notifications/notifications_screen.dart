import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/notification_service.dart';
import '../../widgets/common_widgets.dart';

/// Live in-app notifications pulled from the production backend and grouped by
/// date (Today / Yesterday / Older). The unread count and "mark all read" act
/// on the shared [NotificationService] so the home-tab bell badge stays in
/// sync. Every item is a real server record; there is no seeded/demo content.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    final service = context.read<NotificationService>();
    if (service.items.isEmpty && !service.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => service.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService>();
    final items = service.items;
    final unread = service.unreadCount;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'notifications')),
        actions: [
          if (service.live && items.isNotEmpty) ...[
            if (unread > 0)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    L10n.t(context, 'unread')
                        .replaceFirst('{count}', '$unread'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            TextButton(
              onPressed: () {
                service.markAllRead();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(L10n.t(context, 'allMarkedRead'))),
                );
              },
              child: Text(L10n.t(context, 'markAllRead')),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => service.refresh(),
        child: service.loading && items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                ],
              )
            : items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: L10n.t(context, 'noNotifications'),
                        subtitle: L10n.t(context, 'notificationsEmptySub'),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: _sections(context, items, dark: dark),
                  ),
      ),
    );
  }

  /// Groups the live items into dated sections: Today, Yesterday, Older.
  List<Widget> _sections(
    BuildContext context,
    List<Map<String, dynamic>> items, {
    required bool dark,
  }) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final today = <Map<String, dynamic>>[];
    final yesterday = <Map<String, dynamic>>[];
    final older = <Map<String, dynamic>>[];
    for (final n in items) {
      final d = _date(n);
      if (d.isAfter(todayStart) || _sameDay(d, todayStart)) {
        today.add(n);
      } else if (d.isAfter(yesterdayStart)) {
        yesterday.add(n);
      } else {
        older.add(n);
      }
    }

    final widgets = <Widget>[];
    void addSection(String title, List<Map<String, dynamic>> section) {
      if (section.isEmpty) return;
      widgets.add(_SectionHeader(title: title));
      for (final n in section) {
        widgets.add(_NotificationTile(data: n, dark: dark));
        widgets.add(const SizedBox(height: 10));
      }
      widgets.add(const SizedBox(height: 8));
    }

    addSection(L10n.t(context, 'today'), today);
    addSection(L10n.t(context, 'yesterday'), yesterday);
    addSection(L10n.t(context, 'older'), older);
    return widgets;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _date(Map<String, dynamic> n) =>
      DateTime.tryParse(n['createdAt']?.toString() ??
              n['at']?.toString() ??
              '') ??
      DateTime.now();
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool dark;
  const _NotificationTile({required this.data, required this.dark});

  @override
  Widget build(BuildContext context) {
    final title = data['title']?.toString();
    final body = data['message']?.toString() ??
        data['body']?.toString() ??
        data['description']?.toString() ??
        '';
    final type = data['type']?.toString().toLowerCase() ?? '';
    final read = data['read'] is bool ? data['read'] as bool : false;
    final at = data['createdAt']?.toString() ??
        data['at']?.toString() ??
        DateTime.now().toString();

    final icon = switch (type) {
      'ticket' || 'reservation' || 'booking' =>
        Icons.confirmation_number_outlined,
      'payment' => Icons.account_balance_wallet_outlined,
      'offer' || 'promo' => Icons.local_offer_outlined,
      'trip' || 'shuttle' => Icons.airport_shuttle_rounded,
      _ => Icons.notifications_outlined,
    };
    final color = switch (type) {
      'payment' => AppColors.success,
      'offer' || 'promo' => AppColors.warning,
      _ => AppColors.accent,
    };

    final link = _linkFor(type);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: read ? 0.72 : 1,
      child: GestureDetector(
        onTap: () {
          context.read<NotificationService>().markRead(data['id']?.toString() ?? '');
          if (link != null) Navigator.of(context).pushNamed(link);
        },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: dark ? AppColors.surfaceDarkElevated : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: read ? AppColors.divider : color,
            width: read ? 1 : 1.2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title ?? L10n.t(context, 'softcarUpdate'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            )),
                      ),
                      if (!read)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(body,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        )),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    Formatters.relative(DateTime.tryParse(at) ?? DateTime.now()),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// Maps a server notification type to the passenger screen that shows the
  /// related workflow. Returns null when there is no clear target.
  static String? _linkFor(String type) {
    final t = type.toUpperCase();
    if (t.contains('RESERVATION') ||
        t.contains('TRIP') ||
        t.contains('BOOKING') ||
        t.contains('SHUTTLE') ||
        t.contains('NO_SHOW') ||
        t.contains('BOARDED') ||
        t.contains('DROPPED')) {
      return '/my-bookings';
    }
    if (t.contains('RECHARGE') ||
        t.contains('WALLET') ||
        t.contains('PAYMENT') ||
        t.contains('REFUND') ||
        t.contains('CARD') ||
        t.contains('BALANCE')) {
      return '/wallet';
    }
    if (t.contains('SUPPORT') || t.contains('TICKET')) {
      return '/support-tickets';
    }
    return null;
  }
}
