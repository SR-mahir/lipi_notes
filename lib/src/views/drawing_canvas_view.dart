import 'package:flutter/material.dart';
import '../controllers/canvas_controller.dart';
import '../models/stroke_model.dart';
import 'stroke_painter.dart';

class DrawingCanvasView extends StatefulWidget {
  const DrawingCanvasView({super.key});

  @override
  State<DrawingCanvasView> createState() => _DrawingCanvasViewState();
}

class _DrawingCanvasViewState extends State<DrawingCanvasView> {
  late final CanvasController _controller;
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _canvasKey = GlobalKey(); 
  
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = CanvasController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Offset _getAbsoluteCanvasOffset(Offset globalPosition) {
    final RenderBox? renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return globalPosition;
    return renderBox.globalToLocal(globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Stack(
          children: [
            // Layer 1: The Workspace Canvas Viewport Engine
            Listener(
              onPointerDown: (event) {
                setState(() => _pointerCount++);
                if (_pointerCount == 1) {
                  final canvasOffset = _getAbsoluteCanvasOffset(event.position);
                  _controller.handlePointerDown(
                    event, 
                    canvasOffset,
                    _transformationController.value,
                  );
                }
              },
              onPointerMove: (event) {
                if (_pointerCount == 1) {
                  final canvasOffset = _getAbsoluteCanvasOffset(event.position);
                  _controller.handlePointerMove(
                    event, 
                    canvasOffset,
                    _transformationController.value,
                  );
                }
              },
              onPointerUp: (event) {
                setState(() => _pointerCount = (_pointerCount - 1).clamp(0, 10));
                if (_pointerCount == 0) {
                  _controller.handlePointerUp(event);
                }
              },
              onPointerCancel: (event) {
                setState(() => _pointerCount = 0);
                _controller.handlePointerUp(event);
              },
              child: Container(
                color: const Color(0xFFEAEAEA), 
                width: double.infinity,
                height: double.infinity,
                child: Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.5,
                    maxScale: 4.0,
                    panEnabled: _pointerCount >= 2,
                    scaleEnabled: _pointerCount >= 2,
                    boundaryMargin: const EdgeInsets.all(500),
                    child: Padding(
                      padding: const EdgeInsets.all(32.0), 
                      child: Center(
                        child: Container(
                          key: _canvasKey, 
                          width: screenSize.width * 0.95, 
                          height: screenSize.height * 0.90,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ClipRect(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: StrokePainter(
                                  history: _controller.history,
                                  currentStroke: _controller.currentStroke,
                                ),
                                child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
            
            // Layer 2: Floating Tool Selection Controls Dock Matrix
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        color: _controller.activeTool == CanvasTool.pen ? Colors.green : Colors.grey,
                        onPressed: () => _controller.setTool(CanvasTool.pen),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.cleaning_services_rounded),
                        color: _controller.activeTool == CanvasTool.eraser ? Colors.green : Colors.grey,
                        onPressed: () => _controller.setTool(CanvasTool.eraser),
                      ),
                      const SizedBox(width: 12),
                      Container(width: 1, height: 24, color: Colors.grey.shade300),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        color: Colors.redAccent,
                        onPressed: () => _controller.clearCanvas(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}