import 'package:flutter/material.dart';
import '../models/stroke_model.dart';
import '../models/db_helper.dart';

class CanvasController extends ChangeNotifier {
  final List<DrawingStroke> _history = [];
  List<StrokePoint> _currentPoints = [];
  CanvasTool _activeTool = CanvasTool.pen;

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
    // Automatically query local iPad storage the millisecond the app boots up
    loadStrokesFromDB();
  }

  void setTool(CanvasTool tool) {
    _activeTool = tool;
    notifyListeners();
  }

  // --- COMPRESSION UTILITIES ---
  // Turns coordinates into standard text vectors: "x1,y1 dx2,dy2 dx3,dy3..."
  String _serializePoints(List<StrokePoint> points) {
    return points.map((p) => '${p.point.dx.toStringAsFixed(1)},${p.point.dy.toStringAsFixed(1)}').join(' ');
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

  // --- DATABASE HOOK ACTIONS ---
  Future<void> loadStrokesFromDB() async {
    final savedData = await DBHelper.getSavedStrokes();
    _history.clear();
    
    for (var row in savedData) {
      final pointsList = _deserializePoints(row['path_string'] as String);
      if (pointsList.isNotEmpty) {
        _history.add(
          DrawingStroke(
            points: pointsList,
            color: Color(row['color'] as int),
            strokeWidth: row['stroke_width'] as double,
          ),
        );
      }
    }
    notifyListeners();
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

  void handlePointerUp(PointerEvent event) async {
    if (_activeTool == CanvasTool.eraser) return;

    if (_currentPoints.isNotEmpty) {
      final newStroke = DrawingStroke(
        points: List.from(_currentPoints),
        color: Colors.black,
        strokeWidth: 4.0,
      );

      _history.add(newStroke);
      _currentPoints.clear();
      notifyListeners();

      // PERMANENT LOCAL SAVE TRIGGER
      final String serializedPath = _serializePoints(newStroke.points);
      await DBHelper.insertStroke(serializedPath, Colors.black.value, 4.0);
    }
  }

  void _eraseStrokesAt(Offset touchPoint) {
    // Keep your basic loop logic intact for now
    bool historyChanged = false;
    for (int i = _history.length - 1; i >= 0; i--) {
      for (var strokePoint in _history[i].points) {
        if ((touchPoint - strokePoint.point).distance <= 20.0) {
          _history.removeAt(i);
          historyChanged = true;
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
    notifyListeners();
    // Wipe local hardware database clean
    await DBHelper.clearAllStrokes();
  }
}