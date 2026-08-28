import 'package:flutter/material.dart';
import '../models/workspace_models.dart';
import '../models/db_helper.dart';

class WorkspaceController extends ChangeNotifier {
  List<Folder> _folders = [];
  List<Notebook> _notebooks = [];
  Folder? _activeFolder;

  List<Folder> get folders => _folders;
  List<Notebook> get notebooks => _notebooks;
  Folder? get activeFolder => _activeFolder;

  WorkspaceController() {
    loadWorkspace();
  }

  Future<void> loadWorkspace() async {
    try {
      final folderData = await DBHelper.getFolders();
      _folders = folderData.map((map) => Folder.fromMap(map)).toList();

      final notebookData = await DBHelper.getNotebooks(_activeFolder?.id);
      _notebooks = notebookData.map((map) => Notebook.fromMap(map)).toList();

      notifyListeners();
    } catch (e) {
      debugPrint("Failed to load workspace data: $e");
    }
  }

  Future<void> createFolder(String name, int colorValue) async {
    await DBHelper.insertFolder(name, colorValue);
    await loadWorkspace();
  }

  Future<void> deleteFolder(int folderId) async {
    await DBHelper.deleteFolder(folderId);
    if (_activeFolder?.id == folderId) {
      _activeFolder = null;
    }
    await loadWorkspace();
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
    _activeFolder = folder;
    loadWorkspace();
  }
}
