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
      version: 1,
      onCreate: (db, version) async {
        // Create the strokes database table to save ink configurations
        await db.execute('''
          CREATE TABLE strokes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path_string TEXT NOT NULL,
            color INTEGER NOT NULL,
            stroke_width REAL NOT NULL
          )
        ''');
      },
    );
  }

  // --- SAVE OPERATION ---
  static Future<int> insertStroke(String pathString, int colorValue, double width) async {
    final db = await database;
    return await db.insert(
      'strokes',
      {
        'path_string': pathString,
        'color': colorValue,
        'stroke_width': width,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- LOAD OPERATION ---
  static Future<List<Map<String, dynamic>>> getSavedStrokes() async {
    final db = await database;
    return await db.query('strokes', orderBy: 'id ASC');
  }

  // --- DELETE OPERATION ---
  static Future<int> deleteStroke(int id) async {
    final db = await database;
    return await db.delete(
      'strokes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- WIPE OPERATION ---
  static Future<void> clearAllStrokes() async {
    final db = await database;
    await db.delete('strokes');
  }
}