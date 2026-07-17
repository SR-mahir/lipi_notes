import 'package:flutter/material.dart';
import '../models/stroke_model.dart';

class StrokePainter extends CustomPainter {
  final List<DrawingStroke> history;
  final DrawingStroke? currentStroke;

  StrokePainter({required this.history, this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    for (var stroke in history) {
      _drawStroke(canvas, stroke);
    }
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;
    
    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (stroke.points.length < 3) {
      if (stroke.points.length == 1) {
        final p = stroke.points.first;
        final w = stroke.strokeWidth * (0.5 + 0.8 * p.pressure);
        canvas.drawCircle(p.point, w / 2, paint..style = PaintingStyle.fill);
      } else {
        final p0 = stroke.points[0];
        final p1 = stroke.points[1];
        final w0 = stroke.strokeWidth * (0.5 + 0.8 * p0.pressure);
        final w1 = stroke.strokeWidth * (0.5 + 0.8 * p1.pressure);
        paint.strokeWidth = (w0 + w1) / 2;
        canvas.drawLine(p0.point, p1.point, paint);
      }
      return;
    }

    double prevWidth = stroke.strokeWidth * (0.5 + 0.8 * stroke.points.first.pressure);

    for (int i = 1; i < stroke.points.length - 1; i++) {
      final pPrev = stroke.points[i - 1];
      final pCurr = stroke.points[i];
      final pNext = stroke.points[i + 1];

      // Calculate velocity (distance/time)
      final distance = (pCurr.point - pPrev.point).distance;
      final timeDiff = pCurr.timestamp.difference(pPrev.timestamp).inMicroseconds / 1000000.0;
      final velocity = timeDiff > 0 ? (distance / timeDiff) : 0.0;

      // Stylus pressure tracking and velocity-based thickness scaling
      final pressureFactor = 0.5 + 0.8 * pCurr.pressure;
      // Faster velocity makes the stroke thinner (up to 50% thinner)
      final velocityFactor = 1.0 - (velocity / 2000.0).clamp(0.0, 0.5);
      final rawWidth = stroke.strokeWidth * pressureFactor * velocityFactor;
      
      // Smooth width changes with a low-pass filter
      final currentWidth = prevWidth + (rawWidth - prevWidth) * 0.3;
      prevWidth = currentWidth;

      paint.strokeWidth = currentWidth;

      // Build smoothed quadratic Bezier segment
      final start = i == 1 
          ? pPrev.point 
          : Offset((pPrev.point.dx + pCurr.point.dx) / 2, (pPrev.point.dy + pCurr.point.dy) / 2);
      final end = Offset((pCurr.point.dx + pNext.point.dx) / 2, (pCurr.point.dy + pNext.point.dy) / 2);

      final path = Path();
      path.moveTo(start.dx, start.dy);
      path.quadraticBezierTo(pCurr.point.dx, pCurr.point.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }

    // Connect final segment
    final lastIdx = stroke.points.length - 1;
    final pPenultimate = stroke.points[lastIdx - 1];
    final pLast = stroke.points[lastIdx];
    final start = Offset((pPenultimate.point.dx + pLast.point.dx) / 2, (pPenultimate.point.dy + pLast.point.dy) / 2);
    
    paint.strokeWidth = prevWidth;
    canvas.drawLine(start, pLast.point, paint);
  }

  @override
  bool shouldRepaint(covariant StrokePainter oldDelegate) => true;
}