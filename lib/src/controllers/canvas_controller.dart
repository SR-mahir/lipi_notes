import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/stroke_model.dart';
import '../models/workspace_models.dart';
import '../models/text_box_model.dart';
import '../models/db_helper.dart';

class CanvasController extends ChangeNotifier {
  final Notebook notebook;
  List<NotebookPage> _pages = [];
  int _currentPageIndex = 0;

  final List<DrawingStroke> _history = [];
  List<StrokePoint> _currentPoints = [];
  CanvasTool _activeTool = CanvasTool.pen;
  PenType _activePenType = PenType.fountain;
  CanvasTemplate _activeTemplate = CanvasTemplate.blank;
  bool _isDarkMode = false;
  List<TextBoxModel> _textBoxes = [];
  List<Map<String, dynamic>> _clipAssets = [];

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

  List<NotebookPage> get pages => _pages;
  int get currentPageIndex => _currentPageIndex;
  NotebookPage? get currentPage => _pages.isNotEmpty ? _pages[_currentPageIndex] : null;
  String? get currentPdfPath => currentPage?.pdfPath;
  int? get currentPdfPageIndex => currentPage?.pdfPageIndex;

  List<DrawingStroke> get history => _history;
  CanvasTool get activeTool => _activeTool;
  PenType get activePenType => _activePenType;
  CanvasTemplate get activeTemplate => _activeTemplate;
  bool get isDarkMode => _isDarkMode;
  List<TextBoxModel> get textBoxes => _textBoxes;
  List<Map<String, dynamic>> get clipAssets => _clipAssets;
  List<Offset> get lassoPath => _lassoPath;
  List<DrawingStroke> get selectedStrokes => _selectedStrokes;
  Rect? get selectionBounds => _selectionBounds;

  DrawingStroke? get currentStroke => _currentPoints.isNotEmpty && _pages.isNotEmpty
      ? DrawingStroke(
          points: _currentPoints,
          color: Colors.black,
          strokeWidth: 4.0,
          penType: _activePenType,
          pageId: _pages[_currentPageIndex].id,
        )
      : null;

  CanvasController({required this.notebook}) {
    _loadPagesAndStrokes();
    _startAutoSaveTimer();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _flushUnsavedStrokesSync();
    super.dispose();
  }

  Future<void> _loadPagesAndStrokes() async {
    try {
      final pageData = await DBHelper.getPagesForNotebook(notebook.id!);
      _pages = pageData.map((map) => NotebookPage.fromMap(map)).toList();

      if (_pages.isEmpty) {
        final id = await DBHelper.insertPage(notebook.id!, 0, 'blank');
        _pages = [NotebookPage(id: id, notebookId: notebook.id!, pageIndex: 0, backgroundType: 'blank')];
      }

      _currentPageIndex = 0;
      _activeTemplate = _parseBackgroundType(_pages[_currentPageIndex].backgroundType);
      await loadStrokesFromDB();
    } catch (e) {
      debugPrint("Failed to load pages and strokes: $e");
    }
  }

  CanvasTemplate _parseBackgroundType(String type) {
    return CanvasTemplate.values.firstWhere((e) => e.name == type, orElse: () => CanvasTemplate.blank);
  }

  void setTool(CanvasTool tool) {
    finalizeCurrentStroke();
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

  Future<void> setTemplate(CanvasTemplate template) async {
    _activeTemplate = template;
    notifyListeners();
    if (_pages.isNotEmpty) {
      final pageId = _pages[_currentPageIndex].id!;
      await DBHelper.updatePageBackground(pageId, template.name);

      final oldPage = _pages[_currentPageIndex];
      _pages[_currentPageIndex] = NotebookPage(
        id: oldPage.id,
        notebookId: oldPage.notebookId,
        pageIndex: oldPage.pageIndex,
        backgroundType: template.name,
      );
    }
  }

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
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
    if (_pages.isEmpty) return;
    try {
      final pageId = _pages[_currentPageIndex].id!;
      final savedData = await DBHelper.getSavedStrokesForPage(pageId);
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
              pageId: row['page_id'] as int?,
              points: pointsList,
              color: Color(row['color'] as int),
              strokeWidth: row['stroke_width'] as double,
              penType: penType,
            ),
          );
        }
      }
      notifyListeners();
      await loadTextBoxesFromDB();
      await loadClipsFromDB();
    } catch (e) {
      debugPrint("Failed to load strokes from database: $e");
    }
  }

  Future<void> loadTextBoxesFromDB() async {
    if (_pages.isEmpty) return;
    try {
      final pageId = _pages[_currentPageIndex].id!;
      final savedData = await DBHelper.getTextBoxesForPage(pageId);
      _textBoxes = savedData.map((row) => TextBoxModel.fromMap(row)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to load text boxes from database: $e");
    }
  }

  Future<void> loadClipsFromDB() async {
    try {
      _clipAssets = await DBHelper.getClipAssets();
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to load clip assets: $e");
    }
  }

  Future<void> saveSelectedAsClip(String name) async {
    if (_selectedStrokes.isEmpty) return;

    final pathStrings = <String>[];
    for (var stroke in _selectedStrokes) {
      final ptsStr = serializePointsStatic(stroke.points.map((p) => p.point).toList());
      pathStrings.add(ptsStr);
    }

    final compositePath = pathStrings.join('|');
    final sampleStroke = _selectedStrokes.first;

    final row = {
      'name': name,
      'path_string': compositePath,
      'color': sampleStroke.color.value,
      'stroke_width': sampleStroke.strokeWidth,
      'pen_type': sampleStroke.penType.name,
    };

    try {
      await DBHelper.insertClipAsset(row);
      await loadClipsFromDB();
    } catch (e) {
      debugPrint("Failed to save clip: $e");
    }
  }

  Future<void> stampClip(Map<String, dynamic> clip, Offset targetCenter) async {
    if (_pages.isEmpty) return;
    final pageId = _pages[_currentPageIndex].id!;

    final compositePath = clip['path_string'] as String;
    final pathSegments = compositePath.split('|');

    final allPoints = <Offset>[];
    final strokePointsList = <List<StrokePoint>>[];

    for (var pathStr in pathSegments) {
      final pts = _deserializePoints(pathStr);
      if (pts.isNotEmpty) {
        strokePointsList.add(pts);
        allPoints.addAll(pts.map((p) => p.point));
      }
    }

    if (allPoints.isEmpty) return;

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (var p in allPoints) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    final dx = targetCenter.dx - centerX;
    final dy = targetCenter.dy - centerY;

    final penType = PenType.values.firstWhere(
      (e) => e.name == clip['pen_type'],
      orElse: () => PenType.fountain,
    );
    final color = Color(clip['color'] as int);
    final strokeWidth = clip['stroke_width'] as double;

    for (var pts in strokePointsList) {
      final translatedPoints = pts.map((p) {
        return StrokePoint(
          point: Offset(p.point.dx + dx, p.point.dy + dy),
          pressure: p.pressure,
          timestamp: DateTime.now(),
        );
      }).toList();

      final translatedPathStr = serializePointsStatic(translatedPoints.map((p) => p.point).toList());

      try {
        final strokeId = await DBHelper.insertStroke(
          translatedPathStr,
          color.value,
          strokeWidth,
          penType.name,
          pageId,
        );

        final newStroke = DrawingStroke(
          id: strokeId,
          pageId: pageId,
          points: translatedPoints,
          color: color,
          strokeWidth: strokeWidth,
          penType: penType,
        );

        _history.add(newStroke);
      } catch (e) {
        debugPrint("Failed to insert stamped stroke: $e");
      }
    }

    notifyListeners();
  }

  Future<void> deleteClip(int id) async {
    try {
      await DBHelper.deleteClipAsset(id);
      await loadClipsFromDB();
    } catch (e) {
      debugPrint("Failed to delete clip: $e");
    }
  }

  Future<void> addTextBox(String text, Offset position, double fontSize) async {
    if (_pages.isEmpty) return;
    final pageId = _pages[_currentPageIndex].id!;
    final newBox = TextBoxModel(
      pageId: pageId,
      text: text,
      x: position.dx,
      y: position.dy,
      fontSize: fontSize,
      colorValue: _isDarkMode ? 0xFFFFFFFF : 0xFF000000,
    );
    try {
      final id = await DBHelper.insertTextBox(newBox.toMap());
      _textBoxes.add(newBox.copyWith(id: id));
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to insert text box: $e");
    }
  }

  Future<void> updateTextBox(TextBoxModel updatedBox) async {
    try {
      await DBHelper.updateTextBox(updatedBox.id!, updatedBox.toMap());
      final index = _textBoxes.indexWhere((tb) => tb.id == updatedBox.id);
      if (index != -1) {
        _textBoxes[index] = updatedBox;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Failed to update text box: $e");
    }
  }

  void moveTextBox(TextBoxModel textBox, Offset delta) {
    final updatedBox = textBox.copyWith(
      x: textBox.x + delta.dx,
      y: textBox.y + delta.dy,
    );
    final index = _textBoxes.indexWhere((tb) => tb.id == textBox.id);
    if (index != -1) {
      _textBoxes[index] = updatedBox;
      notifyListeners();
    }
    DBHelper.updateTextBox(updatedBox.id!, updatedBox.toMap());
  }

  Future<void> deleteTextBox(int id) async {
    try {
      await DBHelper.deleteTextBox(id);
      _textBoxes.removeWhere((tb) => tb.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to delete text box: $e");
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
          stroke.pageId!,
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
          stroke.pageId!,
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

  // --- PAGINATION ACTIONS ---
  Future<void> nextPage() async {
    if (_currentPageIndex < _pages.length - 1) {
      finalizeCurrentStroke();
      await _performPeriodicSave();

      _currentPageIndex++;
      _activeTemplate = _parseBackgroundType(_pages[_currentPageIndex].backgroundType);
      await loadStrokesFromDB();
    }
  }

  Future<void> prevPage() async {
    if (_currentPageIndex > 0) {
      finalizeCurrentStroke();
      await _performPeriodicSave();

      _currentPageIndex--;
      _activeTemplate = _parseBackgroundType(_pages[_currentPageIndex].backgroundType);
      await loadStrokesFromDB();
    }
  }

  Future<void> addPage() async {
    finalizeCurrentStroke();
    await _performPeriodicSave();

    final newIndex = _pages.length;
    final pageId = await DBHelper.insertPage(notebook.id!, newIndex, 'blank');
    final newPage = NotebookPage(
      id: pageId,
      notebookId: notebook.id!,
      pageIndex: newIndex,
      backgroundType: 'blank',
    );

    _pages.add(newPage);
    _currentPageIndex = newIndex;
    _activeTemplate = CanvasTemplate.blank;
    _history.clear();
    notifyListeners();
  }

  Future<void> deleteCurrentPage() async {
    if (_pages.length <= 1) return; // Keep at least one page

    finalizeCurrentStroke();
    
    final pageId = _pages[_currentPageIndex].id!;
    _unsavedStrokes.removeWhere((s) => s.pageId == pageId);

    await DBHelper.deletePage(pageId);
    _pages.removeAt(_currentPageIndex);

    // Adjust the indices of all later pages
    for (int i = _currentPageIndex; i < _pages.length; i++) {
      final oldPage = _pages[i];
      await DBHelper.updatePageIndex(oldPage.id!, i);
      _pages[i] = NotebookPage(
        id: oldPage.id,
        notebookId: oldPage.notebookId,
        pageIndex: i,
        backgroundType: oldPage.backgroundType,
      );
    }

    if (_currentPageIndex >= _pages.length) {
      _currentPageIndex = _pages.length - 1;
    }

    _activeTemplate = _parseBackgroundType(_pages[_currentPageIndex].backgroundType);
    await loadStrokesFromDB();
  }

  // --- TOUCH POINTER HANDLING ACTIONS ---
  void handlePointerDown(PointerEvent event, Offset canvasOffset, Matrix4 transformMatrix) {
    if (_pages.isEmpty) return;

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
    if (_pages.isEmpty) return;

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
    if (_pages.isEmpty) return;

    if (_activeTool == CanvasTool.objectEraser || _activeTool == CanvasTool.segmentEraser) return;
    
    if (_activeTool == CanvasTool.lasso) {
      if (_isDraggingSelection) {
        _isDraggingSelection = false;
        _lastDragPoint = null;
      } else {
        if (_lassoPath.length >= 3) {
          _lassoPath.add(_lassoPath.first);
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
    if (_currentPoints.isNotEmpty && _pages.isNotEmpty) {
      if (_currentPoints.length >= 4) {
        final last = _currentPoints.last;
        final tDiff = last.timestamp.difference(_currentPoints[_currentPoints.length - 4].timestamp).inMilliseconds;
        double dMax = 0;
        for (int i = _currentPoints.length - 4; i < _currentPoints.length; i++) {
          final d = (_currentPoints[i].point - last.point).distance;
          if (d > dMax) dMax = d;
        }
        
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
        pageId: _pages[_currentPageIndex].id,
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
              pageId: stroke.pageId,
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
        pageId: s.pageId,
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

    if (chord / pathLength > 0.95) {
      return [points.first, points.last];
    }

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

    final pts = points.map((p) => p.point).toList();
    final epsilon = bbox.width * 0.08;
    final simplified = _rdp(pts, epsilon);

    if (simplified.length == 4) {
      final baseTime = points.first.timestamp;
      return [
        StrokePoint(point: simplified[0], pressure: 1.0, timestamp: baseTime),
        StrokePoint(point: simplified[1], pressure: 1.0, timestamp: baseTime.add(const Duration(milliseconds: 100))),
        StrokePoint(point: simplified[2], pressure: 1.0, timestamp: baseTime.add(const Duration(milliseconds: 200))),
        StrokePoint(point: simplified[0], pressure: 1.0, timestamp: baseTime.add(const Duration(milliseconds: 300))),
      ];
    }

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
    _textBoxes.clear();
    notifyListeners();
    if (_pages.isNotEmpty) {
      final pageId = _pages[_currentPageIndex].id!;
      final db = await DBHelper.database;
      await db.delete('strokes', where: 'page_id = ?', whereArgs: [pageId]);
      await db.delete('text_boxes', where: 'page_id = ?', whereArgs: [pageId]);
    }
  }
}