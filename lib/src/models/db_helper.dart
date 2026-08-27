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
      version: 4,
      onCreate: (db, version) async {
        // Version 3: Create full hierarchical notebook schema
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

        // Version 4: Create text_boxes table
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
  static Future<int> insertFolder(String name, int colorValue) async {
    final db = await database;
    return await db.insert('folders', {'name': name, 'color_value': colorValue});
  }

  static Future<List<Map<String, dynamic>>> getFolders() async {
    final db = await database;
    return await db.query('folders', orderBy: 'id ASC');
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

  // --- PAGES CRUD ---
  static Future<int> insertPage(int notebookId, int pageIndex, String backgroundType) async {
    final db = await database;
    return await db.insert('pages', {
      'notebook_id': notebookId,
      'page_index': pageIndex,
      'background_type': backgroundType,
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
}