import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Branded launch scene: the SoftCar minibus logo "driving" on an animated
/// road while the app boots. The road dashes, streetlights and speed lines
/// scroll to simulate motion, and the bus gently bobs on its suspension.
///
/// Reuses the existing [logoAsset] — no new artwork needed. Wrap it in a
/// [Scaffold] with `backgroundColor: AppColors.ink` and use as the splash.
class BusRoadSplash extends StatefulWidget {
  /// Path of the minibus logo image (relative asset path).
  final String logoAsset;

  /// Short headline shown above the scene (e.g. the app slogan).
  final String tagline;

  /// Optional secondary line under the tagline (e.g. Arabic slogan).
  final String? subtitle;

  /// Brand accent used for the progress bar and light details.
  final Color accent;

  /// Optional known progress (0..1). When null, an indeterminate animated
  /// progress bar is shown instead.
  final double? progress;

  const BusRoadSplash({
    super.key,
    required this.logoAsset,
    required this.tagline,
    this.subtitle,
    this.accent = AppColors.accent,
    this.progress,
  });

  @override
  State<BusRoadSplash> createState() => _BusRoadSplashState();
}

class _BusRoadSplashState extends State<BusRoadSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final roadTop = h * 0.66;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Sky gradient
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0B0B0D), Color(0xFF1A1A1F)],
                ),
              ),
            ),
            // Distant city skyline silhouette
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: roadTop,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SkylinePainter(),
                  size: Size(w, roadTop),
                ),
              ),
            ),
            // Animated road + streetlights + speed lines
            Positioned(
              left: 0,
              right: 0,
              top: roadTop,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _RoadPainter(
                      t: _controller.value,
                      accent: widget.accent,
                    ),
                    size: Size(w, h - roadTop),
                  ),
                ),
              ),
            ),
            // Brand: wordmark + tagline
            Positioned(
              left: 24,
              right: 24,
              top: h * 0.10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SoftCarWordmark(size: 34),
                  const SizedBox(height: 12),
                  Text(
                    widget.tagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // The minibus logo driving on the road
            Positioned(
              left: 0,
              right: 0,
              bottom: h * 0.12,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    // Gentle suspension bob while rolling.
                    final bob =
                        math.sin(_controller.value * 2 * math.pi) * 3.5;
                    return Transform.translate(
                      offset: Offset(0, bob),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: [
                              BoxShadow(
                                color: widget.accent.withValues(alpha: 0.28),
                                blurRadius: 34,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: Image.asset(
                              widget.logoAsset,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Loading progress bar
            Positioned(
              left: 40,
              right: 40,
              bottom: h * 0.045,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final known = widget.progress;
                  if (known != null) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: known.clamp(0.0, 1.0),
                        minHeight: 5,
                        color: widget.accent,
                        backgroundColor: Colors.white12,
                      ),
                    );
                  }
                  // Indeterminate "headlights sweeping" bar.
                  final sweep = (_controller.value * 2) % 2.0;
                  final start = math.max(0.0, sweep - 0.45);
                  final end = math.min(1.0, sweep);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: end > start ? (end - start) : 0,
                      minHeight: 5,
                      color: widget.accent,
                      backgroundColor: Colors.white12,
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

/// The SoftCar wordmark in white (light-on-dark splash context).
class _SoftCarWordmark extends StatelessWidget {
  final double size;
  const _SoftCarWordmark({this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Soft',
          style: TextStyle(
            color: Colors.white,
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        Text(
          'Car',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }
}

/// Dark skyline silhouette rendered behind the road.
class _SkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF131318);
    final rnd = math.Random(7);
    var x = -20.0;
    while (x < size.width) {
      final bw = 42.0 + rnd.nextInt(70);
      final bh = size.height * (0.18 + rnd.nextDouble() * 0.42);
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - bh, bw, bh),
        paint,
      );
      x += bw + 14;
    }
  }

  @override
  bool shouldRepaint(covariant _SkylinePainter oldDelegate) => false;
}

/// Asphalt road with scrolling lane dashes, streetlights and speed lines.
class _RoadPainter extends CustomPainter {
  final double t;
  final Color accent;

  _RoadPainter({required this.t, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final laneH = h / 4;

    // Asphalt
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, h),
      Paint()..color = const Color(0xFF232328),
    );

    // Edge lines
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 2.5;
    for (var i = 0; i <= 3; i++) {
      final y = laneH * i;
      if (i == 0 || i == 3) {
        canvas.drawLine(Offset(0, y + 2), Offset(size.width, y + 2), edge);
      } else {
        // Center dashed lane marker, scrolling left to simulate forward motion.
        final dashLen = 26.0;
        final gap = 24.0;
        final cycle = dashLen + gap;
        final offset = (t * cycle * 2.2) % cycle;
        final dash = Paint()
          ..color = Colors.white.withValues(alpha: 0.75)
          ..strokeWidth = 3;
        var x = -offset;
        while (x < size.width) {
          canvas.drawLine(Offset(x, y), Offset(x + dashLen, y), dash);
          x += cycle;
        }
      }
    }

    // Streetlights scrolling along the road.
    final lampY = laneH * 1.5;
    final lightGap = 150.0;
    final lightOffset = (t * lightGap * 2.2) % lightGap;
    var lx = -lightOffset;
    while (lx < size.width) {
      final pole = Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..strokeWidth = 3;
      canvas.drawLine(Offset(lx, 0), Offset(lx, lampY - 10), pole);
      final head = Paint()
        ..color = accent.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(lx, lampY - 12), 4, head);
      final glow = Paint()
        ..color = accent.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(lx, lampY - 12), 13, glow);
      lx += lightGap;
    }

    // Speed lines near the bus's track (bottom quarter).
    final rnd = math.Random(11);
    final speed = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final n = 9;
    for (var i = 0; i < n; i++) {
      final baseY = h * 0.86 + rnd.nextInt(20);
      final len = 30.0 + rnd.nextInt(40);
      final baseX = (rnd.nextDouble() * size.width * 0.5) - 40;
      final x = baseX - ((t * 220) % 320);
      final wrapped = x < -80 ? x + size.width + 160 : x;
      canvas.drawLine(
        Offset(wrapped, baseY),
        Offset(wrapped + len, baseY),
        speed,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter oldDelegate) => oldDelegate.t != t;
}
