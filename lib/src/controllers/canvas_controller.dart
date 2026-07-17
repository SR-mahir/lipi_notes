import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/stroke_model.dart';
import '../models/db_helper.dart';

class CanvasController extends ChangeNotifier {
  final List<DrawingStroke> _history = [];
  List<StrokePoint> _currentPoints = [];
  CanvasTool _activeTool = CanvasTool.pen;
  
  // Auto-save queue and timer for non-blocking database writes
  final List<DrawingStroke> _unsavedStrokes = [];
  final List<int> _pendingDeletions = [];
  Timer? _autoSaveTimer;

  List<DrawingStroke> get history => _history;
  CanvasTool get activeTool => _activeTool;

  DrawingStroke? get currentStroke => _currentPoints.isNotEmpty
      ? DrawingStroke(
          points: _currentPoints,
          color: Colors.black,
          strokeWidth: 4.0,
        )
      : null;

  CanvasController() {
    // Automatically query local storage on boot
    loadStrokesFromDB();
    // Start periodic background auto-saver
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
    _activeTool = tool;
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
          _history.add(
            DrawingStroke(
              id: row['id'] as int?,
              points: pointsList,
              color: Color(row['color'] as int),
              strokeWidth: row['stroke_width'] as double,
            ),
          );
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to load strokes from database: $e");
    }
  }

  // Periodic autosave run on background isolates using compute
  Future<void> _performPeriodicSave() async {
    // Process pending deletions first to prevent locking
    if (_pendingDeletions.isNotEmpty) {
      final deletions = List<int>.from(_pendingDeletions);
      _pendingDeletions.clear();
      for (var id in deletions) {
        try {
          await DBHelper.deleteStroke(id);
        } catch (e) {
          debugPrint("Failed to delete stroke $id from DB: $e");
          _pendingDeletions.add(id); // Retry next time
        }
      }
    }

    if (_unsavedStrokes.isEmpty) return;

    final strokesToSave = List<DrawingStroke>.from(_unsavedStrokes);
    _unsavedStrokes.clear();

    for (var stroke in strokesToSave) {
      // If the stroke was deleted while waiting in the queue, do not save it
      if (!_history.contains(stroke)) continue;

      final pointsData = stroke.points.map((p) => p.point).toList();
      
      try {
        // Offload the coordinates string generation to background isolate
        final String serializedPath = await compute(serializePointsStatic, pointsData);
        
        // Save to local SQLite database
        final id = await DBHelper.insertStroke(serializedPath, stroke.color.toARGB32(), stroke.strokeWidth);
        stroke.id = id;
      } catch (e) {
        debugPrint("Failed to save stroke to DB: $e");
        _unsavedStrokes.add(stroke); // Retry next time
      }
    }
  }

  // Sync flush on dispose
  void _flushUnsavedStrokesSync() {
    // Sync deletions
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
        DBHelper.insertStroke(serializedPath, stroke.color.toARGB32(), stroke.strokeWidth);
      } catch (_) {}
    }
    _unsavedStrokes.clear();
  }

  // Parses database text entries back into live UI rendering coordinates
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

  void handlePointerDown(PointerEvent event, Offset canvasOffset, Matrix4 transformMatrix) {
    if (_activeTool == CanvasTool.eraser) {
      _eraseStrokesAt(canvasOffset);
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
    if (_activeTool == CanvasTool.eraser) {
      _eraseStrokesAt(canvasOffset);
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
    if (_activeTool == CanvasTool.eraser) return;
    finalizeCurrentStroke();
  }

  void finalizeCurrentStroke() {
    if (_currentPoints.isNotEmpty) {
      final newStroke = DrawingStroke(
        points: List.from(_currentPoints),
        color: Colors.black,
        strokeWidth: 4.0,
      );

      _history.add(newStroke);
      _unsavedStrokes.add(newStroke);
      _currentPoints.clear();
      notifyListeners();
    }
  }

  void _eraseStrokesAt(Offset touchPoint) {
    const double eraserRadius = 20.0;
    bool historyChanged = false;
    
    for (int i = _history.length - 1; i >= 0; i--) {
      final stroke = _history[i];
      // AABB check: skip distant strokes
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

  void clearCanvas() async {
    _history.clear();
    _currentPoints.clear();
    _unsavedStrokes.clear();
    notifyListeners();
    // Wipe local hardware database clean
    await DBHelper.clearAllStrokes();
  }
}