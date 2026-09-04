class Folder {
  final int? id;
  final String name;
  final int colorValue;
  final int? parentId;

  Folder({
    this.id,
    required this.name,
    required this.colorValue,
    this.parentId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'color_value': colorValue,
      'parent_id': parentId,
    };
  }

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as int?,
      name: map['name'] as String,
      colorValue: map['color_value'] as int,
      parentId: map['parent_id'] as int?,
    );
  }
}

class Notebook {
  final int? id;
  final String name;
  final int? folderId;
  final bool isDarkMode;

  Notebook({
    this.id,
    required this.name,
    this.folderId,
    this.isDarkMode = false,
  });

  Notebook copyWith({
    int? id,
    String? name,
    int? folderId,
    bool? isDarkMode,
  }) {
    return Notebook(
      id: id ?? this.id,
      name: name ?? this.name,
      folderId: folderId ?? this.folderId,
      isDarkMode: isDarkMode ?? this.isDarkMode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'folder_id': folderId,
      'dark_mode': isDarkMode ? 1 : 0,
    };
  }

  factory Notebook.fromMap(Map<String, dynamic> map) {
    return Notebook(
      id: map['id'] as int?,
      name: map['name'] as String,
      folderId: map['folder_id'] as int?,
      isDarkMode: (map['dark_mode'] as int? ?? 0) == 1,
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
