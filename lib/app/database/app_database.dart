import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. Version and [onCreate]/[onUpgrade] define the schema;
/// add tables in migrations as the app grows.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'nexora.db';
  static const _version = 1;

  Database? _db;

  /// Opens the database if needed. Safe to call multiple times.
  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;

    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
CREATE TABLE app_meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)
''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Example: if (oldVersion < 2) { await db.execute('CREATE TABLE ...'); }
  }

  /// Small typed helper for app-wide key/value rows (migrations, flags, etc.).
  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeMeta(String key) async {
    final db = await database;
    await db.delete('app_meta', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
