import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Full-screen animated splash shown on every app start, in three beats:
///
/// 1. Silk ribbon flows across the screen.
/// 2. It swirls and gathers into the F with light trails and gold dust.
/// 3. It transforms into the glass logo, then the overlay fades away.
class AnimatedSplash extends StatefulWidget {
  const AnimatedSplash({super.key});

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4400),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _gone = true);
        }
      });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _window(double t, double start, double end) {
    if (t <= start) return 0.0;
    if (t >= end) return 1.0;
    final x = (t - start) / (end - start);
    return x * x * (3 - 2 * x); // smoothstep
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;

        // Beat 1: silk flow (0 -> fades 0.27-0.42), slow drift + zoom out.
        final flowA = 1.0 - _window(t, 0.27, 0.42);
        final flowScale = 1.14 - 0.10 * _window(t, 0.0, 0.42);
        final flowDx = -24.0 * _window(t, 0.0, 0.42);

        // Beat 2: swirling trails (in 0.27-0.42, out 0.62-0.77).
        final trailsA =
            _window(t, 0.27, 0.42) * (1.0 - _window(t, 0.62, 0.77));
        final trailsScale = 1.04 + 0.12 * _window(t, 0.27, 0.77);

        // Beat 3: the logo (in 0.62-0.80), wordmark (0.70-0.85).
        final logoA = _window(t, 0.62, 0.80);
        final logoScale = 0.92 + 0.08 * _window(t, 0.62, 0.85);
        final wordA = _window(t, 0.70, 0.85);

        // Overlay exits at the end.
        final overlayA = 1.0 - _window(t, 0.90, 1.0);

        return Opacity(
          opacity: overlayA,
          child: Container(
            color: const Color(0xFF19031E),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Beat 1
                Opacity(
                  opacity: flowA,
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translate(flowDx)
                      ..scale(flowScale),
                    alignment: Alignment.center,
                    child: Image.asset(
                      'assets/images/splash_flow.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                // Beat 2
                Opacity(
                  opacity: trailsA,
                  child: Transform.scale(
                    scale: trailsScale,
                    child: Image.asset(
                      'assets/images/splash_trails.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                // Gold dust over beats 1-2.
                CustomPaint(
                  painter: _DustPainter(
                    time: t,
                    alpha: (1.0 - logoA) *
                        math.max(flowA, trailsA).clamp(0.0, 1.0),
                  ),
                ),
                // Beat 3
                Opacity(
                  opacity: logoA,
                  child: Center(
                    child: Transform.scale(
                      scale: logoScale,
                      child: Image.asset(
                        'assets/images/splash_logo.png',
                        width: 220,
                        height: 220,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: wordA,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 300),
                        Text(
                          'FLIXTENDED',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Particle {
  _Particle(math.Random rand)
      : x = rand.nextDouble(),
        y = rand.nextDouble(),
        r = 1.0 + rand.nextDouble() * 2.2,
        phase = rand.nextDouble() * math.pi * 2,
        speed = 0.4 + rand.nextDouble() * 0.9,
        gold = rand.nextDouble() > 0.35;

  final double x;
  final double y;
  final double r;
  final double phase;
  final double speed;
  final bool gold;
}

/// Drifting gold dust that twinkles while the ribbon flows and swirls.
class _DustPainter extends CustomPainter {
  _DustPainter({required this.time, required this.alpha});

  final double time;
  final double alpha;

  static final _particles =
      List.generate(46, (_) => _Particle(math.Random(7)));

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.01) return;
    for (final p in _particles) {
      final tw = 0.5 + 0.5 * math.sin(time * 12.0 * p.speed + p.phase);
      final a = (0.10 + 0.45 * tw) * alpha;
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.r,
        Paint()
          ..color = p.gold
              ? const Color(0xFFD9A441).withOpacity(a)
              : Colors.white.withOpacity(a * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DustPainter old) =>
      old.time != time || old.alpha != alpha;
}
