import 'package:flutter/material.dart';
import '../models/workspace_models.dart';
import '../models/db_helper.dart';

class WorkspaceController extends ChangeNotifier {
  List<Folder> _folders = [];
  List<Notebook> _notebooks = [];
  Folder? _activeFolder;
  final List<Folder> _breadcrumbs = [];

  List<Folder> get folders => _folders;
  List<Notebook> get notebooks => _notebooks;
  Folder? get activeFolder => _activeFolder;
  List<Folder> get breadcrumbs => List.unmodifiable(_breadcrumbs);

  WorkspaceController() {
    loadWorkspace();
  }

  Future<void> loadWorkspace() async {
    try {
      final folderData = await DBHelper.getFolders(parentId: _activeFolder?.id);
      _folders = folderData.map((map) => Folder.fromMap(map)).toList();

      final notebookData = await DBHelper.getNotebooks(_activeFolder?.id);
      _notebooks = notebookData.map((map) => Notebook.fromMap(map)).toList();

      notifyListeners();
    } catch (e) {
      debugPrint("Failed to load workspace data: $e");
    }
  }

  Future<void> createFolder(String name, int colorValue) async {
    await DBHelper.insertFolder(name, colorValue, parentId: _activeFolder?.id);
    await loadWorkspace();
  }

  Future<void> deleteFolder(int folderId) async {
    await DBHelper.deleteFolder(folderId);
    if (_activeFolder?.id == folderId) {
      navigateUp();
    } else {
      _breadcrumbs.removeWhere((f) => f.id == folderId);
      await loadWorkspace();
    }
  }

  Future<void> createNotebook(String name) async {
    final notebookId = await DBHelper.insertNotebook(name, _activeFolder?.id);
    // Create the initial page automatically (0-indexed Page 1)
    await DBHelper.insertPage(notebookId, 0, 'blank');
    await loadWorkspace();
  }

  Future<int> importPDFNotebook(String name, String pdfPath, int totalPages) async {
    final notebookId = await DBHelper.insertNotebook(name, _activeFolder?.id);
    for (int i = 0; i < totalPages; i++) {
      await DBHelper.insertPage(
        notebookId, 
        i, 
        'blank',
        pdfPath: pdfPath,
        pdfPageIndex: i + 1,
      );
    }
    await loadWorkspace();
    return notebookId;
  }

  Future<void> deleteNotebook(int notebookId) async {
    await DBHelper.deleteNotebook(notebookId);
    await loadWorkspace();
  }

  void navigateToFolder(Folder? folder) {
    if (folder == null) {
      _breadcrumbs.clear();
      _activeFolder = null;
    } else {
      final existingIndex = _breadcrumbs.indexWhere((f) => f.id == folder.id);
      if (existingIndex >= 0) {
        _breadcrumbs.removeRange(existingIndex + 1, _breadcrumbs.length);
      } else {
        _breadcrumbs.add(folder);
      }
      _activeFolder = folder;
    }
    loadWorkspace();
  }

  void navigateUp() {
    if (_breadcrumbs.isNotEmpty) {
      _breadcrumbs.removeLast();
      _activeFolder = _breadcrumbs.isNotEmpty ? _breadcrumbs.last : null;
      loadWorkspace();
    }
  }

  void navigateToBreadcrumb(int index) {
    if (index < 0) {
      navigateToFolder(null);
    } else if (index < _breadcrumbs.length) {
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
      _activeFolder = _breadcrumbs.last;
      loadWorkspace();
    }
  }

  Future<List<Map<String, dynamic>>> searchDeep(String query) async {
    return await DBHelper.searchNotes(query);
  }
}
