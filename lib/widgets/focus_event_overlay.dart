import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../services/ads_service.dart';
import 'event_fx.dart';
import 'soft_video_player.dart';

Future<bool?> showFocusEventOverlay(BuildContext context, AdItem ad) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FocusEventDialog(ad: ad),
  );
}

class _FocusEventDialog extends StatefulWidget {
  final AdItem ad;
  const _FocusEventDialog({required this.ad});

  @override
  State<_FocusEventDialog> createState() => _FocusEventDialogState();
}

class _FocusEventDialogState extends State<_FocusEventDialog> {
  Timer? _timer;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.ad.displaySeconds < 10 ? 10 : widget.ad.displaySeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remaining <= 1) {
        timer.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final image = Formatters.imageUrl(ad.imageUrl);
    final hasVideo = ad.mediaType.toUpperCase() == 'VIDEO' &&
        ad.videoUrl.trim().isNotEmpty;
    return PopScope(
      canPop: _remaining == 0,
      child: Dialog(
        insetPadding: const EdgeInsets.all(18),
        clipBehavior: Clip.antiAlias,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 300,
                  child: EventFX(
                    animation: ad.animation,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasVideo)
                          SoftVideoPlayer(url: ad.videoUrl, height: 300)
                        else if (image.isNotEmpty)
                          Image.network(image, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder())
                        else
                          _placeholder(),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                              stops: [0.5, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 18,
                          child: Text(ad.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              )),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: _remaining == 0
                                ? IconButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    icon: const Icon(Icons.close,
                                        color: Colors.white),
                                  )
                                : Text('$_remaining',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    )),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(L10n.t(context, 'focusEventTitle'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w900,
                          )),
                      if (ad.details.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(ad.details,
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _remaining == 0
                            ? () => Navigator.pop(context, true)
                            : null,
                        icon: const Icon(Icons.celebration_rounded),
                        label: Text(_remaining == 0
                            ? L10n.t(context, 'focusEventView')
                            : '${L10n.t(context, 'focusEventView')} · $_remaining ${L10n.t(context, 'seconds')}'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.accent, AppColors.accentDark],
          ),
        ),
        child: Center(
          child: Icon(Icons.celebration_rounded,
              color: Colors.white54, size: 72),
        ),
      );
}
