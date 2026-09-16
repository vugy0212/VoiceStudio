import 'dart:math' as math;
import 'package:flutter/material.dart';

class NeonWaveformWidget extends StatefulWidget {
  final bool isPlaying;

  const NeonWaveformWidget({
    super.key,
    required this.isPlaying,
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
      duration: const Duration(milliseconds: 1800),
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
          height: 62,
          child: CustomPaint(
            painter: _WaveformPainter(
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

class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;

  _WaveformPainter({required this.progress, required this.isPlaying});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final width = size.width;

    final path = Path();
    final points = 75;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final mainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final shader = const LinearGradient(
      colors: [
        Color(0xFF00E5FF), // Electric Cyan
        Color(0xFF00B0FF),
        Color(0xFFB388FF),
        Color(0xFFC040FD), // Electric Purple/Magenta
      ],
      stops: [0.0, 0.4, 0.7, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, width, size.height));

    glowPaint.shader = shader;
    glowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
    mainPaint.shader = shader;

    path.moveTo(0, midY);

    for (int i = 0; i <= points; i++) {
      final x = (i / points) * width;
      // Envelope: tapers near left and right edges like in mockup
      final envelope = math.sin((i / points) * math.pi);

      final phase = isPlaying ? (progress * 2 * math.pi) : 0.0;
      final freq1 = math.sin((i * 0.45) + phase);
      final freq2 = math.cos((i * 0.85) - (phase * 0.7));
      final amp = (freq1 * 0.65 + freq2 * 0.35) * (size.height * 0.44) * envelope;

      final y = midY + amp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw neon glow pass first, then crisp sharp pass on top
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, mainPaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isPlaying != isPlaying;
  }
}
