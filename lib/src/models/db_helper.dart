import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'lipinotes.db');

    return await openDatabase(
      path,
      version: 8,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        // Version 7 & 8: Full hierarchical notebook schema with subfolders, typography & dark mode
        await db.execute('''
          CREATE TABLE folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            color_value INTEGER NOT NULL,
            parent_id INTEGER,
            FOREIGN KEY (parent_id) REFERENCES folders (id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE notebooks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            folder_id INTEGER,
            dark_mode INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE SET NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE pages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            notebook_id INTEGER NOT NULL,
            page_index INTEGER NOT NULL,
            background_type TEXT NOT NULL DEFAULT 'blank',
            pdf_path TEXT,
            pdf_page_index INTEGER,
            FOREIGN KEY (notebook_id) REFERENCES notebooks (id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE strokes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path_string TEXT NOT NULL,
            color INTEGER NOT NULL,
            stroke_width REAL NOT NULL,
            pen_type TEXT NOT NULL DEFAULT 'fountain',
            page_id INTEGER NOT NULL,
            FOREIGN KEY (page_id) REFERENCES pages (id) ON DELETE CASCADE
          )
        ''');

        // Version 4 & 7: Create text_boxes table with font_family
        await db.execute('''
          CREATE TABLE text_boxes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            page_id INTEGER NOT NULL,
            text TEXT NOT NULL,
            x REAL NOT NULL,
            y REAL NOT NULL,
            width REAL NOT NULL,
            height REAL NOT NULL,
            font_size REAL NOT NULL,
            color INTEGER NOT NULL,
            font_family TEXT NOT NULL DEFAULT 'sans',
            FOREIGN KEY (page_id) REFERENCES pages (id) ON DELETE CASCADE
          )
        ''');

        // Version 5: Create clip_assets table
        await db.execute('''
          CREATE TABLE clip_assets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            path_string TEXT NOT NULL,
            color INTEGER NOT NULL,
            stroke_width REAL NOT NULL,
            pen_type TEXT NOT NULL DEFAULT 'fountain'
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE strokes ADD COLUMN pen_type TEXT NOT NULL DEFAULT 'fountain'");
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE folders (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              color_value INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE notebooks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              folder_id INTEGER,
              FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE SET NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE pages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              notebook_id INTEGER NOT NULL,
              page_index INTEGER NOT NULL,
              background_type TEXT NOT NULL DEFAULT 'blank',
              FOREIGN KEY (notebook_id) REFERENCES notebooks (id) ON DELETE CASCADE
            )
          ''');

          await db.execute("ALTER TABLE strokes ADD COLUMN page_id INTEGER");

          final List<Map<String, dynamic>> existingStrokes = await db.rawQuery('SELECT count(*) as count FROM strokes');
          final count = existingStrokes.first['count'] as int? ?? 0;
          if (count > 0) {
            final folderId = await db.insert('folders', {'name': 'Default Folder', 'color_value': 0xFF4CAF50});
            final notebookId = await db.insert('notebooks', {'name': 'My First Notebook', 'folder_id': folderId});
            final pageId = await db.insert('pages', {'notebook_id': notebookId, 'page_index': 0, 'background_type': 'blank'});
            await db.update('strokes', {'page_id': pageId});
          }
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE text_boxes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              page_id INTEGER NOT NULL,
              text TEXT NOT NULL,
              x REAL NOT NULL,
              y REAL NOT NULL,
              width REAL NOT NULL,
              height REAL NOT NULL,
              font_size REAL NOT NULL,
              color INTEGER NOT NULL,
              FOREIGN KEY (page_id) REFERENCES pages (id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE clip_assets (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              path_string TEXT NOT NULL,
              color INTEGER NOT NULL,
              stroke_width REAL NOT NULL,
              pen_type TEXT NOT NULL DEFAULT 'fountain'
            )
          ''');
        }
        if (oldVersion < 6) {
          await db.execute("ALTER TABLE pages ADD COLUMN pdf_path TEXT");
          await db.execute("ALTER TABLE pages ADD COLUMN pdf_page_index INTEGER");
        }
        if (oldVersion < 7) {
          await db.execute("ALTER TABLE folders ADD COLUMN parent_id INTEGER REFERENCES folders (id) ON DELETE CASCADE");
          await db.execute("ALTER TABLE text_boxes ADD COLUMN font_family TEXT NOT NULL DEFAULT 'sans'");
        }
        if (oldVersion < 8) {
          await db.execute("ALTER TABLE notebooks ADD COLUMN dark_mode INTEGER NOT NULL DEFAULT 0");
        }
      },
    );
  }

  // --- STROKES CRUD ---
  static Future<int> insertStroke(String pathString, int colorValue, double width, String penType, int pageId) async {
    final db = await database;
    return await db.insert(
      'strokes',
      {
        'path_string': pathString,
        'color': colorValue,
        'stroke_width': width,
        'pen_type': penType,
        'page_id': pageId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getSavedStrokes() async {
    final db = await database;
    return await db.query('strokes', orderBy: 'id ASC');
  }

  static Future<List<Map<String, dynamic>>> getSavedStrokesForPage(int pageId) async {
    final db = await database;
    return await db.query(
      'strokes',
      where: 'page_id = ?',
      whereArgs: [pageId],
      orderBy: 'id ASC',
    );
  }

  static Future<int> deleteStroke(int id) async {
    final db = await database;
    return await db.delete(
      'strokes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> clearAllStrokes() async {
    final db = await database;
    await db.delete('strokes');
  }

  // --- FOLDERS CRUD ---
  static Future<int> insertFolder(String name, int colorValue, {int? parentId}) async {
    final db = await database;
    return await db.insert('folders', {
      'name': name,
      'color_value': colorValue,
      'parent_id': parentId,
    });
  }

  static Future<List<Map<String, dynamic>>> getFolders({int? parentId}) async {
    final db = await database;
    if (parentId == null) {
      return await db.query('folders', where: 'parent_id IS NULL', orderBy: 'id ASC');
    }
    return await db.query('folders', where: 'parent_id = ?', whereArgs: [parentId], orderBy: 'id ASC');
  }

  static Future<List<Map<String, dynamic>>> getAllFolders() async {
    final db = await database;
    return await db.query('folders', orderBy: 'id ASC');
  }

  static Future<Map<String, dynamic>?> getFolderById(int id) async {
    final db = await database;
    final res = await db.query('folders', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return res.first;
    return null;
  }

  static Future<int> deleteFolder(int id) async {
    final db = await database;
    return await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  // --- NOTEBOOKS CRUD ---
  static Future<int> insertNotebook(String name, int? folderId) async {
    final db = await database;
    return await db.insert('notebooks', {'name': name, 'folder_id': folderId});
  }

  static Future<List<Map<String, dynamic>>> getNotebooks(int? folderId) async {
    final db = await database;
    if (folderId == null) {
      return await db.query('notebooks', where: 'folder_id IS NULL', orderBy: 'id ASC');
    }
    return await db.query('notebooks', where: 'folder_id = ?', whereArgs: [folderId], orderBy: 'id ASC');
  }

  static Future<List<Map<String, dynamic>>> getAllNotebooks() async {
    final db = await database;
    return await db.query('notebooks', orderBy: 'id ASC');
  }

  static Future<int> deleteNotebook(int id) async {
    final db = await database;
    return await db.delete('notebooks', where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> updateNotebookDarkMode(int notebookId, bool isDarkMode) async {
    final db = await database;
    return await db.update(
      'notebooks',
      {'dark_mode': isDarkMode ? 1 : 0},
      where: 'id = ?',
      whereArgs: [notebookId],
    );
  }

  // --- PAGES CRUD ---
  static Future<int> insertPage(int notebookId, int pageIndex, String backgroundType, {String? pdfPath, int? pdfPageIndex}) async {
    final db = await database;
    return await db.insert('pages', {
      'notebook_id': notebookId,
      'page_index': pageIndex,
      'background_type': backgroundType,
      'pdf_path': pdfPath,
      'pdf_page_index': pdfPageIndex,
    });
  }

  static Future<List<Map<String, dynamic>>> getPagesForNotebook(int notebookId) async {
    final db = await database;
    return await db.query('pages', where: 'notebook_id = ?', whereArgs: [notebookId], orderBy: 'page_index ASC');
  }

  static Future<int> updatePageBackground(int pageId, String backgroundType) async {
    final db = await database;
    return await db.update(
      'pages',
      {'background_type': backgroundType},
      where: 'id = ?',
      whereArgs: [pageId],
    );
  }

  static Future<int> updatePageIndex(int pageId, int newIndex) async {
    final db = await database;
    return await db.update(
      'pages',
      {'page_index': newIndex},
      where: 'id = ?',
      whereArgs: [pageId],
    );
  }

  static Future<int> deletePage(int id) async {
    final db = await database;
    return await db.delete('pages', where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> duplicatePage(int pageId) async {
    final db = await database;
    final pageRes = await db.query('pages', where: 'id = ?', whereArgs: [pageId]);
    if (pageRes.isEmpty) throw Exception("Page not found");
    final page = pageRes.first;
    final notebookId = page['notebook_id'] as int;
    final pageIndex = page['page_index'] as int;
    final backgroundType = page['background_type'] as String;
    final pdfPath = page['pdf_path'] as String?;
    final pdfPageIndex = page['pdf_page_index'] as int?;

    // Shift all subsequent pages by +1 to insert the duplicate right after
    await db.rawUpdate(
      'UPDATE pages SET page_index = page_index + 1 WHERE notebook_id = ? AND page_index > ?',
      [notebookId, pageIndex],
    );

    final newPageIndex = pageIndex + 1;
    final newPageId = await db.insert('pages', {
      'notebook_id': notebookId,
      'page_index': newPageIndex,
      'background_type': backgroundType,
      'pdf_path': pdfPath,
      'pdf_page_index': pdfPageIndex,
    });

    // Duplicate all strokes
    final strokes = await db.query('strokes', where: 'page_id = ?', whereArgs: [pageId]);
    for (var stroke in strokes) {
      await db.insert('strokes', {
        'path_string': stroke['path_string'],
        'color': stroke['color'],
        'stroke_width': stroke['stroke_width'],
        'pen_type': stroke['pen_type'],
        'page_id': newPageId,
      });
    }

    // Duplicate all text_boxes
    final textBoxes = await db.query('text_boxes', where: 'page_id = ?', whereArgs: [pageId]);
    for (var tb in textBoxes) {
      await db.insert('text_boxes', {
        'page_id': newPageId,
        'text': tb['text'],
        'x': tb['x'],
        'y': tb['y'],
        'width': tb['width'],
        'height': tb['height'],
        'font_size': tb['font_size'],
        'color': tb['color'],
        'font_family': tb['font_family'] ?? 'sans',
      });
    }

    return newPageId;
  }

  static Future<void> reorderPages(int notebookId, List<int> orderedPageIds) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < orderedPageIds.length; i++) {
      batch.update(
        'pages',
        {'page_index': i},
        where: 'id = ? AND notebook_id = ?',
        whereArgs: [orderedPageIds[i], notebookId],
      );
    }
    await batch.commit(noResult: true);
  }

  // --- TEXT BOXES CRUD ---
  static Future<int> insertTextBox(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('text_boxes', row);
  }

  static Future<List<Map<String, dynamic>>> getTextBoxesForPage(int pageId) async {
    final db = await database;
    return await db.query('text_boxes', where: 'page_id = ?', whereArgs: [pageId], orderBy: 'id ASC');
  }

  static Future<int> updateTextBox(int id, Map<String, dynamic> row) async {
    final db = await database;
    return await db.update('text_boxes', row, where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> deleteTextBox(int id) async {
    final db = await database;
    return await db.delete('text_boxes', where: 'id = ?', whereArgs: [id]);
  }

  // --- CLIP ASSETS CRUD ---
  static Future<int> insertClipAsset(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('clip_assets', row);
  }

  static Future<List<Map<String, dynamic>>> getClipAssets() async {
    final db = await database;
    return await db.query('clip_assets', orderBy: 'id ASC');
  }

  static Future<int> deleteClipAsset(int id) async {
    final db = await database;
    return await db.delete('clip_assets', where: 'id = ?', whereArgs: [id]);
  }

  // --- DEEP METADATA SEARCH INDEX ---
  static Future<List<Map<String, dynamic>>> searchNotes(String query) async {
    final db = await database;
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final sql = '''
      SELECT 
        text_boxes.id as text_box_id,
        text_boxes.text as matched_text,
        text_boxes.page_id,
        pages.page_index,
        notebooks.id as notebook_id,
        notebooks.name as notebook_name,
        notebooks.folder_id
      FROM text_boxes
      INNER JOIN pages ON text_boxes.page_id = pages.id
      INNER JOIN notebooks ON pages.notebook_id = notebooks.id
      WHERE LOWER(text_boxes.text) LIKE ?
      ORDER BY notebooks.id, pages.page_index
    ''';

    return await db.rawQuery(sql, ['%$cleanQuery%']);
  }
}