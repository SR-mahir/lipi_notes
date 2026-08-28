import 'package:flutter/material.dart';
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
              title: const Text("New Folder"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Folder Name"),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: colors.map((c) {
                      final isSelected = selectedColor == c;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.black, width: 2.5)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  )
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isNotEmpty) {
                      _workspaceController.createFolder(
                        nameController.text.trim(),
                        selectedColor,
                      );
                      Navigator.pop(context);
                    }
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
          title: const Text("New Notebook"),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: "Notebook Name"),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  _workspaceController.createNotebook(
                    nameController.text.trim(),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text("Create"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _workspaceController,
      builder: (context, _) {
        final activeFolder = _workspaceController.activeFolder;
        final hasActiveFolder = activeFolder != null;

        // Apply metadata query filter
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
                      hintText: "Search notebooks & folders...",
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    autofocus: true,
                    style: const TextStyle(fontSize: 16),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
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
                      _workspaceController.navigateToFolder(null);
                      if (_isSearching) {
                        setState(() {
                          _isSearching = false;
                          _searchQuery = "";
                          _searchController.clear();
                        });
                      }
                    },
                  )
                : null,
            actions: [
              IconButton(
                icon: Icon(_isSearching ? Icons.close : Icons.search),
                onPressed: () {
                  setState(() {
                    if (_isSearching) {
                      _isSearching = false;
                      _searchQuery = "";
                      _searchController.clear();
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
          body: filteredFolders.isEmpty && filteredNotebooks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty 
                            ? "No matches found for '$_searchQuery'"
                            : "Your workspace is empty.",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isNotEmpty 
                            ? "Try refining your search keyword."
                            : "Tap the Buttons below to add folders or notebooks.",
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: filteredFolders.length + filteredNotebooks.length,
                  itemBuilder: (context, index) {
                    final showFolder = index < filteredFolders.length;
                    
                    if (showFolder) {
                      final folder = filteredFolders[index];
                      return _buildFolderCard(folder);
                    } else {
                      final notebookIndex = index - filteredFolders.length;
                      final notebook = filteredNotebooks[notebookIndex];
                      return _buildNotebookCard(notebook);
                    }
                  },
                ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasActiveFolder) ...[
                FloatingActionButton.small(
                  heroTag: "add_folder",
                  onPressed: _showCreateFolderDialog,
                  backgroundColor: Colors.green.shade100,
                  foregroundColor: Colors.green.shade900,
                  child: const Icon(Icons.create_new_folder),
                ),
                const SizedBox(height: 12),
              ],
              FloatingActionButton(
                heroTag: "add_notebook",
                onPressed: _showCreateNotebookDialog,
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                child: const Icon(Icons.add_task),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- ITEM RENDERING WIDGETS ---
  Widget _buildFolderCard(Folder folder) {
    return GestureDetector(
      onTap: () {
        _workspaceController.navigateToFolder(folder);
        if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchQuery = "";
            _searchController.clear();
          });
        }
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
