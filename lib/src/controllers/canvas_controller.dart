import 'package:flutter/material.dart';
import '../models/stroke_model.dart';

class CanvasController extends ChangeNotifier {
  final List<DrawingStroke> _history = [];
  List<StrokePoint> _currentPoints = [];

  List<DrawingStroke> get history => _history;
  
  DrawingStroke? get currentStroke => _currentPoints.isNotEmpty
      ? DrawingStroke(
          points: _currentPoints,
          color: Colors.black,
          strokeWidth: 4.0,
        )
      : null;

  void handlePointerDown(PointerEvent event, Offset canvasOffset, Matrix4 transformMatrix) {
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
    if (_currentPoints.isNotEmpty) {
      _history.add(
        DrawingStroke(
          points: List.from(_currentPoints),
          color: Colors.black,
          strokeWidth: 4.0,
        ),
      );
      _currentPoints.clear();
      notifyListeners();
    }
  }

  void clearCanvas() {
    _history.clear();
    _currentPoints.clear();
    notifyListeners();
  }
}