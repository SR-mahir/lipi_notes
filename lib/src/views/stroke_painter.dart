import 'package:flutter/material.dart';
import '../models/stroke_model.dart';

class StrokePainter extends CustomPainter {
  final List<DrawingStroke> history;
  final DrawingStroke? currentStroke;
  final List<Offset> lassoPath;
  final Rect? selectionBounds;

  StrokePainter({
    required this.history,
    this.currentStroke,
    this.lassoPath = const [],
    this.selectionBounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Pass 1: Draw Highlighter strokes underneath other inks
    for (var stroke in history) {
      if (stroke.penType == PenType.highlighter) {
        _drawStroke(canvas, stroke);
      }
    }
    if (currentStroke != null && currentStroke!.penType == PenType.highlighter) {
      _drawStroke(canvas, currentStroke!);
    }

    // Pass 2: Draw all other strokes (Fountain, Ballpoint, Brush)
    for (var stroke in history) {
      if (stroke.penType != PenType.highlighter) {
        _drawStroke(canvas, stroke);
      }
    }
    if (currentStroke != null && currentStroke!.penType != PenType.highlighter) {
      _drawStroke(canvas, currentStroke!);
    }

    // Pass 3: Draw Lasso Loop Overlay
    if (lassoPath.isNotEmpty) {
      final lassoPaint = Paint()
        ..color = Colors.blue.withOpacity(0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      
      final path = Path();
      path.moveTo(lassoPath.first.dx, lassoPath.first.dy);
      for (int i = 1; i < lassoPath.length; i++) {
        path.lineTo(lassoPath[i].dx, lassoPath[i].dy);
      }
      canvas.drawPath(path, lassoPaint);
    }

    // Pass 4: Draw Transform Selection Box
    if (selectionBounds != null) {
      final boxPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      
      canvas.drawRect(selectionBounds!, boxPaint);

      // Draw active corner scale/rotate handles
      final handlePaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.fill;
      final handleBorderPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final corners = [
        selectionBounds!.topLeft,
        selectionBounds!.topRight,
        selectionBounds!.bottomLeft,
        selectionBounds!.bottomRight,
      ];

      for (var corner in corners) {
        canvas.drawCircle(corner, 6.0, handlePaint);
        canvas.drawCircle(corner, 6.0, handleBorderPaint);
      }
    }
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;
    
    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = stroke.penType == PenType.highlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = stroke.penType == PenType.highlighter ? StrokeJoin.miter : StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (stroke.penType == PenType.highlighter) {
      paint.color = stroke.color.withOpacity(0.35);
      paint.strokeWidth = stroke.strokeWidth * 3.5;
    } else if (stroke.penType == PenType.brush) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, stroke.strokeWidth * 0.18);
    }

    if (stroke.points.length < 3) {
      if (stroke.points.length == 1) {
        final p = stroke.points.first;
        final w = _getPointWidth(stroke, p, stroke.strokeWidth);
        canvas.drawCircle(p.point, w / 2, paint..style = PaintingStyle.fill);
      } else {
        final p0 = stroke.points[0];
        final p1 = stroke.points[1];
        final w0 = _getPointWidth(stroke, p0, stroke.strokeWidth);
        final w1 = _getPointWidth(stroke, p1, stroke.strokeWidth);
        paint.strokeWidth = (w0 + w1) / 2;
        canvas.drawLine(p0.point, p1.point, paint);
      }
      return;
    }

    double prevWidth = _getPointWidth(stroke, stroke.points.first, stroke.strokeWidth);

    for (int i = 1; i < stroke.points.length - 1; i++) {
      final pPrev = stroke.points[i - 1];
      final pCurr = stroke.points[i];
      final pNext = stroke.points[i + 1];

      double currentWidth;
      if (stroke.penType == PenType.ballpoint || stroke.penType == PenType.highlighter) {
        currentWidth = stroke.penType == PenType.highlighter ? stroke.strokeWidth * 3.5 : stroke.strokeWidth;
      } else {
        final distance = (pCurr.point - pPrev.point).distance;
        final timeDiff = pCurr.timestamp.difference(pPrev.timestamp).inMicroseconds / 1000000.0;
        final velocity = timeDiff > 0 ? (distance / timeDiff) : 0.0;

        final pressureFactor = stroke.penType == PenType.brush 
            ? (0.3 + 1.2 * pCurr.pressure) 
            : (0.5 + 0.8 * pCurr.pressure);

        final velocityFactor = stroke.penType == PenType.brush
            ? 1.0 
            : 1.0 - (velocity / 2000.0).clamp(0.0, 0.5);

        final rawWidth = stroke.strokeWidth * pressureFactor * velocityFactor;
        currentWidth = prevWidth + (rawWidth - prevWidth) * 0.3;
      }
      
      prevWidth = currentWidth;
      paint.strokeWidth = currentWidth;

      final start = i == 1 
          ? pPrev.point 
          : Offset((pPrev.point.dx + pCurr.point.dx) / 2, (pPrev.point.dy + pCurr.point.dy) / 2);
      final end = Offset((pCurr.point.dx + pNext.point.dx) / 2, (pCurr.point.dy + pNext.point.dy) / 2);

      final path = Path();
      path.moveTo(start.dx, start.dy);
      path.quadraticBezierTo(pCurr.point.dx, pCurr.point.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }

    final lastIdx = stroke.points.length - 1;
    final pPenultimate = stroke.points[lastIdx - 1];
    final pLast = stroke.points[lastIdx];
    final start = Offset((pPenultimate.point.dx + pLast.point.dx) / 2, (pPenultimate.point.dy + pLast.point.dy) / 2);
    
    paint.strokeWidth = prevWidth;
    canvas.drawLine(start, pLast.point, paint);
  }

  double _getPointWidth(DrawingStroke stroke, StrokePoint p, double baseWidth) {
    if (stroke.penType == PenType.ballpoint) {
      return baseWidth;
    } else if (stroke.penType == PenType.highlighter) {
      return baseWidth * 3.5;
    } else if (stroke.penType == PenType.brush) {
      return baseWidth * (0.3 + 1.2 * p.pressure);
    } else {
      return baseWidth * (0.5 + 0.8 * p.pressure);
    }
  }

  @override
  bool shouldRepaint(covariant StrokePainter oldDelegate) => true;
}