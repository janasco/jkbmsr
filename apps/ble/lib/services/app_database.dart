import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// App-local SQLite database. Currently backs app settings (theme mode,
/// last-connected BMS device) as a simple key/value table.
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _db;

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    final opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'jkbmsr_ble.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
        );
      },
    );
  }

  Future<String?> getValue(String key) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> setValue(String key, String value) async {
    try {
      final db = await _database;
      await db.insert(
        'app_settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> removeValue(String key) async {
    try {
      final db = await _database;
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
    } catch (_) {}
  }
}
