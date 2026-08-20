import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/stroke_model.dart';
import '../models/db_helper.dart';

class CanvasController extends ChangeNotifier {
  final List<DrawingStroke> _history = [];
  List<StrokePoint> _currentPoints = [];
  CanvasTool _activeTool = CanvasTool.pen;
  PenType _activePenType = PenType.fountain;

  // Lasso and selection properties
  final List<Offset> _lassoPath = [];
  final List<DrawingStroke> _selectedStrokes = [];
  Rect? _selectionBounds;
  bool _isDraggingSelection = false;
  Offset? _lastDragPoint;
  
  // Auto-save queue and timer for non-blocking database writes
  final List<DrawingStroke> _unsavedStrokes = [];
  final List<int> _pendingDeletions = [];
  Timer? _autoSaveTimer;

  List<DrawingStroke> get history => _history;
  CanvasTool get activeTool => _activeTool;
  PenType get activePenType => _activePenType;
  List<Offset> get lassoPath => _lassoPath;
  List<DrawingStroke> get selectedStrokes => _selectedStrokes;
  Rect? get selectionBounds => _selectionBounds;

  DrawingStroke? get currentStroke => _currentPoints.isNotEmpty
      ? DrawingStroke(
          points: _currentPoints,
          color: Colors.black,
          strokeWidth: 4.0,
          penType: _activePenType,
        )
      : null;

  CanvasController() {
    loadStrokesFromDB();
    _startAutoSaveTimer();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _flushUnsavedStrokesSync();
    super.dispose();
  }

  void setTool(CanvasTool tool) {
    finalizeCurrentStroke();
    
    // Clear selection if switching away from lasso
    if (_activeTool == CanvasTool.lasso && tool != CanvasTool.lasso) {
      _selectedStrokes.clear();
      _selectionBounds = null;
    }
    
    _activeTool = tool;
    notifyListeners();
  }

  void setPenType(PenType type) {
    finalizeCurrentStroke();
    _activePenType = type;
    notifyListeners();
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _performPeriodicSave();
    });
  }

  // --- SERIALIZATION TASK RUN ON BACKGROUND ISOLATE ---
  static String serializePointsStatic(List<Offset> points) {
    return points.map((p) => '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}').join(' ');
  }

  // --- DATABASE HOOK ACTIONS ---
  Future<void> loadStrokesFromDB() async {
    try {
      final savedData = await DBHelper.getSavedStrokes();
      _history.clear();
      
      for (var row in savedData) {
        final pointsList = _deserializePoints(row['path_string'] as String);
        if (pointsList.isNotEmpty) {
          final penTypeString = row['pen_type'] as String? ?? 'fountain';
          final penType = PenType.values.firstWhere(
            (e) => e.name == penTypeString,
            orElse: () => PenType.fountain,
          );

          _history.add(
            DrawingStroke(
              id: row['id'] as int?,
              points: pointsList,
              color: Color(row['color'] as int),
              strokeWidth: row['stroke_width'] as double,
              penType: penType,
            ),
          );
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to load strokes from database: $e");
    }
  }

  Future<void> _performPeriodicSave() async {
    if (_pendingDeletions.isNotEmpty) {
      final deletions = List<int>.from(_pendingDeletions);
      _pendingDeletions.clear();
      for (var id in deletions) {
        try {
          await DBHelper.deleteStroke(id);
        } catch (e) {
          debugPrint("Failed to delete stroke $id from DB: $e");
          _pendingDeletions.add(id);
        }
      }
    }

    if (_unsavedStrokes.isEmpty) return;

    final strokesToSave = List<DrawingStroke>.from(_unsavedStrokes);
    _unsavedStrokes.clear();

    for (var stroke in strokesToSave) {
      if (!_history.contains(stroke)) continue;

      final pointsData = stroke.points.map((p) => p.point).toList();
      
      try {
        final String serializedPath = await compute(serializePointsStatic, pointsData);
        final id = await DBHelper.insertStroke(
          serializedPath, 
          stroke.color.toARGB32(), 
          stroke.strokeWidth,
          stroke.penType.name,
        );
        stroke.id = id;
      } catch (e) {
        debugPrint("Failed to save stroke to DB: $e");
        _unsavedStrokes.add(stroke);
      }
    }
  }

  void _flushUnsavedStrokesSync() {
    if (_pendingDeletions.isNotEmpty) {
      for (var id in _pendingDeletions) {
        try {
          DBHelper.deleteStroke(id);
        } catch (_) {}
      }
      _pendingDeletions.clear();
    }

    if (_unsavedStrokes.isEmpty) return;
    for (var stroke in _unsavedStrokes) {
      if (!_history.contains(stroke)) continue;
      final pointsData = stroke.points.map((p) => p.point).toList();
      final String serializedPath = serializePointsStatic(pointsData);
      try {
        DBHelper.insertStroke(
          serializedPath, 
          stroke.color.toARGB32(), 
          stroke.strokeWidth,
          stroke.penType.name,
        );
      } catch (_) {}
    }
    _unsavedStrokes.clear();
  }

  List<StrokePoint> _deserializePoints(String dataString) {
    if (dataString.isEmpty) return [];
    return dataString.split(' ').map((pair) {
      final coordinates = pair.split(',');
      final dx = double.tryParse(coordinates[0]) ?? 0.0;
      final dy = double.tryParse(coordinates[1]) ?? 0.0;
      return StrokePoint(
        point: Offset(dx, dy),
        pressure: 1.0,
        timestamp: DateTime.now(),
      );
    }).toList();
  }

  // --- TOUCH POINTER HANDLING ACTIONS ---
  void handlePointerDown(PointerEvent event, Offset canvasOffset, Matrix4 transformMatrix) {
    if (_activeTool == CanvasTool.objectEraser) {
      _eraseStrokesAt(canvasOffset);
      return;
    } else if (_activeTool == CanvasTool.segmentEraser) {
      _eraseSegmentAt(canvasOffset);
      return;
    } else if (_activeTool == CanvasTool.lasso) {
      if (_selectionBounds != null && _selectionBounds!.contains(canvasOffset)) {
        _isDraggingSelection = true;
        _lastDragPoint = canvasOffset;
      } else {
        _selectedStrokes.clear();
        _selectionBounds = null;
        _lassoPath.clear();
        _lassoPath.add(canvasOffset);
      }
      notifyListeners();
      return;
    }

    double absolutePressure = event.pressure > 0 ? event.pressure : 1.0;
    _currentPoints = [
      StrokePoint(
        point: canvasOffset,
        pressure: absolutePressure,
        timestamp: DateTime.now(),
      )
    ];
    notifyListeners();
  }

  void handlePointerMove(PointerEvent event, Offset canvasOffset, Matrix4 transformMatrix) {
    if (_activeTool == CanvasTool.objectEraser) {
      _eraseStrokesAt(canvasOffset);
      return;
    } else if (_activeTool == CanvasTool.segmentEraser) {
      _eraseSegmentAt(canvasOffset);
      return;
    } else if (_activeTool == CanvasTool.lasso) {
      if (_isDraggingSelection && _lastDragPoint != null) {
        final delta = canvasOffset - _lastDragPoint!;
        _lastDragPoint = canvasOffset;
        _translateSelectedStrokes(delta);
      } else {
        _lassoPath.add(canvasOffset);
        notifyListeners();
      }
      return;
    }

    double absolutePressure = event.pressure > 0 ? event.pressure : 1.0;
    _currentPoints.add(
      StrokePoint(
        point: canvasOffset,
        pressure: absolutePressure,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void handlePointerUp(PointerEvent event) {
    if (_activeTool == CanvasTool.objectEraser || _activeTool == CanvasTool.segmentEraser) return;
    
    if (_activeTool == CanvasTool.lasso) {
      if (_isDraggingSelection) {
        _isDraggingSelection = false;
        _lastDragPoint = null;
      } else {
        if (_lassoPath.length >= 3) {
          _lassoPath.add(_lassoPath.first); // Close loop
          _performLassoSelection();
        }
        _lassoPath.clear();
      }
      notifyListeners();
      return;
    }
    
    finalizeCurrentStroke();
  }

  void finalizeCurrentStroke() {
    if (_currentPoints.isNotEmpty) {
      // Check if user paused at the end of the stroke (Shape Snapping gesture)
      if (_currentPoints.length >= 4) {
        final last = _currentPoints.last;
        final tDiff = last.timestamp.difference(_currentPoints[_currentPoints.length - 4].timestamp).inMilliseconds;
        double dMax = 0;
        for (int i = _currentPoints.length - 4; i < _currentPoints.length; i++) {
          final d = (_currentPoints[i].point - last.point).distance;
          if (d > dMax) dMax = d;
        }
        
        // If final movement stopped for ~400ms within a 12px area, execute snapping
        if (tDiff >= 400 && dMax <= 12.0) {
          final snappedPoints = _recognizeShape(_currentPoints);
          if (snappedPoints != null) {
            _currentPoints = snappedPoints;
          }
        }
      }

      final newStroke = DrawingStroke(
        points: List.from(_currentPoints),
        color: Colors.black,
        strokeWidth: 4.0,
        penType: _activePenType,
      );

      _history.add(newStroke);
      _unsavedStrokes.add(newStroke);
      _currentPoints.clear();
      notifyListeners();
    }
  }

  // --- ERASER & EDITING UTILS ---
  void _eraseStrokesAt(Offset touchPoint) {
    const double eraserRadius = 20.0;
    bool historyChanged = false;
    
    for (int i = _history.length - 1; i >= 0; i--) {
      final stroke = _history[i];
      if (!stroke.boundingBox.inflate(eraserRadius).contains(touchPoint)) {
        continue;
      }

      for (var strokePoint in stroke.points) {
        if ((touchPoint - strokePoint.point).distance <= eraserRadius) {
          final removed = _history.removeAt(i);
          historyChanged = true;
          
          if (removed.id != null) {
            _pendingDeletions.add(removed.id!);
          } else {
            _unsavedStrokes.remove(removed);
          }
          break;
        }
      }
    }
    if (historyChanged) {
      notifyListeners();
    }
  }

  void _eraseSegmentAt(Offset touchPoint) {
    const double eraserRadius = 15.0;
    bool historyChanged = false;
    
    for (int i = _history.length - 1; i >= 0; i--) {
      final stroke = _history[i];
      if (!stroke.boundingBox.inflate(eraserRadius).contains(touchPoint)) {
        continue;
      }

      final List<List<StrokePoint>> splitStrokes = [];
      List<StrokePoint> currentGroup = [];

      for (var pt in stroke.points) {
        final dist = (touchPoint - pt.point).distance;
        if (dist > eraserRadius) {
          currentGroup.add(pt);
        } else {
          if (currentGroup.isNotEmpty) {
            splitStrokes.add(List.from(currentGroup));
            currentGroup.clear();
          }
        }
      }
      if (currentGroup.isNotEmpty) {
        splitStrokes.add(currentGroup);
      }

      if (splitStrokes.length != 1 || splitStrokes.first.length != stroke.points.length) {
        final removed = _history.removeAt(i);
        historyChanged = true;
        
        if (removed.id != null) {
          _pendingDeletions.add(removed.id!);
        } else {
          _unsavedStrokes.remove(removed);
        }

        for (var list in splitStrokes) {
          if (list.length >= 1) {
            final newSub = DrawingStroke(
              points: list,
              color: stroke.color,
              strokeWidth: stroke.strokeWidth,
              penType: stroke.penType,
            );
            _history.insert(i, newSub);
            _unsavedStrokes.add(newSub);
          }
        }
      }
    }

    if (historyChanged) {
      notifyListeners();
    }
  }

  // --- LASSO SELECTION MATHEMATICS ---
  void _performLassoSelection() {
    _selectedStrokes.clear();
    
    for (var stroke in _history) {
      int pointsInside = 0;
      for (var pt in stroke.points) {
        if (_isPointInPolygon(pt.point, _lassoPath)) {
          pointsInside++;
        }
      }
      
      // If majority of the stroke coordinates are lassoed, select it
      if (pointsInside > stroke.points.length * 0.5) {
        _selectedStrokes.add(stroke);
      }
    }

    _recalculateSelectionBounds();
  }

  void _recalculateSelectionBounds() {
    if (_selectedStrokes.isEmpty) {
      _selectionBounds = null;
      return;
    }

    double minX = _selectedStrokes.first.boundingBox.left;
    double maxX = _selectedStrokes.first.boundingBox.right;
    double minY = _selectedStrokes.first.boundingBox.top;
    double maxY = _selectedStrokes.first.boundingBox.bottom;

    for (var s in _selectedStrokes) {
      if (s.boundingBox.left < minX) minX = s.boundingBox.left;
      if (s.boundingBox.right > maxX) maxX = s.boundingBox.right;
      if (s.boundingBox.top < minY) minY = s.boundingBox.top;
      if (s.boundingBox.bottom > maxY) maxY = s.boundingBox.bottom;
    }

    _selectionBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _translateSelectedStrokes(Offset delta) {
    final List<DrawingStroke> updatedStrokes = [];
    
    for (var s in _selectedStrokes) {
      final shiftedPoints = s.points.map((sp) => StrokePoint(
        point: sp.point + delta,
        pressure: sp.pressure,
        timestamp: sp.timestamp,
      )).toList();

      final updated = DrawingStroke(
        points: shiftedPoints,
        color: s.color,
        strokeWidth: s.strokeWidth,
        penType: s.penType,
      );

      if (s.id != null) {
        _pendingDeletions.add(s.id!);
      } else {
        _unsavedStrokes.remove(s);
      }

      final index = _history.indexOf(s);
      if (index != -1) {
        _history[index] = updated;
      }
      _unsavedStrokes.add(updated);
      updatedStrokes.add(updated);
    }

    _selectedStrokes.clear();
    _selectedStrokes.addAll(updatedStrokes);
    _recalculateSelectionBounds();
  }

  bool _isPointInPolygon(Offset p, List<Offset> poly) {
    if (poly.length < 3) return false;
    bool inside = false;
    int j = poly.length - 1;
    for (int i = 0; i < poly.length; i++) {
      if ((poly[i].dy > p.dy) != (poly[j].dy > p.dy) &&
          (p.dx < (poly[j].dx - poly[i].dx) * (p.dy - poly[i].dy) / (poly[j].dy - poly[i].dy) + poly[i].dx)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  // --- SHAPE RECOGNIZER ALGORITHMS ---
  List<StrokePoint>? _recognizeShape(List<StrokePoint> points) {
    if (points.length < 5) return null;

    double pathLength = 0;
    for (int i = 0; i < points.length - 1; i++) {
      pathLength += (points[i + 1].point - points[i].point).distance;
    }

    final first = points.first.point;
    final last = points.last.point;
    final chord = (last - first).distance;

    // Line Test
    if (chord / pathLength > 0.95) {
      return [points.first, points.last];
    }

    // Centroid and bounding box
    double sumX = 0, sumY = 0;
    for (var p in points) {
      sumX += p.point.dx;
      sumY += p.point.dy;
    }
    final centroid = Offset(sumX / points.length, sumY / points.length);

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
    final bbox = Rect.fromLTRB(minX, minY, maxX, maxY);

    // Circle Test
    double sumRadius = 0;
    for (var p in points) {
      sumRadius += (p.point - centroid).distance;
    }
    final avgRadius = sumRadius / points.length;

    double variance = 0;
    for (var p in points) {
      final diff = (p.point - centroid).distance - avgRadius;
      variance += diff * diff;
    }
    final stdDev = math.sqrt(variance / points.length);
    final isClosed = (last - first).distance < bbox.width * 0.45;

    if (stdDev / avgRadius < 0.12 && isClosed) {
      final snapped = <StrokePoint>[];
      const segments = 36;
      final baseTime = points.first.timestamp;
      for (int i = 0; i <= segments; i++) {
        final angle = (2 * math.pi * i) / segments;
        final pt = centroid + Offset(math.cos(angle) * avgRadius, math.sin(angle) * avgRadius);
        snapped.add(StrokePoint(
          point: pt,
          pressure: 1.0,
          timestamp: baseTime.add(Duration(milliseconds: i * 15)),
        ));
      }
      return snapped;
    }

    // Simplify points via RDP for Polygon tests
    final pts = points.map((p) => p.point).toList();
    final epsilon = bbox.width * 0.08;
    final simplified = _rdp(pts, epsilon);

    // Triangle check (4 vertices closed)
    if (simplified.length == 4) {
      final baseTime = points.first.timestamp;
      return [
        StrokePoint(point: simplified[0], pressure: 1.0, timestamp: baseTime),
        StrokePoint(point: simplified[1], pressure: 1.0, timestamp: baseTime.add(const Duration(milliseconds: 100))),
        StrokePoint(point: simplified[2], pressure: 1.0, timestamp: baseTime.add(const Duration(milliseconds: 200))),
        StrokePoint(point: simplified[0], pressure: 1.0, timestamp: baseTime.add(const Duration(milliseconds: 300))),
      ];
    }

    // Rectangle check (5 vertices closed)
    if (simplified.length == 5) {
      final baseTime = points.first.timestamp;
      final corners = [
        bbox.topLeft,
        bbox.topRight,
        bbox.bottomRight,
        bbox.bottomLeft,
        bbox.topLeft,
      ];
      return List.generate(corners.length, (idx) => StrokePoint(
        point: corners[idx],
        pressure: 1.0,
        timestamp: baseTime.add(Duration(milliseconds: idx * 80)),
      ));
    }

    return null;
  }

  double _perpendicularDistance(Offset p, Offset p1, Offset p2) {
    double num = ((p2.dy - p1.dy) * p.dx - (p2.dx - p1.dx) * p.dy + p2.dx * p1.dy - p2.dy * p1.dx).abs();
    double den = (p2 - p1).distance;
    return den == 0 ? 0.0 : (num / den);
  }

  List<Offset> _rdp(List<Offset> pts, double epsilon) {
    if (pts.length < 3) return pts;
    double maxDist = 0.0;
    int index = 0;
    int end = pts.length - 1;
    for (int i = 1; i < end; i++) {
      double dist = _perpendicularDistance(pts[i], pts[0], pts[end]);
      if (dist > maxDist) {
        maxDist = dist;
        index = i;
      }
    }
    if (maxDist > epsilon) {
      List<Offset> recResults1 = _rdp(pts.sublist(0, index + 1), epsilon);
      List<Offset> recResults2 = _rdp(pts.sublist(index, pts.length), epsilon);
      return [...recResults1.sublist(0, recResults1.length - 1), ...recResults2];
    }
    return [pts[0], pts[end]];
  }

  void clearCanvas() async {
    _history.clear();
    _currentPoints.clear();
    _unsavedStrokes.clear();
    _selectedStrokes.clear();
    _selectionBounds = null;
    notifyListeners();
    await DBHelper.clearAllStrokes();
  }
}