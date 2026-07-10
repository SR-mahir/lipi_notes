import 'package:flutter/material.dart';
import '../controllers/canvas_controller.dart';
import 'stroke_painter.dart';

class DrawingCanvasView extends StatefulWidget {
  const DrawingCanvasView({super.key});

  @override
  State<DrawingCanvasView> createState() => _DrawingCanvasViewState();
}

class _DrawingCanvasViewState extends State<DrawingCanvasView> {
  late final CanvasController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CanvasController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Listener(
          onPointerDown: _controller.handlePointerDown,
          onPointerMove: _controller.handlePointerMove,
          onPointerUp: _controller.handlePointerUp,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: StrokePainter(
                history: _controller.history,
                currentStroke: _controller.currentStroke,
              ),
              child: Container(
                color: Colors.transparent,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        );
      },
    );
  }
}