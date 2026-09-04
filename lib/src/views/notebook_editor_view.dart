import 'package:flutter/material.dart';

import '../controllers/canvas_controller.dart';
import '../models/workspace_models.dart';
import 'drawing_canvas_view.dart';

class NotebookEditorView extends StatefulWidget {
  final Notebook notebook;
  final int? initialPageIndex;

  const NotebookEditorView({
    super.key, 
    required this.notebook,
    this.initialPageIndex,
  });

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
    if (widget.initialPageIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _canvasController.goToPage(widget.initialPageIndex!);
      });
    }
  }

  @override
  void dispose() {
    _canvasController.dispose();
    super.dispose();
  }

  Future<void> _exportToPDF([BuildContext? originContext]) async {
    // On iPad/iOS, sharePositionOrigin is required to anchor the popover.
    Rect? shareOrigin;
    final targetContext = originContext ?? context;
    final box = targetContext.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
      shareOrigin = box.localToGlobal(Offset.zero) & box.size;
    }
    final media = MediaQuery.of(context);
    shareOrigin ??= Rect.fromLTWH(media.size.width - 60, 40, 40, 40);

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
              Text("Generating PDF document..."),
            ],
          ),
        );
      },
    );

    try {
      await _canvasController.exportToPDF(sharePositionOrigin: shareOrigin);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Export failed: $e")),
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
                icon: const Icon(Icons.grid_view_rounded, color: Colors.green),
                tooltip: "Page Organizer",
                onPressed: _showPageOrganizerModal,
              ),
              IconButton(
                icon: const Icon(Icons.control_point_duplicate_rounded, color: Colors.green),
                tooltip: "Duplicate Current Page",
                onPressed: () async {
                  await _canvasController.duplicateCurrentPage();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Duplicated Page to Page ${_canvasController.currentPageIndex + 1}")),
                    );
                  }
                },
              ),
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
              Builder(
                builder: (btnContext) => IconButton(
                  icon: const Icon(Icons.share_outlined, color: Colors.green),
                  tooltip: "Export PDF",
                  onPressed: _isExporting ? null : () => _exportToPDF(btnContext),
                ),
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
                
                // Pagination Indicator & Quick Jump
                GestureDetector(
                  onTap: _showPageOrganizerModal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Page ${currentIndex + 1} of $pagesCount",
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down_rounded, size: 18),
                      ],
                    ),
                  ),
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

  void _showPageOrganizerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return ListenableBuilder(
          listenable: _canvasController,
          builder: (context, _) {
            final pages = _canvasController.pages;
            final currentIndex = _canvasController.currentPageIndex;

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.grid_view_rounded, color: Colors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Page Organizer (${pages.length} Pages)",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Text(
                                  "Drag handles to reorder, or tap to jump to page.",
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(modalContext),
                          ),
                        ],
                      ),
                    ),

                    // Reorderable list
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: pages.length,
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final List<int> orderedIds = pages.map((p) => p.id!).toList();
                          final movedId = orderedIds.removeAt(oldIndex);
                          orderedIds.insert(newIndex, movedId);
                          _canvasController.reorderPages(orderedIds);
                        },
                        itemBuilder: (context, index) {
                          final page = pages[index];
                          final isCurrent = index == currentIndex;

                          return Card(
                            key: ValueKey(page.id),
                            elevation: isCurrent ? 2 : 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isCurrent ? Colors.green : Colors.grey.shade300,
                                width: isCurrent ? 2 : 1,
                              ),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: isCurrent ? Colors.green : Colors.grey.shade200,
                                child: Text(
                                  "${index + 1}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isCurrent ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    "Page ${index + 1}",
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        "ACTIVE",
                                        style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                "${page.backgroundType.toUpperCase()} background${page.pdfPath != null ? ' • PDF Page ${page.pdfPageIndex}' : ''}",
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.blueGrey),
                                    tooltip: "Duplicate",
                                    onPressed: () async {
                                      await _canvasController.duplicateCurrentPage();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text("Duplicated Page to Page ${_canvasController.currentPageIndex + 1}")),
                                        );
                                      }
                                    },
                                  ),
                                  if (pages.length > 1)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                      tooltip: "Delete",
                                      onPressed: () async {
                                        await _canvasController.goToPage(index);
                                        await _canvasController.deleteCurrentPage();
                                      },
                                    ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Icon(Icons.drag_handle_rounded, color: Colors.grey),
                                  ),
                                ],
                              ),
                              onTap: () {
                                _canvasController.goToPage(index);
                                Navigator.pop(modalContext);
                              },
                            ),
                          );
                        },
                      ),
                    ),

                    // Bottom Bar
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await _canvasController.addPage();
                            if (modalContext.mounted) {
                              Navigator.pop(modalContext);
                            }
                          },
                          icon: const Icon(Icons.add_rounded),
                          label: const Text("Add Blank Page"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
