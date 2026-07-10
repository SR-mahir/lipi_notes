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
        // Create Notebooks Directory Table
        await db.execute('''
          CREATE TABLE notebooks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        // Create Canvas Pages Order Table
        await db.execute('''
          CREATE TABLE pages (
            id TEXT PRIMARY KEY,
            notebook_id TEXT NOT NULL,
            page_index INTEGER NOT NULL,
            FOREIGN KEY (notebook_id) REFERENCES notebooks (id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }
}