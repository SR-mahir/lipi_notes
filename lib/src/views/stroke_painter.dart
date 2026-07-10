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
  if (stroke.points.length < 3) {
    // If there are only 1 or 2 points, a straight line is fine
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    
    if (stroke.points.length == 1) {
      canvas.drawCircle(stroke.points.first.point, stroke.strokeWidth / 2, paint..style = PaintingStyle.fill);
    } else {
      canvas.drawLine(stroke.points.first.point, stroke.points.last.point, paint);
    }
    return;
  }

  final paint = Paint()
    ..color = stroke.color
    ..strokeWidth = stroke.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true; // Ensures the hardware smooths the pixels

  final path = Path();
  
  // Start at the first recorded point
  path.moveTo(stroke.points.first.point.dx, stroke.points.first.point.dy);

  // Loop through midpoints to calculate Bezier control vectors
  for (int i = 1; i < stroke.points.length - 1; i++) {
    final current = stroke.points[i].point;
    final next = stroke.points[i + 1].point;
    
    // Calculate the mathematical midpoint between the current point and the next point
    final midPointX = (current.dx + next.dx) / 2;
    final midPointY = (current.dy + next.dy) / 2;

    // Draw a quadratic curve using the current point as the control anchor
    path.quadraticBezierTo(current.dx, current.dy, midPointX, midPointY);
  }

  // Draw a final line connecting to the absolute last touch event point
  path.lineTo(stroke.points.last.point.dx, stroke.points.last.point.dy);

  canvas.drawPath(path, paint);
}

  @override
  bool shouldRepaint(covariant StrokePainter oldDelegate) {
    return oldDelegate.currentStroke != currentStroke || oldDelegate.history != history;
  }
}