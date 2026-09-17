import 'dart:math' as math;
import 'package:flutter/material.dart';

class NeonWaveformWidget extends StatefulWidget {
  final bool isPlaying;
  final double height;

  const NeonWaveformWidget({
    super.key,
    required this.isPlaying,
    this.height = 54,
  });

  @override
  State<NeonWaveformWidget> createState() => _NeonWaveformWidgetState();
}

class _NeonWaveformWidgetState extends State<NeonWaveformWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isPlaying) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant NeonWaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _animController.repeat();
      } else {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return SizedBox(
          height: widget.height,
          child: CustomPaint(
            painter: _SpectrumPainter(
              progress: _animController.value,
              isPlaying: widget.isPlaying,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;

  _SpectrumPainter({required this.progress, required this.isPlaying});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final width = size.width;
    const points = 80;

    final shader = const LinearGradient(
      colors: [
        Color(0xFF00E5FF), // Electric Cyan
        Color(0xFF00B0FF), // Neon Blue
        Color(0xFFB388FF), // Lavender
        Color(0xFFC040FD), // Electric Purple/Magenta
      ],
      stops: [0.0, 0.35, 0.7, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, width, size.height));

    final secondaryShader = const LinearGradient(
      colors: [
        Color(0x8000E5FF),
        Color(0x80B388FF),
        Color(0x80C040FD),
      ],
    ).createShader(Rect.fromLTWH(0, 0, width, size.height));

    // Glow paint for intense neon halo
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

    // Sharp foreground neon line
    final mainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = shader;

    // Secondary background harmonic wave
    final secondaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..shader = secondaryShader;

    final primaryPath = Path();
    final secondaryPath = Path();

    final phase = isPlaying ? (progress * 2 * math.pi) : 0.0;
    final maxAmp = size.height * (isPlaying ? 0.44 : 0.12);

    for (int i = 0; i <= points; i++) {
      final normX = i / points;
      final x = normX * width;
      // Envelope: natural taper at edges
      final envelope = math.sin(normX * math.pi);

      // Primary wave
      final f1 = math.sin((i * 0.42) + phase);
      final f2 = math.cos((i * 0.82) - (phase * 0.7));
      final amp1 = (f1 * 0.65 + f2 * 0.35) * maxAmp * envelope;
      final y1 = midY + amp1;

      // Secondary wave (harmonic counter-phase)
      final sf1 = math.sin((i * 0.55) - (phase * 1.3));
      final sf2 = math.cos((i * 0.35) + (phase * 0.9));
      final amp2 = (sf1 * 0.55 + sf2 * 0.45) * (maxAmp * 0.65) * envelope;
      final y2 = midY + amp2;

      if (i == 0) {
        primaryPath.moveTo(x, y1);
        secondaryPath.moveTo(x, y2);
      } else {
        primaryPath.lineTo(x, y1);
        secondaryPath.lineTo(x, y2);
      }
    }

    // Draw secondary harmonic line first
    canvas.drawPath(secondaryPath, secondaryPaint);
    // Draw neon halo glow pass
    canvas.drawPath(primaryPath, glowPaint);
    // Draw crisp sharp neon line on top
    canvas.drawPath(primaryPath, mainPaint);
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isPlaying != isPlaying;
  }
}
