import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The temporary-chat icon, as in ChatGPT: a round speech bubble (tail at the bottom left) drawn as a
/// dashed outline — it is not kept — with a check mark inside while temporary chat is on.
class TemporaryChatIcon extends StatelessWidget {
  const TemporaryChatIcon({super.key, required this.on, required this.color, this.size = 24});

  final bool on;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _TemporaryChatPainter(on: on, color: color),
  );
}

class _TemporaryChatPainter extends CustomPainter {
  _TemporaryChatPainter({required this.on, required this.color});

  final bool on;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24-unit grid, scaled to the icon's size.
    final k = size.width / 24;
    canvas.scale(k, k);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const center = Offset(12.3, 11.6);
    const r = 8.2;
    Offset at(double degrees, [double scale = 1]) {
      final a = degrees * math.pi / 180;
      return center + Offset(math.cos(a), math.sin(a)) * r * scale;
    }

    final circle = Rect.fromCircle(center: center, radius: r);
    double rad(double degrees) => degrees * math.pi / 180;

    // Four arcs with gaps between them (angles clockwise from the right, y down).
    canvas
      ..drawArc(circle, rad(228), rad(86), false, pen) // top
      ..drawArc(circle, rad(-27), rad(45), false, pen) // right
      ..drawArc(circle, rad(38), rad(36), false, pen); // bottom right

    // Left side: down into the tail at the bottom left, then along the bottom.
    final tail = Path()
      ..moveTo(at(203).dx, at(203).dy)
      ..lineTo(center.dx - r * 0.86, center.dy + r * 0.78)
      ..lineTo(at(101).dx, at(101).dy);
    canvas.drawPath(tail, pen);

    if (on) {
      final check = Path()
        ..moveTo(center.dx - r * 0.36, center.dy + r * 0.06)
        ..lineTo(center.dx - r * 0.1, center.dy + r * 0.32)
        ..lineTo(center.dx + r * 0.38, center.dy - r * 0.34);
      canvas.drawPath(check, pen);
    }
  }

  @override
  bool shouldRepaint(_TemporaryChatPainter old) => old.on != on || old.color != color;
}
