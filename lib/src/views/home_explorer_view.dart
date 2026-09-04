import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';
import '../controllers/workspace_controller.dart';
import '../models/workspace_models.dart';
import 'notebook_editor_view.dart';

class HomeExplorerView extends StatefulWidget {
  const HomeExplorerView({super.key});

  @override
  State<HomeExplorerView> createState() => _HomeExplorerViewState();
}

class _HomeExplorerViewState extends State<HomeExplorerView> {
  late final WorkspaceController _workspaceController;
  bool _isSearching = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _deepSearchResults = [];

  @override
  void initState() {
    super.initState();
    _workspaceController = WorkspaceController();
  }

  @override
  void dispose() {
    _workspaceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) async {
    setState(() {
      _searchQuery = val;
    });
    if (val.trim().isNotEmpty) {
      final results = await _workspaceController.searchDeep(val);
      if (mounted) {
        setState(() {
          _deepSearchResults = results;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _deepSearchResults = [];
        });
      }
    }
  }

  void _clearSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = "";
      _searchController.clear();
      _deepSearchResults = [];
    });
  }

  // --- SHOW CREATE FOLDER DIALOG ---
  void _showCreateFolderDialog() {
    final nameController = TextEditingController();
    int selectedColor = 0xFF4CAF50; // Green default
    final List<int> colors = [
      0xFF4CAF50, // Green
      0xFF2196F3, // Blue
      0xFFFF9800, // Orange
      0xFFE91E63, // Pink
      0xFF9C27B0, // Purple
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_workspaceController.activeFolder != null ? "Create Sub-Folder" : "Create Folder"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: _workspaceController.activeFolder != null ? "Sub-folder name" : "Folder name",
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: colors.map((colorValue) {
                      final isSelected = selectedColor == colorValue;
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            selectedColor = colorValue;
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(colorValue),
                            shape: BoxShape.circle,
                            border: isSelected ? Border.all(color: Colors.black87, width: 3) : null,
                          ),
                        ),
                      );
                    }).toList(),
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
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      _workspaceController.createFolder(name, selectedColor);
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

  // --- SHOW CREATE NOTEBOOK DIALOG ---
  void _showCreateNotebookDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Create Notebook"),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: "Notebook name",
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
                  _workspaceController.createNotebook(name);
                }
                Navigator.pop(context);
              },
              child: const Text("Create"),
            ),
          ],
        );
      },
    );
  }

  // --- IMPORT PDF FLOW ---
  Future<void> _importPDFNotebookFlow() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.single.path == null) return;
      
      final path = result.files.single.path!;
      final name = result.files.single.name.replaceAll('.pdf', '');

      // Open PDF document using pdfx to retrieve number of pages
      final document = await PdfDocument.openFile(path);
      final totalPages = document.pagesCount;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(color: Colors.green),
                SizedBox(width: 20),
                Text("Importing and parsing PDF..."),
              ],
            ),
          );
        },
      );

      final notebookId = await _workspaceController.importPDFNotebook(name, path, totalPages);
      
      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        final importedNotebook = Notebook(
          id: notebookId,
          name: name,
          folderId: _workspaceController.activeFolder?.id,
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NotebookEditorView(notebook: importedNotebook),
          ),
        ).then((_) => _workspaceController.loadWorkspace());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to import PDF notebook: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _workspaceController,
      builder: (context, _) {
        final activeFolder = _workspaceController.activeFolder;
        final hasActiveFolder = activeFolder != null;
        final breadcrumbs = _workspaceController.breadcrumbs;

        final filteredFolders = _workspaceController.folders.where(
          (f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase())
        ).toList();

        final filteredNotebooks = _workspaceController.notebooks.where(
          (n) => n.name.toLowerCase().contains(_searchQuery.toLowerCase())
        ).toList();

        return Scaffold(
          appBar: AppBar(
            title: _isSearching
                ? TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: "Search notebooks, folders, & page text...",
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    autofocus: true,
                    style: const TextStyle(fontSize: 16),
                    onChanged: _onSearchChanged,
                  )
                : Row(
                    children: [
                      const Icon(Icons.book_rounded, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        hasActiveFolder ? activeFolder.name : "Lipinotes Workspace",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
            leading: hasActiveFolder
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      _workspaceController.navigateUp();
                      if (_isSearching) _clearSearch();
                    },
                  )
                : null,
            actions: [
              IconButton(
                icon: Icon(_isSearching ? Icons.close : Icons.search),
                onPressed: () {
                  setState(() {
                    if (_isSearching) {
                      _clearSearch();
                    } else {
                      _isSearching = true;
                    }
                  });
                },
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
          backgroundColor: const Color(0xFFF7F7F7),
          body: Column(
            children: [
              // Breadcrumb trail bar
              if (breadcrumbs.isNotEmpty && !_isSearching)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _workspaceController.navigateToFolder(null),
                          child: const Row(
                            children: [
                              Icon(Icons.home_outlined, size: 16, color: Colors.green),
                              SizedBox(width: 4),
                              Text("Home", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        for (int i = 0; i < breadcrumbs.length; i++) ...[
                          const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                          GestureDetector(
                            onTap: () => _workspaceController.navigateToBreadcrumb(i),
                            child: Text(
                              breadcrumbs[i].name,
                              style: TextStyle(
                                color: i == breadcrumbs.length - 1 ? Colors.black87 : Colors.green,
                                fontWeight: i == breadcrumbs.length - 1 ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // Main Body: Search Results or Explorer Grid
              Expanded(
                child: _isSearching && _searchQuery.isNotEmpty
                    ? _buildSearchResultsView(filteredFolders, filteredNotebooks)
                    : _buildWorkspaceGrid(filteredFolders, filteredNotebooks),
              ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: "add_folder",
                onPressed: _showCreateFolderDialog,
                backgroundColor: Colors.green.shade100,
                foregroundColor: Colors.green.shade900,
                tooltip: hasActiveFolder ? "Add Sub-Folder" : "Add Folder",
                child: const Icon(Icons.create_new_folder),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.small(
                heroTag: "import_pdf",
                onPressed: _importPDFNotebookFlow,
                backgroundColor: Colors.green.shade100,
                foregroundColor: Colors.green.shade900,
                tooltip: "Import PDF Notebook",
                child: const Icon(Icons.picture_as_pdf),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: "add_notebook",
                onPressed: _showCreateNotebookDialog,
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                tooltip: "Create Notebook",
                child: const Icon(Icons.add_task),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- SEARCH RESULTS VIEW WITH PAGE NOTE SNIPPETS ---
  Widget _buildSearchResultsView(List<Folder> folders, List<Notebook> notebooks) {
    final hasNoResults = folders.isEmpty && notebooks.isEmpty && _deepSearchResults.isEmpty;

    if (hasNoResults) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              "No matches found for '$_searchQuery'",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              "Searched across folder titles, notebook titles, and page note contents.",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (folders.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              "FOLDERS",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
            ),
          ),
          ...folders.map((f) => ListTile(
            leading: Icon(Icons.folder_rounded, color: Color(f.colorValue)),
            title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            onTap: () {
              _workspaceController.navigateToFolder(f);
              _clearSearch();
            },
          )),
        ],

        if (notebooks.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              "NOTEBOOKS",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
            ),
          ),
          ...notebooks.map((n) => ListTile(
            leading: const Icon(Icons.chrome_reader_mode_rounded, color: Colors.green),
            title: Text(n.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => NotebookEditorView(notebook: n)),
              ).then((_) => _workspaceController.loadWorkspace());
            },
          )),
        ],

        if (_deepSearchResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              "MATCHES IN PAGE NOTES (TEXT OVERLAY)",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
            ),
          ),
          ..._deepSearchResults.map((item) {
            final notebookId = item['notebook_id'] as int;
            final notebookName = item['notebook_name'] as String;
            final pageIndex = item['page_index'] as int;
            final matchedText = item['matched_text'] as String;
            final folderId = item['folder_id'] as int?;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 1,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade50,
                  child: const Icon(Icons.sticky_note_2_outlined, color: Colors.green, size: 20),
                ),
                title: Text(
                  "$notebookName • Page ${pageIndex + 1}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                subtitle: Text(
                  matchedText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                onTap: () {
                  final nb = Notebook(id: notebookId, name: notebookName, folderId: folderId);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NotebookEditorView(
                        notebook: nb,
                        initialPageIndex: pageIndex,
                      ),
                    ),
                  ).then((_) => _workspaceController.loadWorkspace());
                },
              ),
            );
          }),
        ],
      ],
    );
  }

  // --- WORKSPACE GRID VIEW ---
  Widget _buildWorkspaceGrid(List<Folder> folders, List<Notebook> notebooks) {
    if (folders.isEmpty && notebooks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty 
                  ? "No matches found for '$_searchQuery'"
                  : "This folder is empty.",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty 
                  ? "Try refining your search keyword."
                  : "Tap the buttons below to create folders, notebooks, or import PDFs.",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 0.85,
      ),
      itemCount: folders.length + notebooks.length,
      itemBuilder: (context, index) {
        final showFolder = index < folders.length;
        if (showFolder) {
          return _buildFolderCard(folders[index]);
        } else {
          final notebookIndex = index - folders.length;
          return _buildNotebookCard(notebooks[notebookIndex]);
        }
      },
    );
  }

  // --- ITEM RENDERING WIDGETS ---
  Widget _buildFolderCard(Folder folder) {
    return GestureDetector(
      onTap: () {
        _workspaceController.navigateToFolder(folder);
        if (_isSearching) _clearSearch();
      },
      child: Card(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_rounded,
                    size: 72,
                    color: Color(folder.colorValue),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      folder.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                onPressed: () => _showDeleteConfirmation(folder.name, () {
                  _workspaceController.deleteFolder(folder.id!);
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotebookCard(Notebook notebook) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NotebookEditorView(notebook: notebook),
          ),
        ).then((_) => _workspaceController.loadWorkspace());
      },
      child: Card(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.chrome_reader_mode_rounded,
                    size: 72,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      notebook.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                onPressed: () => _showDeleteConfirmation(notebook.name, () {
                  _workspaceController.deleteNotebook(notebook.id!);
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(String itemName, VoidCallback onDelete) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Confirmation"),
          content: Text("Are you sure you want to permanently delete '$itemName'?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                onDelete();
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
