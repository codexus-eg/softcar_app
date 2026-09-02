import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Lightweight, dependency-free looping effect for event hero areas.
/// Built entirely on AnimationController + CustomPainter, it maps backend
/// `animation` values to a handful of particle looks (`fireworks`, `confetti`,
/// `sparkle`, `shimmer`, `float`, `rotate`, `shake`) and falls back to a
/// gentle entrance fade + scale sweep for everything else.
class EventFX extends StatefulWidget {
  final String animation;
  final Color accentColor;
  final Widget child;

  const EventFX({
    super.key,
    required this.animation,
    required this.child,
    this.accentColor = AppColors.accent,
  });

  @override
  State<EventFX> createState() => _EventFXState();
}

class _EventFXState extends State<EventFX> with SingleTickerProviderStateMixin {
  static const Set<String> _particleFx = {
    'fireworks',
    'confetti',
    'sparkle',
    'shimmer',
    'float',
    'rotate',
    'shake',
    'festival_cards',
    'flames',
    'water_splash',
  };

  static const Map<String, Duration> _durations = {
    'fireworks': Duration(milliseconds: 3200),
    'confetti': Duration(milliseconds: 2800),
    'sparkle': Duration(milliseconds: 2400),
    'shimmer': Duration(milliseconds: 2400),
    'float': Duration(milliseconds: 3400),
    'rotate': Duration(milliseconds: 5200),
    'shake': Duration(milliseconds: 900),
    'festival_cards': Duration(milliseconds: 3600),
    'flames': Duration(milliseconds: 1800),
    'water_splash': Duration(milliseconds: 2600),
  };

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration:
        _durations[widget.animation.toLowerCase()] ??
        const Duration(milliseconds: 2400),
  );

  String get _anim => widget.animation.toLowerCase();
  bool get _isParticle => _particleFx.contains(_anim);

  @override
  void initState() {
    super.initState();
    if (_isParticle) {
      _controller.repeat();
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_anim == 'shake') {
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final dx = math.sin(_controller.value * math.pi * 6) * 7;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: widget.child,
      );
    }
    if (_isParticle) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: CustomPaint(
              painter: _EventFXPainter(
                animation: _anim,
                accentColor: widget.accentColor,
                progress: _controller,
              ),
            ),
          ),
        ],
      );
    }
    final curved = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(curved),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Draws the looping particles. A fixed random seed + memoized fixtures keep
/// every frame stable so particles glide instead of flickering.
class _EventFXPainter extends CustomPainter {
  _EventFXPainter({
    required this.animation,
    required this.accentColor,
    required Animation<double> progress,
  }) : _progress = progress,
       super(repaint: progress);

  final String animation;
  final Color accentColor;
  final Animation<double> _progress;
  final math.Random _random = math.Random(7);

  late final double _hue = () {
    final h = HSLColor.fromColor(accentColor).hue;
    return h.isFinite ? h : 0.0;
  }();

  late final List<double> _spot = List.generate(64, (_) => _random.nextDouble());
  late final List<double> _phase = List.generate(
    64,
    (_) => _random.nextDouble(),
  );

  late final List<Color> _rainbow = List.generate(
    8,
    (i) =>
        HSLColor.fromAHSL(1, (_hue + i * 45) % 360, 0.78, 0.6).toColor(),
  );

  @override
  void paint(Canvas canvas, Size size) {
    switch (animation) {
      case 'fireworks':
        _paintFireworks(canvas, size);
        break;
      case 'confetti':
        _paintConfetti(canvas, size);
        break;
      case 'sparkle':
        _paintSparkle(canvas, size);
        break;
      case 'shimmer':
        _paintShimmer(canvas, size);
        break;
      case 'float':
        _paintFloat(canvas, size);
        break;
      case 'rotate':
        _paintRotate(canvas, size);
        break;
      case 'festival_cards':
        _paintFestivalCards(canvas, size);
        break;
      case 'flames':
        _paintFlames(canvas, size);
        break;
      case 'water_splash':
        _paintWaterSplash(canvas, size);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _EventFXPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.accentColor != accentColor;

  // ---- fireworks: rising sparks explode radially near the top -------------

  void _paintFireworks(Canvas canvas, Size size) {
    final t = _progress.value;
    const bursts = 3;
    for (var b = 0; b < bursts; b++) {
      final phase = (t + b / bursts) % 1.0;
      final x = size.width * (0.2 + 0.6 * _spot[b * 2]);
      final y = size.height * (0.16 + 0.34 * _spot[b * 2 + 1]);
      if (phase < 0.32) {
        final rise = Curves.easeOutCubic.transform(phase / 0.32);
        final pos = Offset.lerp(
          Offset(x, size.height * 1.05),
          Offset(x, y),
          rise,
        )!;
        _ball(canvas, pos, 1.5 + rise * 3, Colors.white.withValues(alpha: 0.9));
      } else {
        final p = (phase - 0.32) / 0.68;
        const sparks = 12;
        final base = _rainbow[b % _rainbow.length];
        for (var i = 0; i < sparks; i++) {
          final angle = (i / sparks) * math.pi * 2 + b * 0.4;
          final travel = Curves.easeOutCubic.transform(p) * size.width * 0.16;
          final sx = x + math.cos(angle) * travel;
          final sy = y + math.sin(angle) * travel * 0.7;
          final glow = (1 - p).clamp(0.0, 1.0);
          final mix = Color.lerp(base, Colors.white, _phase[(i + b * sparks) % 64])!;
          _ball(
            canvas,
            Offset(sx, sy),
            1.2 + glow * 2.4,
            mix.withValues(alpha: glow),
          );
        }
      }
    }
  }

  // ---- confetti: falling multi-colour rectangles --------------------------

  void _paintConfetti(Canvas canvas, Size size) {
    final t = _progress.value;
    const count = 26;
    for (var i = 0; i < count; i++) {
      final p = (t + i * 0.09) % 1.0;
      final x =
          size.width * (0.05 + 0.9 * _spot[i]) +
          math.sin(p * math.pi * 3 + i) * 14;
      final y = p * size.height * 1.12 - 24;
      final color = _rainbow[i % _rainbow.length].withValues(
        alpha: p > 0.9 ? 0.15 : 0.9,
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p * math.pi * 4 + i);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 9, height: 6),
        Paint()..color = color,
      );
      canvas.restore();
    }
  }

  // ---- sparkle: twinkling star particles -----------------------------------

  void _paintSparkle(Canvas canvas, Size size) {
    final t = _progress.value;
    const count = 16;
    for (var i = 0; i < count; i++) {
      final phase = (t + i * 0.11) % 1.0;
      final tw = Curves.easeInOut.transform(math.sin(phase * math.pi));
      final x = size.width * (0.1 + 0.8 * _spot[i]);
      final y = size.height * (0.08 + 0.7 * _spot[i + 16]);
      final r = 2 + tw * 4;
      _star(canvas, Offset(x, y), r, Colors.white.withValues(alpha: tw));
      _star(
        canvas,
        Offset(x + 7, y + 6),
        r * 0.6,
        accentColor.withValues(alpha: tw * 0.8),
      );
    }
  }

  // ---- shimmer: moving diagonal light sweep --------------------------------

  void _paintShimmer(Canvas canvas, Size size) {
    final t = _progress.value;
    final x = t * (size.width + size.height * 0.7) - size.height * 0.35;
    final band = Rect.fromLTWH(x - 130, -size.height * 0.1, 260, size.height * 1.2);
    final paint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.28),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(band);
    canvas.drawRect(band, paint);
  }

  // ---- float: gentle rising particles --------------------------------------

  void _paintFloat(Canvas canvas, Size size) {
    final t = _progress.value;
    const count = 16;
    for (var i = 0; i < count; i++) {
      final p = (t + i * 0.08) % 1.0;
      final x =
          size.width * (0.12 + 0.76 * _spot[i]) +
          math.sin((p + i) * math.pi * 2) * 16;
      final y = size.height * (1.05 - p * 1.15);
      final alpha = (1 - p).clamp(0.0, 1.0) * 0.7;
      final color = i.isEven ? accentColor : Colors.white;
      _ball(canvas, Offset(x, y), 1 + p * 2, color.withValues(alpha: alpha));
    }
  }

  // ---- rotate: slowly rotating glow ring -----------------------------------

  void _paintRotate(Canvas canvas, Size size) {
    final t = _progress.value;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.36;
    final angle = t * math.pi * 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = accentColor.withValues(alpha: 0.35),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      angle,
      math.pi * 0.75,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.95),
    );
    final comet = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    _ball(canvas, comet, 7, accentColor.withValues(alpha: 0.8));
    _ball(canvas, comet, 3, Colors.white);
  }

  void _paintFestivalCards(Canvas canvas, Size size) {
    final t = _progress.value;
    for (var i = 0; i < 18; i++) {
      final p = (t + i * 0.071) % 1;
      final depth = 0.45 + _phase[i] * 0.8;
      final x = size.width * (0.04 + _spot[i] * 0.92) +
          math.sin((p * 5 + i) * math.pi) * 18;
      final y = -28 + p * (size.height + 56);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p * math.pi * 3 + _phase[i] * math.pi);
      canvas.scale(depth, depth * (0.55 + math.sin(p * math.pi * 4).abs()));
      final rect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-13, -9, 26, 18),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, Paint()..color = _rainbow[i % 8]);
      canvas.drawLine(const Offset(-7, 0), const Offset(7, 0),
          Paint()..color = Colors.white70..strokeWidth = 1.5);
      canvas.restore();
    }
  }

  void _paintFlames(Canvas canvas, Size size) {
    final t = _progress.value;
    for (var i = 0; i < 22; i++) {
      final x = size.width * i / 21;
      final wave = 0.55 + 0.45 * math.sin(t * math.pi * 2 + i * 1.7);
      final height = 24 + 70 * wave * (0.5 + _spot[i] * 0.5);
      final path = Path()
        ..moveTo(x - 12, size.height)
        ..quadraticBezierTo(x - 10, size.height - height * 0.45,
            x, size.height - height)
        ..quadraticBezierTo(x + 12, size.height - height * 0.42,
            x + 14, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xFFFF2D00), Color(0xFFFFC400), Colors.white],
          ).createShader(Rect.fromLTWH(x - 15, size.height - height, 30, height)),
      );
    }
  }

  void _paintWaterSplash(Canvas canvas, Size size) {
    final t = _progress.value;
    final origin = Offset(size.width / 2, size.height * 0.88);
    for (var i = 0; i < 28; i++) {
      final p = (t + _phase[i] * 0.35) % 1;
      final angle = -math.pi * (0.12 + _spot[i] * 0.76);
      final speed = size.width * (0.16 + _phase[i] * 0.34);
      final x = origin.dx + math.cos(angle) * speed * p;
      final y = origin.dy + math.sin(angle) * speed * p +
          size.height * 0.55 * p * p;
      final alpha = (1 - p).clamp(0.0, 1.0);
      _ball(canvas, Offset(x, y), 2 + _spot[i] * 5,
          const Color(0xFF5DDCFF).withValues(alpha: alpha * 0.85));
    }
    canvas.drawOval(
      Rect.fromCenter(center: origin, width: size.width * (0.4 + t * 0.5), height: 18),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF9DEBFF).withValues(alpha: 1 - t),
    );
  }

  // ---- shared draw helpers ---------------------------------------------------

  void _ball(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()..color = color;
    canvas.drawCircle(center, radius, paint);
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r * 0.28, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r * 0.28, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }
}
