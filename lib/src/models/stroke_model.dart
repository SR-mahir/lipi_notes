import 'dart:ui';
enum CanvasTool { pen, eraser }

class StrokePoint {
  final Offset point;
  final double pressure;
  final DateTime timestamp;

  StrokePoint({
    required this.point,
    required this.pressure,
    required this.timestamp,
  });
}

class DrawingStroke {
  final List<StrokePoint> points;
  final Color color;
  final double strokeWidth;

  DrawingStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}