import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev4_quadikran_monitoring/screens/main_nav_screen.dart';
import 'package:rev4_quadikran_monitoring/screens/login_page_screen.dart';

const _kNavy = Color(0xFF030B1F);
const _kBrightNavy = Color(0xFF1F3F7A);
const _kAmber = Color(0xFFF39C12);
const _kAmberLight = Color(0xFFFFBF47);
const _kPrimaryCyan = Color(0xFF06B6D4);
const _kPrimaryBlue = Color(0xFF3B82F6);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _orbitCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _barCtrl;
  late final AnimationController _companyNameCtrl;
  late final AnimationController _btAnimCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _pulse;
  late final Animation<double> _orbit;
  late final Animation<double> _glow;
  late final Animation<double> _bar;
  late final Animation<double> _companyNameOpacity;
  late final Animation<Offset> _companyNameSlide;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });

    SystemChannels.textInput.invokeMethod('TextInput.hide');

    // Initialize
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );
    _companyNameCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _btAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Logo entrance
    _logoScale = CurvedAnimation(
      parent: _introCtrl,
      curve: const ElasticOutCurve(0.7),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _introCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Title animations
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textCtrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _textCtrl,
            curve: const Interval(0.0, 0.65, curve: Curves.easeOutQuint),
          ),
        );

    _subtitleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textCtrl,
        curve: const Interval(0.35, 0.8, curve: Curves.easeOut),
      ),
    );

    _companyNameOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _companyNameCtrl, curve: Curves.easeOut));
    _companyNameSlide =
        Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _companyNameCtrl, curve: Curves.easeOutCubic),
        );

    _orbit = Tween<double>(begin: 0, end: 2 * math.pi).animate(_orbitCtrl);
    _pulse = Tween<double>(begin: 0.95, end: 1.0).animate(_pulseCtrl);
    _glow = Tween<double>(begin: 0.3, end: 0.8).animate(_glowCtrl);
    _bar = CurvedAnimation(parent: _barCtrl, curve: Curves.easeInOut);

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 250));
    _introCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _textCtrl.forward();
    _barCtrl.forward();
    _companyNameCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 4500));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            isLoggedIn ? const MainNavScreen() : const LoginPage(),
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.7, curve: Curves.easeIn),
          );
          final scale = Tween<double>(begin: 0.96, end: 1.0).animate(
            CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
            ),
          );
          final slide =
              Tween<Offset>(
                begin: const Offset(0.0, 0.03),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 1.0, curve: Curves.easeOutQuint),
                ),
              );
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _textCtrl.dispose();
    _pulseCtrl.dispose();
    _orbitCtrl.dispose();
    _glowCtrl.dispose();
    _barCtrl.dispose();
    _companyNameCtrl.dispose();
    _btAnimCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: _kPrimaryBlue,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color.fromARGB(255, 20, 92, 133).withAlpha(200),
              const Color.fromARGB(255, 6, 62, 153),
              const Color.fromARGB(255, 31, 63, 122),
              const Color.fromARGB(255, 11, 44, 93),
              const Color.fromARGB(255, 1, 5, 22),
            ],
          ),
        ),
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_orbitCtrl, _glowCtrl]),
              builder: (_, _) => CustomPaint(
                size: size,
                painter: _StarfieldPainter(
                  orbit: _orbit.value,
                  glowAlpha: _glow.value,
                ),
              ),
            ),

            Positioned(
              bottom: -60,
              left: -60,
              child: AnimatedBuilder(
                animation: _glowCtrl,
                builder: (_, _) => Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _kBrightNavy.withValues(alpha: _glow.value * 0.5),
                        _kNavy.withValues(alpha: _glow.value * 0.3),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Company logo
            Positioned(
              top: 30,
              right: 12,
              child: SlideTransition(
                position: _companyNameSlide,
                child: FadeTransition(
                  opacity: _companyNameOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Color.fromARGB(255, 255, 255, 255),
                                Color.fromARGB(255, 255, 255, 255),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color.fromARGB(
                                  255,
                                  255,
                                  255,
                                  255,
                                ).withValues(alpha: 0.3),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            child: Image.asset(
                              'assets/images/Intellicontrol Final Logo300PPI.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.business,
                                  size: 16,
                                  color: Colors.white,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo badge
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _pulseCtrl,
                      _orbitCtrl,
                      _glowCtrl,
                      _btAnimCtrl,
                    ]),
                    builder: (context, _) {
                      return FadeTransition(
                        opacity: _logoOpacity,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: ScaleTransition(
                            scale: _pulse,
                            child: _LogoBadge(
                              orbit: _orbit.value,
                              glow: _glow.value,
                              btPhase: _btAnimCtrl.value,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  SlideTransition(
                    position: _titleSlide,
                    child: FadeTransition(
                      opacity: _titleOpacity,
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (b) => const LinearGradient(
                              colors: [Colors.white, _kAmberLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(b),
                            child: const Text(
                              'QuadiKRAN Connect',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Asul',
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.8,
                                height: 1,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 40,
                                height: 1,
                                color: _kAmber.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'v 1.0.0',
                                style: TextStyle(
                                  fontFamily: 'Rajdhani',
                                  fontSize: 11,
                                  color: Colors.white38,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 40,
                                height: 1,
                                color: _kAmber.withValues(alpha: 0.5),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  FadeTransition(
                    opacity: _subtitleOpacity,
                    child: SizedBox(
                      height: 24,
                      child: AnimatedTextKit(
                        isRepeatingAnimation: false,
                        animatedTexts: [
                          FadeAnimatedText(
                            'Bluetooth PLC Monitoring System',
                            textStyle: const TextStyle(
                              fontFamily: 'Asul',
                              fontSize: 13,
                              color: Colors.white54,
                              letterSpacing: 2,
                            ),
                            duration: const Duration(milliseconds: 2400),
                          ),
                          FadeAnimatedText(
                            'Real-time Control & Insights',
                            textStyle: const TextStyle(
                              fontFamily: 'Asul',
                              fontSize: 13,
                              color: Colors.white54,
                              letterSpacing: 2,
                            ),
                            duration: const Duration(milliseconds: 2400),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),
                ],
              ),
            ),

            Positioned(
              bottom: 44,
              left: 40,
              right: 40,
              child: FadeTransition(
                opacity: _subtitleOpacity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SYSTEM INITIALISING',
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white38,
                            letterSpacing: 2,
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _barCtrl,
                          builder: (_, _) => Text(
                            '${(_bar.value * 100).toInt()}%',
                            style: TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _kAmber.withValues(alpha: 0.7),
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 3,
                        color: Colors.white.withValues(alpha: 0.08),
                        child: AnimatedBuilder(
                          animation: _bar,
                          builder: (_, _) => FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _bar.value,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_kAmber, _kAmberLight],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kAmber.withValues(alpha: 0.6),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge({
    required this.orbit,
    required this.glow,
    required this.btPhase,
  });

  final double orbit;
  final double glow;
  final double btPhase;

  static const double _outer = 200.0;
  static const double _inner = 158.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _outer,
      height: _outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Inner accent ring
          Container(
            width: _inner + 12,
            height: _inner + 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _kAmberLight.withValues(alpha: 0.22 + glow * 0.3),
                width: 1.0,
              ),
            ),
          ),

          Container(
            width: _inner,
            height: _inner,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Color.fromARGB(255, 22, 38, 71),
                  Color.fromARGB(255, 13, 31, 55),
                ],
                center: Alignment.topLeft,
                radius: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.lightBlueAccent.withValues(
                    alpha: 0.2 + glow * 0.1,
                  ),
                  blurRadius: 28 + glow * 20,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 22,
                  spreadRadius: 2,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
          ),

          // Bluetooth symbol
          SizedBox(
            width: _inner,
            height: _inner,
            child: CustomPaint(painter: _BluetoothSymbolPainter(btPhase)),
          ),
        ],
      ),
    );
  }
}

class _BluetoothSymbolPainter extends CustomPainter {
  const _BluetoothSymbolPainter(this.phase);

  final double phase;

  // Precomputed vertices as static const
  static const List<Offset> _vertices = [
    Offset(-8.500, -8.531),
    Offset(8.141, 7.492),
    Offset(-0.211, 15.531),
    Offset(-0.211, -15.332),
    Offset(7.500, -7.516),
    Offset(-8.500, 8.500),
  ];

  static const double _spanY = 30.863;

  // Cache paint objects to avoid recreation
  static final Paint _ghostPaint = Paint()
    ..color = _kPrimaryBlue.withValues(alpha: 0.5)
    ..strokeWidth = 0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final Paint _sparkCorePaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.95);

  @override
  void paint(Canvas canvas, Size size) {
    final fitScale = size.height * 0.58 / _spanY;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final path = Path();
    for (int i = 0; i < _vertices.length; i++) {
      final pt = Offset(
        cx + _vertices[i].dx * fitScale,
        cy + _vertices[i].dy * fitScale,
      );
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final total = metric.length;

    void drawSeg(double start, double len, Paint p) {
      final ns = start % total;
      final end = ns + len;
      if (end <= total) {
        canvas.drawPath(metric.extractPath(ns, end), p);
      } else {
        canvas.drawPath(metric.extractPath(ns, total), p);
        canvas.drawPath(metric.extractPath(0.0, end - total), p);
      }
    }

    // Broadcast rings
    for (int r = 0; r < 7; r++) {
      final lag = r / 5.0;
      final rPhase = ((phase - lag) % 1.0 + 1.0) % 1.0;
      final alpha = math.pow(1.0 - rPhase, 1.8).toDouble() * 0.42;
      if (alpha < 0.015) continue;

      final radius = 6.0 + rPhase * size.height * 0.5;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color.fromARGB(
            255,
            255,
            7,
            7,
          ).withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 + (1.0 - rPhase) * 1.2,
      );
    }

    // Ghost outline
    _ghostPaint.strokeWidth = size.height * 0.042;
    canvas.drawPath(path, _ghostPaint);

    const segFrac = 0.55;
    const tailFrac = 0.2;
    final segLen = segFrac * total;
    final tailLen = tailFrac * segLen;
    final bodyLen = segLen - tailLen;
    final s = phase * total;

    // Tail
    drawSeg(
      s,
      tailLen,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _kBrightNavy.withValues(alpha: 0.0),
            _kBrightNavy.withValues(alpha: 0.55),
          ],
        ).createShader(rect)
        ..strokeWidth = size.height * 0.038
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Body
    drawSeg(
      s + tailLen,
      bodyLen,
      Paint()
        ..shader = const LinearGradient(
          colors: [_kPrimaryCyan, Colors.white, _kPrimaryBlue],
          stops: [0.0, 0.50, 1.0],
        ).createShader(rect)
        ..strokeWidth = size.height * 0.052
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Spark at leading edge
    final sparkOff = (s + segLen) % total;
    final tangent = metric.getTangentForOffset(sparkOff);
    if (tangent != null) {
      final sp = tangent.position;
      canvas.drawCircle(
        sp,
        size.height * 0.046,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawCircle(
        sp,
        size.height * 0.026,
        Paint()
          ..color = _kPrimaryCyan.withValues(alpha: 0.80)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      _sparkCorePaint.color = Colors.white.withValues(alpha: 0.95);
      canvas.drawCircle(sp, size.height * 0.014, _sparkCorePaint);
    }
  }

  @override
  bool shouldRepaint(_BluetoothSymbolPainter old) => old.phase != phase;
}

// Starfield node class
class _StarNode {
  final double bx, by;
  final double freq;
  final double phase;
  final double ampX, ampY;
  final double depth;
  final bool isHub;
  final double size;
  final double pOff;

  const _StarNode({
    required this.bx,
    required this.by,
    required this.freq,
    required this.phase,
    required this.ampX,
    required this.ampY,
    required this.depth,
    required this.isHub,
    required this.size,
    required this.pOff,
  });
}

// Starfield painter with cached nodes
class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({required this.orbit, required this.glowAlpha});
  final double orbit;
  final double glowAlpha;

  static final math.Random _rng = math.Random(42); //
  static final List<_StarNode> _nodes = List.generate(30, (i) {
    final isHub = i % 8 == 0;
    return _StarNode(
      bx: _rng.nextDouble(),
      by: _rng.nextDouble(),
      freq: 0.25 + _rng.nextDouble() * 0.75,
      phase: _rng.nextDouble() * 2 * math.pi,
      ampX: 0.015 + _rng.nextDouble() * 0.045,
      ampY: 0.015 + _rng.nextDouble() * 0.045,
      depth: _rng.nextDouble(),
      isHub: isHub,
      size: isHub
          ? 2.2 + _rng.nextDouble() * 1.4
          : 0.7 + _rng.nextDouble() * 1.8,
      pOff: _rng.nextDouble(),
    );
  });

  static const double _connectFrac = 0.27;

  // Cache paint objects
  static final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.65;

  static final Paint _pulsePaint = Paint()..style = PaintingStyle.fill;
  static final Paint _nodePaint = Paint()..style = PaintingStyle.fill;
  static final Paint _haloPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

  @override
  void paint(Canvas canvas, Size size) {
    final threshold = _connectFrac * math.min(size.width, size.height);
    final t = orbit / (2 * math.pi);

    // Precompute positions
    final positions = List.generate(_nodes.length, (i) {
      final n = _nodes[i];
      final x =
          (n.bx + math.sin(orbit * n.freq + n.phase) * n.ampX) * size.width;
      final y =
          (n.by + math.cos(orbit * n.freq * 0.7 + n.phase + 1.1) * n.ampY) *
          size.height;
      return Offset(x.clamp(0.0, size.width), y.clamp(0.0, size.height));
    });

    // Draw connections and pulses
    for (int i = 0; i < _nodes.length; i++) {
      for (int j = i + 1; j < _nodes.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        if (d > threshold) continue;

        final fade = 1.0 - d / threshold;
        _linePaint.color = _kPrimaryBlue.withValues(
          alpha: fade * glowAlpha * 0.28,
        );
        canvas.drawLine(positions[i], positions[j], _linePaint);

        if (!_nodes[i].isHub && !_nodes[j].isHub) continue;
        final tPulse = (t * 2.2 + _nodes[i].pOff) % 1.0;
        final px =
            positions[i].dx + (positions[j].dx - positions[i].dx) * tPulse;
        final py =
            positions[i].dy + (positions[j].dy - positions[i].dy) * tPulse;
        _pulsePaint.color = _kAmber.withValues(alpha: fade * glowAlpha * 0.82);
        canvas.drawCircle(Offset(px, py), 1.8, _pulsePaint);
      }
    }

    // Draw nodes
    for (int i = 0; i < _nodes.length; i++) {
      final n = _nodes[i];
      final p = positions[i];
      final alpha = (0.20 + n.depth * 0.80) * glowAlpha;

      if (n.isHub) {
        // Halo
        canvas.drawCircle(
          p,
          n.size * 5.5,
          _haloPaint..color = _kPrimaryBlue.withValues(alpha: alpha * 0.10),
        );
        // Outer ring
        canvas.drawCircle(
          p,
          n.size * 2.8,
          Paint()
            ..color = _kPrimaryBlue.withValues(alpha: alpha * 0.52)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.85,
        );
        // Inner ring
        canvas.drawCircle(
          p,
          n.size * 1.6,
          Paint()
            ..color = _kPrimaryBlue.withValues(alpha: alpha * 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
        // Crosshair
        final cr = n.size * 4.2;
        final crossPaint = Paint()
          ..color = _kPrimaryBlue.withValues(alpha: alpha * 0.38)
          ..strokeWidth = 0.65
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(p.dx - cr, p.dy),
          Offset(p.dx + cr, p.dy),
          crossPaint,
        );
        canvas.drawLine(
          Offset(p.dx, p.dy - cr),
          Offset(p.dx, p.dy + cr),
          crossPaint,
        );
        // Core
        _nodePaint.color = _kPrimaryBlue.withValues(alpha: alpha);
        canvas.drawCircle(p, n.size, _nodePaint);
      } else {
        _nodePaint.color = Colors.white.withValues(alpha: alpha * 0.70);
        canvas.drawCircle(p, n.size, _nodePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) =>
      old.orbit != orbit || old.glowAlpha != glowAlpha;
}
