import 'package:flutter/material.dart';
import '../models/workspace_models.dart';
import '../controllers/canvas_controller.dart';
import '../utils/pdf_exporter.dart';
import 'drawing_canvas_view.dart';

class NotebookEditorView extends StatefulWidget {
  final Notebook notebook;

  const NotebookEditorView({super.key, required this.notebook});

  @override
  State<NotebookEditorView> createState() => _NotebookEditorViewState();
}

class _NotebookEditorViewState extends State<NotebookEditorView> {
  late final CanvasController _canvasController;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _canvasController = CanvasController(notebook: widget.notebook);
  }

  @override
  void dispose() {
    _canvasController.dispose();
    super.dispose();
  }

  Future<void> _exportToPDF() async {
    setState(() => _isExporting = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: Colors.green),
              SizedBox(width: 20),
              Text("Compiling Vector PDF..."),
            ],
          ),
        );
      },
    );

    try {
      await PDFExporter.exportNotebook(widget.notebook);
    } catch (e) {
      debugPrint("Failed to export notebook: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to export PDF: $e")),
        );
      }
    } finally {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _canvasController,
      builder: (context, _) {
        final pagesCount = _canvasController.pages.length;
        final currentIndex = _canvasController.currentPageIndex;
        final hasMultiplePages = pagesCount > 1;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.notebook.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  "Notebook Editor",
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _canvasController.isDarkMode 
                      ? Icons.light_mode_outlined 
                      : Icons.dark_mode_outlined,
                  color: Colors.green,
                ),
                tooltip: _canvasController.isDarkMode ? "Light Mode" : "Dark Mode",
                onPressed: () => _canvasController.toggleDarkMode(),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.green),
                tooltip: "Export PDF",
                onPressed: _isExporting ? null : _exportToPDF,
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                tooltip: "Delete Current Page",
                onPressed: hasMultiplePages
                    ? () => _showDeletePageConfirmation()
                    : null,
              ),
              const SizedBox(width: 8),
            ],
            backgroundColor: Colors.white,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(color: Colors.grey.shade200, height: 1.0),
            ),
          ),
          body: DrawingCanvasView(controller: _canvasController),
          bottomNavigationBar: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                )
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous Page Button
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: currentIndex > 0
                      ? () => _canvasController.prevPage()
                      : null,
                ),
                
                // Pagination Indicator
                Text(
                  "Page ${currentIndex + 1} of $pagesCount",
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),

                // Next Page Button / Add Page Button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded),
                      onPressed: currentIndex < pagesCount - 1
                          ? () => _canvasController.nextPage()
                          : null,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_box_outlined, color: Colors.green),
                      tooltip: "Add Page",
                      onPressed: () => _canvasController.addPage(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeletePageConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Page"),
          content: Text("Are you sure you want to delete Page ${_canvasController.currentPageIndex + 1}? All strokes on this page will be permanently erased."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                _canvasController.deleteCurrentPage();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );
  }
}
