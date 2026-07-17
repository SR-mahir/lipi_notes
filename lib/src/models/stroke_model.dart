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
  int? id;
  final List<StrokePoint> points;
  final Color color;
  final double strokeWidth;
  late final Rect boundingBox;

  DrawingStroke({
    this.id,
    required this.points,
    required this.color,
    required this.strokeWidth,
  }) {
    if (points.isEmpty) {
      boundingBox = Rect.zero;
    } else {
      double minX = points.first.point.dx;
      double maxX = points.first.point.dx;
      double minY = points.first.point.dy;
      double maxY = points.first.point.dy;
      for (var p in points) {
        if (p.point.dx < minX) minX = p.point.dx;
        if (p.point.dx > maxX) maxX = p.point.dx;
        if (p.point.dy < minY) minY = p.point.dy;
        if (p.point.dy > maxY) maxY = p.point.dy;
      }
      boundingBox = Rect.fromLTRB(minX, minY, maxX, maxY);
    }
  }
}