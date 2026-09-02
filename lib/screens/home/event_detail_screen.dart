import 'package:flutter/material.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/ads_service.dart';
import '../../services/passenger_api.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/event_fx.dart';
import '../../widgets/soft_video_player.dart';

/// Full-page event viewer: a large animated hero (ad image or branded accent
/// gradient), the event name, full details, small animation chips and a
/// "Rules / شروط الفعالية" section when the ad carries rules text.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  AdItem? _ad;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is AdItem) {
        _ad = args;
        passengerApi.reportAdView(args.id);
      }
    }
  }

  Color get _accent {
    final raw = _ad?.accentColor.trim() ?? '';
    if (raw.isEmpty) return AppColors.accent;
    final hex = raw.replaceFirst('#', '');
    final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return value == null ? AppColors.accent : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final accent = _accent;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: accent,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: EventFX(
                animation: ad.animation,
                accentColor: accent,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _heroImage(ad, accent),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black45],
                          stops: [0.55, 1],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _body(ad, accent)),
        ],
      ),
    );
  }

  Widget _heroImage(AdItem ad, Color accent) {
    final img = Formatters.imageUrl(ad.imageUrl);
    final accentDark = Color.lerp(accent, Colors.black, 0.35) ?? accent;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accentDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.celebration_rounded,
          size: 72,
          color: Colors.white.withValues(alpha: 0.32),
        ),
      ),
    );
    if (img.isEmpty) return placeholder;
    return Image.network(
      img,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }

  Widget _body(AdItem ad, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ad.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          if (ad.mediaType == 'VIDEO' && ad.videoUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            SoftVideoPlayer(
              url: ad.videoUrl,
              height: 230,
            ),
          ],
          const SizedBox(height: 12),
          _chips(ad),
          if (ad.details.trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              ad.details,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
          if (ad.rules.trim().isNotEmpty) ...[
            const SizedBox(height: 24),
            _rulesCard(ad),
          ],
        ],
      ),
    );
  }

  Widget _chips(AdItem ad) {
    final anim = ad.animation.trim().toLowerCase();
    final label = anim.isEmpty ? '' : _cap(anim);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          Icons.auto_awesome_rounded,
          anim.isEmpty
              ? L10n.t(context, 'animationLabel')
              : '${L10n.t(context, 'animationLabel')} · $label',
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rulesCard(AdItem ad) {
    final lines = ad.rules
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                size: 18,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                L10n.t(context, 'eventRules'),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
