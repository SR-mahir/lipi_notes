import 'package:flutter/material.dart';
import '../models/stroke_model.dart';

class CanvasController extends ChangeNotifier {
  // Application State
  final List<DrawingStroke> _history = [];
  List<StrokePoint> _currentPoints = [];

  // Getters for the View layer
  List<DrawingStroke> get history => _history;
  
  DrawingStroke? get currentStroke => _currentPoints.isNotEmpty
      ? DrawingStroke(
          points: _currentPoints,
          color: Colors.black,
          strokeWidth: 4.0,
        )
      : null;

  // Controller Handlers
  void handlePointerDown(PointerDownEvent event) {
    _currentPoints = [
      StrokePoint(
        point: event.localPosition,
        pressure: event.pressure,
        timestamp: DateTime.now(),
      )
    ];
    notifyListeners();
  }

  void handlePointerMove(PointerMoveEvent event) {
    _currentPoints.add(
      StrokePoint(
        point: event.localPosition,
        pressure: event.pressure,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void handlePointerUp(PointerUpEvent event) {
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