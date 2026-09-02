import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Branded in-app network video player used by ads and special events.
class SoftVideoPlayer extends StatefulWidget {
  final String url;
  final double height;
  final bool autoPlay;
  final bool loop;

  const SoftVideoPlayer({
    super.key,
    required this.url,
    this.height = 220,
    this.autoPlay = true,
    this.loop = true,
  });

  @override
  State<SoftVideoPlayer> createState() => _SoftVideoPlayerState();
}

class _SoftVideoPlayerState extends State<SoftVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SoftVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final old = _controller;
    _controller = null;
    await old?.dispose();
    final uri = Uri.tryParse(widget.url.trim());
    if (uri == null || !uri.hasScheme) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize();
      await controller.setLooping(widget.loop);
      await controller.setVolume(0);
      if (widget.autoPlay) await controller.play();
      if (!mounted) return controller.dispose();
      setState(() {
        _failed = false;
        _controller = controller;
      });
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              )
            else
              ColoredBox(
                color: const Color(0xFF11141B),
                child: Center(
                  child: _failed
                      ? const Icon(Icons.videocam_off_rounded,
                          color: Colors.white54, size: 40)
                      : const CircularProgressIndicator(color: Colors.white),
                ),
              ),
            if (controller != null)
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () {
                        setState(() {
                          controller.value.isPlaying
                              ? controller.pause()
                              : controller.play();
                        });
                      },
                      icon: Icon(controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white38,
                        ),
                      ),
                    ),
                    IconButton(
                      color: Colors.white,
                      onPressed: () {
                        setState(() => _muted = !_muted);
                        controller.setVolume(_muted ? 0 : 1);
                      },
                      icon: Icon(_muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded),
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
