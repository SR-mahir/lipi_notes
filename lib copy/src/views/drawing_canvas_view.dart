import 'package:flutter/material.dart';
import '../controllers/canvas_controller.dart';
import '../models/stroke_model.dart';
import '../models/text_box_model.dart';
import 'stroke_painter.dart';

class DrawingCanvasView extends StatefulWidget {
  final CanvasController controller;

  const DrawingCanvasView({super.key, required this.controller});

  @override
  State<DrawingCanvasView> createState() => _DrawingCanvasViewState();
}

class _DrawingCanvasViewState extends State<DrawingCanvasView> {
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _canvasKey = GlobalKey(); 
  
  int _pointerCount = 0;
  bool _showTemplates = false;

  @override
  void dispose() {
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
    final _controller = widget.controller;

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
                  if (_controller.activeTool == CanvasTool.text) {
                    _showAddTextBoxDialog(context, canvasOffset);
                  } else {
                    _controller.handlePointerDown(
                      event, 
                      canvasOffset,
                      _transformationController.value,
                    );
                  }
                } else if (_pointerCount >= 2) {
                  _controller.finalizeCurrentStroke();
                }
              },
              onPointerMove: (event) {
                if (_pointerCount == 1 && _controller.activeTool != CanvasTool.text) {
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
                if (_pointerCount == 0 && _controller.activeTool != CanvasTool.text) {
                  _controller.handlePointerUp(event);
                }
              },
              onPointerCancel: (event) {
                setState(() => _pointerCount = 0);
                if (_controller.activeTool != CanvasTool.text) {
                  _controller.handlePointerUp(event);
                }
              },
              child: Container(
                color: _controller.isDarkMode ? const Color(0xFF121212) : const Color(0xFFEAEAEA), 
                width: double.infinity,
                height: double.infinity,
                child: Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.1,
                    maxScale: 10.0,
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
                            color: _controller.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: _controller.isDarkMode 
                                    ? Colors.white.withValues(alpha: 0.03) 
                                    : Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ClipRect(
                            child: RepaintBoundary(
                              child: Stack(
                                children: [
                                  CustomPaint(
                                    painter: StrokePainter(
                                      history: _controller.history,
                                      currentStroke: _controller.currentStroke,
                                      lassoPath: _controller.lassoPath,
                                      selectionBounds: _controller.selectionBounds,
                                      activeTemplate: _controller.activeTemplate,
                                      isDarkMode: _controller.isDarkMode,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                  ..._controller.textBoxes.map((tb) {
                                    return Positioned(
                                      left: tb.x,
                                      top: tb.y,
                                      child: GestureDetector(
                                        onPanUpdate: (details) {
                                          _controller.moveTextBox(tb, details.delta);
                                        },
                                        onTap: () {
                                          _showEditTextBoxDialog(context, tb);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: _controller.activeTool == CanvasTool.text
                                                  ? Colors.green.withOpacity(0.5)
                                                  : Colors.transparent,
                                              width: 1,
                                            ),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            tb.text,
                                            style: TextStyle(
                                              fontSize: tb.fontSize,
                                              color: Color(tb.colorValue),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
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
                          tooltip: "Pen Tool",
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.cleaning_services_rounded),
                          color: _controller.activeTool == CanvasTool.objectEraser ? Colors.green : Colors.grey,
                          onPressed: () => _controller.setTool(CanvasTool.objectEraser),
                          tooltip: "Object Eraser",
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.auto_fix_normal),
                          color: _controller.activeTool == CanvasTool.segmentEraser ? Colors.green : Colors.grey,
                          onPressed: () => _controller.setTool(CanvasTool.segmentEraser),
                          tooltip: "Segment Eraser",
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.gesture),
                          color: _controller.activeTool == CanvasTool.lasso ? Colors.green : Colors.grey,
                          onPressed: () => _controller.setTool(CanvasTool.lasso),
                          tooltip: "Lasso Selection",
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.title_rounded),
                          color: _controller.activeTool == CanvasTool.text ? Colors.green : Colors.grey,
                          onPressed: () => _controller.setTool(CanvasTool.text),
                          tooltip: "Text Box Overlay",
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.grid_on),
                          color: _showTemplates ? Colors.green : Colors.grey,
                          onPressed: () {
                            setState(() {
                              _showTemplates = !_showTemplates;
                            });
                          },
                          tooltip: "Canvas Templates",
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.auto_awesome_motion_rounded),
                          color: Colors.grey,
                          onPressed: () => _showClipDrawerBottomSheet(context),
                          tooltip: "Clip Drawer",
                        ),
                        const SizedBox(width: 12),
                        Container(width: 1, height: 24, color: Colors.grey.shade300),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: Colors.redAccent,
                          onPressed: () => _controller.clearCanvas(),
                          tooltip: "Clear Canvas",
                        ),
                      ],
                    ),
                  ),
                  if (_controller.activeTool == CanvasTool.pen) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _controller.setPenType(PenType.fountain),
                            child: Text(
                              "Fountain",
                              style: TextStyle(
                                color: _controller.activePenType == PenType.fountain ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _controller.setPenType(PenType.ballpoint),
                            child: Text(
                              "Ballpoint",
                              style: TextStyle(
                                color: _controller.activePenType == PenType.ballpoint ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _controller.setPenType(PenType.highlighter),
                            child: Text(
                              "Highlighter",
                              style: TextStyle(
                                color: _controller.activePenType == PenType.highlighter ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _controller.setPenType(PenType.brush),
                            child: Text(
                              "Brush",
                              style: TextStyle(
                                color: _controller.activePenType == PenType.brush ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_showTemplates) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _controller.setTemplate(CanvasTemplate.blank),
                            child: Text(
                              "Blank",
                              style: TextStyle(
                                color: _controller.activeTemplate == CanvasTemplate.blank ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _controller.setTemplate(CanvasTemplate.ruled),
                            child: Text(
                              "Ruled",
                              style: TextStyle(
                                color: _controller.activeTemplate == CanvasTemplate.ruled ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _controller.setTemplate(CanvasTemplate.grid),
                            child: Text(
                              "Grid",
                              style: TextStyle(
                                color: _controller.activeTemplate == CanvasTemplate.grid ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _controller.setTemplate(CanvasTemplate.dotted),
                            child: Text(
                              "Dotted",
                              style: TextStyle(
                                color: _controller.activeTemplate == CanvasTemplate.dotted ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]
                ],
              ),
            ),
            if (_controller.selectedStrokes.isNotEmpty)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: FloatingActionButton.extended(
                    onPressed: () => _showSaveClipDialog(context),
                    label: const Text("Save Selection as Clip"),
                    icon: const Icon(Icons.save_alt_rounded),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showAddTextBoxDialog(BuildContext context, Offset position) {
    final textController = TextEditingController();
    double fontSize = 18.0;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Create Text Box"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      hintText: "Enter your text...",
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    maxLines: null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text("Font Size:"),
                      Expanded(
                        child: Slider(
                          min: 12,
                          max: 64,
                          divisions: 13,
                          value: fontSize,
                          label: "${fontSize.round()}px",
                          onChanged: (val) {
                            setDialogState(() {
                              fontSize = val;
                            });
                          },
                        ),
                      ),
                      Text("${fontSize.round()}px"),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    final text = textController.text.trim();
                    if (text.isNotEmpty) {
                      widget.controller.addTextBox(text, position, fontSize);
                    }
                    Navigator.pop(context);
                  },
                  child: const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditTextBoxDialog(BuildContext context, TextBoxModel textBox) {
    final textController = TextEditingController(text: textBox.text);
    double fontSize = textBox.fontSize;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Edit Text Box"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text("Font Size:"),
                      Expanded(
                        child: Slider(
                          min: 12,
                          max: 64,
                          divisions: 13,
                          value: fontSize,
                          label: "${fontSize.round()}px",
                          onChanged: (val) {
                            setDialogState(() {
                              fontSize = val;
                            });
                          },
                        ),
                      ),
                      Text("${fontSize.round()}px"),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    widget.controller.deleteTextBox(textBox.id!);
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  child: const Text("Delete"),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    final text = textController.text.trim();
                    if (text.isNotEmpty) {
                      widget.controller.updateTextBox(
                        textBox.copyWith(
                          text: text,
                          fontSize: fontSize,
                        ),
                      );
                    }
                    Navigator.pop(context);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSaveClipDialog(BuildContext context) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Save Selection as Clip"),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: "Enter asset name (e.g., Star)",
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  widget.controller.saveSelectedAsClip(name);
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Saved '$name' to Clip Drawer"),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  void _showClipDrawerBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final clips = widget.controller.clipAssets;

            return Container(
              height: 350,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "User Asset Clip Drawer",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: clips.isEmpty
                        ? const Center(
                            child: Text(
                              "No saved clips yet.\nUse Lasso Tool to select any drawing and save it!",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.1,
                            ),
                            itemCount: clips.length,
                            itemBuilder: (context, idx) {
                              final clip = clips[idx];
                              return Card(
                                elevation: 1.5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    final size = MediaQuery.of(context).size;
                                    widget.controller.stampClip(
                                      clip, 
                                      Offset(size.width / 2, size.height / 2),
                                    );
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("Stamped '${clip['name']}' in center of canvas"),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.auto_awesome_mosaic_rounded,
                                                color: Colors.green.shade600,
                                                size: 28,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                clip['name'] as String,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 2,
                                        right: 2,
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.redAccent,
                                              size: 16,
                                            ),
                                            onPressed: () {
                                              widget.controller.deleteClip(clip['id'] as int);
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}