class Folder {
  final int? id;
  final String name;
  final int colorValue;

  Folder({
    this.id,
    required this.name,
    required this.colorValue,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'color_value': colorValue,
    };
  }

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as int?,
      name: map['name'] as String,
      colorValue: map['color_value'] as int,
    );
  }
}

class Notebook {
  final int? id;
  final String name;
  final int? folderId;

  Notebook({
    this.id,
    required this.name,
    this.folderId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'folder_id': folderId,
    };
  }

  factory Notebook.fromMap(Map<String, dynamic> map) {
    return Notebook(
      id: map['id'] as int?,
      name: map['name'] as String,
      folderId: map['folder_id'] as int?,
    );
  }
}

class NotebookPage {
  final int? id;
  final int notebookId;
  final int pageIndex;
  final String backgroundType; // 'blank', 'ruled', 'grid', 'dotted'
  final String? pdfPath;
  final int? pdfPageIndex;

  NotebookPage({
    this.id,
    required this.notebookId,
    required this.pageIndex,
    this.backgroundType = 'blank',
    this.pdfPath,
    this.pdfPageIndex,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'notebook_id': notebookId,
      'page_index': pageIndex,
      'background_type': backgroundType,
      'pdf_path': pdfPath,
      'pdf_page_index': pdfPageIndex,
    };
  }

  factory NotebookPage.fromMap(Map<String, dynamic> map) {
    return NotebookPage(
      id: map['id'] as int?,
      notebookId: map['notebook_id'] as int,
      pageIndex: map['page_index'] as int,
      backgroundType: map['background_type'] as String? ?? 'blank',
      pdfPath: map['pdf_path'] as String?,
      pdfPageIndex: map['pdf_page_index'] as int?,
    );
  }
}
