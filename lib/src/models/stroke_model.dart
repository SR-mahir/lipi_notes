import 'dart:ui';
enum CanvasTool { pen, objectEraser, segmentEraser, lasso, text }
enum PenType { fountain, ballpoint, highlighter, brush }
enum CanvasTemplate { blank, ruled, grid, dotted }

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
  int? pageId;
  final List<StrokePoint> points;
  final Color color;
  final double strokeWidth;
  final PenType penType;
  late final Rect boundingBox;

  DrawingStroke({
    this.id,
    this.pageId,
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.penType = PenType.fountain,
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