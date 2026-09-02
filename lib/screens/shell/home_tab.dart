import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_time.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../models/shuttle.dart';
import '../../services/ads_service.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/reservation_service.dart';
import '../../services/shuttle_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/date_badge.dart';
import '../../widgets/live_bus_widgets.dart';

/// Home tab: pick a day, then choose a live SoftCar trip for any of the three
/// classes (Go coach, Fit minibus, Luxury sedan) and book a seat. Everything
/// here comes from the live API — the header shows the
/// real passenger avatar, the "boarding next" card carries live bus tracking,
/// and the notification bell reflects the real unread count.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with WidgetsBindingObserver {
  static const int _carouselDays = 30;
  static const double _cardWidth = 62;
  static const double _cardExtent = _cardWidth + 10;
  static const double _stripPadding = 20;

  DateTime _today() => _egyptToday();
  DateTime _day = _egyptToday();
  String _fmtDay(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  final ScrollController _stripController = ScrollController();

  /// Today at midnight in Egypt wall-clock time — the schedule's home
  /// timezone — so the carousel always starts on the correct local day.
  static DateTime _egyptToday() {
    final now = egWall(DateTime.now()) ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tiers (admin packages) are shown right under the day buttons on this
    // tab, so make sure they are loaded even before the user opens a trip.
    Future.microtask(context.read<ShuttleService>().loadTiers);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stripController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-read "today" on resume so an overnight session rolls the strip.
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  /// Scrolls the day carousel so the selected card sits centred.
  void _revealSelected({bool animate = false}) {
    if (!_stripController.hasClients) return;
    final viewport = _stripController.position.viewportDimension;
    final index = _day
        .difference(_egyptToday())
        .inDays
        .clamp(0, _carouselDays - 1);
    final target =
        (_stripPadding +
            index * _cardExtent +
            _cardWidth / 2 -
            viewport / 2)
        .clamp(0.0, _stripController.position.maxScrollExtent);
    if (animate) {
      _stripController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _stripController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shuttle = context.watch<ShuttleService>();
    final auth = context.watch<AuthService>();
    final reservations = context.watch<ReservationService>();
    final notifications = context.watch<NotificationService>();
    // "Today" is recomputed on every build (and on lifecycle resume) so a
    // session open across midnight keeps the carousel anchored correctly.
    final today = _egyptToday();
    if (_day.isBefore(today)) _day = today;
    final trips = shuttle.trips.where((t) => _tripOnDay(t, _day)).toList();
    final boardingNext =
        reservations.upcoming.isNotEmpty ? reservations.upcoming.first : null;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            shuttle.syncLive(),
            reservations.syncFromLive(),
            notifications.refresh(),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(auth)),
            SliverToBoxAdapter(child: _AdsCarousel()),
            SliverToBoxAdapter(child: _searchEntry()),
            SliverToBoxAdapter(child: _TierGrid()),
            if (boardingNext != null)
              SliverToBoxAdapter(
                child: _FadeSlide(
                  child: _BoardingNextCard(ticket: boardingNext),
                ),
              ),
            if (!auth.isLoggedIn)
              SliverToBoxAdapter(
                child: _FadeSlide(
                  delay: const Duration(milliseconds: 80),
                  child: _SignInCta(),
                ),
              ),
            SliverToBoxAdapter(
              child: _FadeSlide(
                delay: const Duration(milliseconds: 120),
                child: _dayStrip(today),
              ),
            ),
            SliverToBoxAdapter(
              child: _FadeSlide(
                delay: const Duration(milliseconds: 160),
                child: _fleetIndicator(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: Row(
                  children: [
                    Text(
                      _dayTitle(_day),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      '${trips.length} ${L10n.t(context, 'departures')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (shuttle.loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 56),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else if (trips.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: L10n.t(context, 'allFleetDepartures'),
                    subtitle: L10n.t(context, 'noDeparturesSub'),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _FadeSlide(
                    delay: Duration(milliseconds: 100 + i * 70),
                    child: _TripCard(
                      trip: trips[i],
                      tiers: shuttle.tiersFor(trips[i]),
                    ),
                  ),
                  childCount: trips.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // ---- header -------------------------------------------------------------

  Widget _header(AuthService auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = auth.profile;
    final imageUrl = profile.image;
    final initials =
        profile.name.isEmpty
            ? '?'
            : profile.name
                .split(' ')
                .where((w) => w.isNotEmpty)
                .take(2)
                .map((w) => w[0])
                .join()
                .toUpperCase();
    final unread = context.select<NotificationService, int>(
      (s) => s.unreadCount,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
              border: Border.all(
                color:
                    isDark ? AppColors.surfaceDarkElevated : AppColors.surface,
                width: 2,
              ),
              image:
                  imageUrl != null && imageUrl.isNotEmpty
                      ? DecorationImage(
                        image: NetworkImage(
                          'https://softcarshuttle.com$imageUrl',
                        ),
                        fit: BoxFit.cover,
                      )
                      : null,
            ),
            alignment: Alignment.center,
            child:
                imageUrl == null || imageUrl.isEmpty
                    ? Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    )
                    : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(context),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  profile.name.isEmpty
                      ? L10n.t(context, 'appName')
                      : profile.name.split(' ').take(2).join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip:
                    unread > 0
                        ? L10n.t(
                          context,
                          'unreadNotifications',
                        ).replaceFirst('{count}', '$unread')
                        : L10n.t(context, 'notifications'),
                icon: Icon(
                  Icons.notifications_none_rounded,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
                onPressed:
                    () => Navigator.of(context).pushNamed('/notifications'),
              ),
              if (unread > 0)
                Positioned(
                  right: 4,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 1.6,
                      ),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- hero banner + search -----------------------------------------------

  Widget _searchEntry() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pushNamed('/whereto'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDarkElevated : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 24, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  L10n.t(context, 'whereTo'),
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white54 : AppColors.textSecondary,
                  ),
                ),
              ),
              const Icon(Icons.tune, size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // ---- day strip + fleet --------------------------------------------------

  /// 30 consecutive Egypt-local days starting today. Adding to the day
  /// component lets DateTime roll over month and year boundaries.
  Widget _dayStrip(DateTime today) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        controller: _stripController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _stripPadding),
        itemCount: _carouselDays,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final day = DateTime(today.year, today.month, today.day + i);
          return _DayCard(
            day: day,
            today: today,
            selected: _sameDay(day, _day),
            onTap: () {
              Haptics.selection();
              setState(() => _day = day);
              final shuttle = context.read<ShuttleService>();
              if (_sameDay(day, _today())) {
                shuttle.syncLive();
              } else {
                shuttle.searchTrips(date: _fmtDay(day));
              }
              _revealSelected(animate: true);
            },
          );
        },
      ),
    );
  }

  /// Whether [trip] departs on the Egypt-local calendar [day] — backend
  /// timestamps are re-based through [egDate] so the day bucket is correct
  /// on any device timezone.
  bool _tripOnDay(ShuttleTrip trip, DateTime day) {
    final eg = egDate(trip.startTime);
    return eg != null && _sameDay(eg, day);
  }

  Widget _fleetIndicator() {
    final shuttle = context.watch<ShuttleService>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            _fleetChip(
              label: L10n.t(context, 'luxury3'),
              icon: ShuttleClass.luxury.icon,
              color: ShuttleClass.luxury.color,
              selected: shuttle.fleetFilter == ShuttleClass.luxury,
              onTap: () => _openFiltered(ShuttleClass.luxury),
            ),
            const SizedBox(width: 8),
            _fleetChip(
              label: L10n.t(context, 'standard14to28'),
              icon: Icons.airport_shuttle_rounded,
              color: AppColors.accent,
              selected:
                  shuttle.fleetFilter != null &&
                  shuttle.fleetFilter != ShuttleClass.luxury,
              onTap: () => _openFiltered(ShuttleService.standardFleet),
            ),
          ],
        ),
      ),
    );
  }

  /// Toggles the fleet filter (tapping the active chip clears it back to All)
  /// and opens search pre-filtered.
  void _openFiltered(ShuttleClass filter) {
    Haptics.selection();
    final shuttle = context.read<ShuttleService>();
    final current = shuttle.fleetFilter;
    shuttle.setFleetFilter(current == filter ? null : filter);
    Navigator.of(context).pushNamed('/search');
  }

  Widget _fleetChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: selected ? Colors.white : color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayTitle(DateTime day) {
    final labels = dayLabels(context, day);
    final n = day.difference(_egyptToday()).inDays;
    final label =
        n == 0
            ? L10n.t(context, 'today')
            : n == 1
            ? L10n.t(context, 'tomorrow')
            : labels.weekday;
    return '$label, ${labels.dayNumber} ${labels.month}';
  }

  String _greeting(BuildContext context) {
    final hour = DateTime.now().hour;
    if (hour < 12) return L10n.t(context, 'goodMorning');
    if (hour < 17) return L10n.t(context, 'goodAfternoon');
    return L10n.t(context, 'goodEvening');
  }
}

/// Home-screen reserve-tier bento grid: a dynamic, variable-size grid
/// (4-column cross pattern) rendered strictly from the live tier list served
/// by `GET /api/mobile/tiers`. Each tier maps to a tile sized by the admin's
/// grid view configuration (`gridSpanX` × `gridSpanY`, falling back to 4×4),
/// so the grid never hardcodes or mocks a tier and never depends on an image
/// having loaded. Each photo fills its element with the name + before/after
/// prices overlaid above it; tapping a tile opens the full tier-detail screen.
class _TierGrid extends StatefulWidget {
  const _TierGrid();

  @override
  State<_TierGrid> createState() => _TierGridState();
}

class _TierGridState extends State<_TierGrid> {
  @override
  void initState() {
    super.initState();
    final shuttle = context.read<ShuttleService>();
    if (shuttle.tiers.isEmpty) {
      // Tiers load lazily after home appears — populate the grid.
      Future.microtask(shuttle.loadTiers);
    }
  }

  List<ReservationTier> _availableTiers() {
    final now = DateTime.now();
    return context
        .read<ShuttleService>()
        .tiers
        .where((t) {
          if (t.validFrom != null && t.validFrom!.isAfter(now)) return false;
          if (t.validUntil != null && t.validUntil!.isBefore(now)) return false;
          return true;
        })
        .take(10)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final tiers = _availableTiers();
    if (tiers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          child: Row(
            children: [
              const Icon(
                Icons.workspace_premium_outlined,
                size: 16,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                L10n.t(context, 'reserveTiers'),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: StaggeredGrid.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final tier in tiers)
                StaggeredGridTile.count(
                  crossAxisCellCount: tier.gridSpanX.clamp(1, 4).toInt(),
                  mainAxisCellCount: tier.gridSpanY.clamp(1, 6).toInt(),
                  child: _TierGridTile(tier: tier),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

/// One bento tile for a reserve tier. The tier photo fills the whole element
/// (cropped to fit the tile's shape); when no image is available a branded
/// gradient backs the tile. The tier details — name plus the price before
/// (struck) and price after — are laid out above the image so they stay
/// legible over any photo. Tapping opens the tier-detail screen, preserving
/// the carousel's navigation contract.
class _TierGridTile extends StatelessWidget {
  final ReservationTier tier;
  const _TierGridTile({required this.tier});

  @override
  Widget build(BuildContext context) {
    final img = Formatters.imageUrl(tier.imageUrl);
    final compact = (tier.gridSpanX < 2);
    final tallEnough = tier.gridSpanY >= 3;
    final nameSize = compact ? 12.0 : 14.0;
    final priceSize = compact ? 11.0 : 13.0;

    return GestureDetector(
      onTap: () =>
          Navigator.of(context).pushNamed('/tier-detail', arguments: tier),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Tier photo fills the element; gradient falls back.
            if (img.isNotEmpty)
              Image.network(
                img,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _TierTileFallback(),
              )
            else
              const _TierTileFallback(),
            // Top scrim so the details above the image always read clearly.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.black.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
            if (tier.durationDays > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 5 : 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${tier.durationDays} ${L10n.t(context, 'days')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            // Tier details — name and price before/after — above the image.
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tier.name,
                    maxLines: tallEnough ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: nameSize,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (tier.originalPrice > tier.packagePrice) ...[
                        Text(
                          Formatters.currency(tier.originalPrice),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: priceSize - 1,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.lineThrough,
                            shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          Formatters.currency(tier.packagePrice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: priceSize,
                            fontWeight: FontWeight.w900,
                            shadows: const [Shadow(color: Colors.black54, blurRadius: 5)],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!compact &&
                      tallEnough &&
                      tier.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      tier.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Branded gradient backing for tiles whose photo is missing or failing.
class _TierTileFallback extends StatelessWidget {
  const _TierTileFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF141B2E), Color(0xFF1F2B47)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

/// Home-screen ads carousel: a horizontally-scrollable strip of promotions
/// from `GET /api/mobile/ads`. While loading or on network failure it shows
/// scrollable placeholder tiles so the home screen never breaks.
class _AdsCarousel extends StatefulWidget {
  const _AdsCarousel();

  @override
  State<_AdsCarousel> createState() => _AdsCarouselState();
}

class _AdsCarouselState extends State<_AdsCarousel> {
  final AdsService _service = AdsService();
  final PageController _pages = PageController(viewportFraction: 0.88);
  Timer? _autoPlay;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _service.load();
    _autoPlay = Timer.periodic(const Duration(seconds: 6), (_) {
      final count = _service.ads.length;
      if (!mounted || count < 2 || !_pages.hasClients) return;
      _page = (_page + 1) % count;
      _pages.animateToPage(
        _page,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoPlay?.cancel();
    _pages.dispose();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final ads = _service.ads;
        final width = MediaQuery.of(context).size.width - 48;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_offer_outlined,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    L10n.t(context, 'offers'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 152,
              child: PageView.builder(
                controller: _pages,
                padEnds: false,
                onPageChanged: (value) => _page = value,
                itemCount: ads.isEmpty ? 3 : ads.length,
                itemBuilder:
                    (context, i) {
                      final loading = ads.isEmpty;
                      return Padding(
                        padding: EdgeInsets.only(
                          left: i == 0 ? 20 : 6,
                          right: 6,
                        ),
                        child: _FadeSlide(
                          delay: Duration(milliseconds: 120 + i * 120),
                          child: loading
                              ? _PlaceholderAdCard(
                                  width: width,
                                  onRetry: _service.error != null
                                      ? _service.load
                                      : null,
                                )
                              : _AdCard(ad: ads[i], width: width),
                        ),
                      );
                    },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Scrollable placeholder tiles shown while the ads endpoint is loading or
/// unreachable, so the offers strip keeps its shape (and "خطط لرحلتك" is gone).
/// If a network failure happened the tile turns into a retry card.
class _PlaceholderAdCard extends StatelessWidget {
  final double width;
  final VoidCallback? onRetry;

  const _PlaceholderAdCard({required this.width, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.surface,
              isDark ? AppColors.surfaceDark : AppColors.surface.withValues(alpha: 0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                onRetry != null
                    ? Icons.refresh_rounded
                    : Icons.local_offer_outlined,
                color: AppColors.textTertiary,
                size: 28,
              ),
              const SizedBox(height: 10),
              Text(
                onRetry != null
                    ? L10n.t(context, 'retry')
                    : L10n.t(context, 'offers'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One ad tile: an image (or a branded gradient when the image is missing),
/// the promo name, short details and a looping animated offer badge.
class _AdCard extends StatelessWidget {
  final AdItem ad;
  final double width;

  const _AdCard({required this.ad, required this.width});

  @override
  Widget build(BuildContext context) {
    final img = Formatters.imageUrl(ad.imageUrl);
    return GestureDetector(
      onTap: () =>
          Navigator.of(context).pushNamed('/event-detail', arguments: ad),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (img.isNotEmpty)
              Image.network(
                img,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackGradient(context),
              )
            else
              _fallbackGradient(context),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.62),
                  ],
                  stops: const [0.35, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _PulseOfferBadge(),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'OFFER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    ad.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ad.details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackGradient(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent, AppColors.accentDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.local_offer_rounded,
          size: 54,
          color: Colors.white.withValues(alpha: 0.28),
        ),
      ),
    );
  }
}

/// Tiny looping scale-pulse for the offer badge — purely cosmetic, no deps.
class _PulseOfferBadge extends StatefulWidget {
  const _PulseOfferBadge();

  @override
  State<_PulseOfferBadge> createState() => _PulseOfferBadgeState();
}

class _PulseOfferBadgeState extends State<_PulseOfferBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween(
    begin: 0.85,
    end: 1.15,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.local_offer_rounded,
          size: 15,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Lightweight entrance animation: fades + slides its child in once, with an
/// optional delay so list items stagger pleasantly.
class _FadeSlide extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _FadeSlide({required this.child, this.delay = Duration.zero});

  @override
  State<_FadeSlide> createState() => _FadeSlideState();
}

class _FadeSlideState extends State<_FadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Card that surfaces the passenger's next official ticket with a live
/// countdown to departure and a live bus-tracking strip — tapping opens the
/// boarding pass, and the strip opens the full-screen live tracking map.
class _BoardingNextCard extends StatelessWidget {
  final Ticket ticket;
  const _BoardingNextCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final stripColor = ticket.vehicleClass?.color ?? AppColors.accent;
    final mins = ticket.departure.difference(DateTime.now()).inMinutes;
    final countdown =
        mins > 0
            ? '${L10n.t(context, 'departsIn')} '
                '${mins >= 60 ? '${mins ~/ 60}${L10n.t(context, 'hoursShort')} ${mins % 60}${L10n.t(context, 'minutesShort')}' : '$mins${L10n.t(context, 'minutesShort')}'}'
            : L10n.t(context, 'boardingNow');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: SoftCard(
        accent: true,
        onTap:
            () => Navigator.of(context).pushNamed('/ticket', arguments: ticket),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: stripColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.confirmation_number_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.t(context, 'boardingNext'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${ticket.from} → ${ticket.to}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        egFormat(ticket.departure, 'EEE, HH:mm'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    countdown,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LiveBusStrip(ticket: ticket),
          ],
        ),
      ),
    );
  }
}

/// Promotes sign-in when the home shell is reached as a guest.
class _SignInCta extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: SoftCard(
        onTap: () => Navigator.of(context).pushNamed('/auth'),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.person_outline_rounded,
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
                    L10n.t(context, 'signInToBook'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    L10n.t(context, 'createAccountPrompt'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

/// One day card of the home 30-day carousel: weekday abbrev on top, big
/// day number centre, small month below. Index 0/1 swap the weekday for the
/// localized Today / Tomorrow word. The selected day is accent-filled.
class _DayCard extends StatelessWidget {
  final DateTime day;
  final DateTime today;
  final bool selected;
  final VoidCallback onTap;

  const _DayCard({
    required this.day,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labels = dayLabels(context, day);
    final n = day.difference(today).inDays;
    final topLabel =
        n == 0
            ? L10n.t(context, 'today')
            : n == 1
            ? L10n.t(context, 'tomorrow')
            : labels.weekday;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: _HomeTabState._cardWidth,
        decoration: BoxDecoration(
          color:
              selected
                  ? AppColors.accent
                  : isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.divider,
          ),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                  : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  topLabel,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              labels.dayNumber,
              style: TextStyle(
                fontSize: 22,
                height: 1.0,
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              labels.month,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white70 : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final ShuttleTrip trip;
  final List<ReservationTier> tiers;
  const _TripCard({required this.trip, this.tiers = const []});

  @override
  Widget build(BuildContext context) {
    final time = egFormat(trip.startTime, 'HH:mm');
    final free = trip.seatsRemaining;
    final vehicleColor = trip.vehicle?.color ?? AppColors.accent;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final occupancy =
        trip.totalSeats <= 0
            ? 1.0
            : (trip.totalSeats - free).clamp(0, trip.totalSeats) /
                trip.totalSeats;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: SoftCard(
        accent: true,
        onTap:
            () => Navigator.of(
              context,
            ).pushNamed('/trip-details', arguments: trip),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DateBadge(date: trip.startTime, height: 52),
                const SizedBox(width: 10),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: vehicleColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: vehicleColor.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    time,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
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
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: vehicleColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '${trip.vehicle?.name ?? L10n.t(context, 'shuttle')} · ${egFormat(trip.startTime, 'EEE')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.currency(trip.price),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            free > 0
                                ? AppColors.success.withValues(alpha: 0.12)
                                : AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        free > 0
                            ? '$free ${L10n.t(context, 'seatsFree')}'
                            : L10n.t(context, 'full'),
                        style: TextStyle(
                          fontSize: 11,
                          color: free > 0 ? AppColors.success : AppColors.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _RouteSummary(from: trip.fromName, to: trip.toName),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: occupancy.clamp(0.0, 1.0),
                minHeight: 4,
                color: vehicleColor,
                backgroundColor:
                    isDark ? AppColors.dividerDark : AppColors.divider,
              ),
            ),
            if (tiers.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tiers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final tier = tiers[i];
                    final chipColor = tier.isRecommended
                        ? AppColors.accent
                        : AppColors.textSecondary;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: tier.isRecommended
                            ? AppColors.accentSoft
                            : isDark
                            ? AppColors.surfaceDarkElevated
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: tier.isRecommended
                              ? AppColors.accent.withValues(alpha: 0.6)
                              : AppColors.divider,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_activity_outlined,
                            size: 12,
                            color: chipColor,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              tier.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: chipColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
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
        const Icon(Icons.trip_origin, size: 14, color: AppColors.accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            from,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(width: 22, height: 1, color: AppColors.divider),
        ),
        const Icon(Icons.location_on, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            to,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

