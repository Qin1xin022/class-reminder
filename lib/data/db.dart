import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 单例数据库。Android 用 sqflite 原生实现，Windows/Linux 用 sqlite3 FFI。
class AppDb {
  AppDb._();
  static final AppDb I = AppDb._();

  static const int schemaVersion = 12;

  Database? _db;

  DatabaseFactory get _factory {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }

  Future<Database> get db async {
    final cached = _db;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'class_reminder.db');
    final opened = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: schemaVersion, onCreate: _onCreate, onUpgrade: _onUpgrade),
    );
    _db = opened;
    return opened;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE courses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        teacher TEXT NOT NULL,
        location TEXT NOT NULL,
        weekday INTEGER NOT NULL,
        start_min INTEGER NOT NULL,
        end_min INTEGER NOT NULL,
        week_start INTEGER NOT NULL,
        week_end INTEGER NOT NULL,
        color INTEGER NOT NULL,
        remind TEXT NOT NULL DEFAULT '30,15'
      )
    ''');
    await db.execute('''
      CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        course_id INTEGER,
        folder_id INTEGER,
        comp_id INTEGER,
        start_at INTEGER,
        end_at INTEGER,
        due_at INTEGER,
        remind TEXT NOT NULL,
        done INTEGER NOT NULL,
        note TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        score TEXT NOT NULL DEFAULT '',
        reviewer TEXT NOT NULL DEFAULT '',
        review_note TEXT NOT NULL DEFAULT '',
        evaluated_at INTEGER,
        summary TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        tags TEXT NOT NULL,
        course_id INTEGER,
        folder_id INTEGER,
        pinned INTEGER NOT NULL,
        rating INTEGER NOT NULL DEFAULT 0,
        review TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE reviews(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date_key TEXT NOT NULL UNIQUE,
        done_text TEXT NOT NULL,
        blocker_text TEXT NOT NULL,
        tomorrow_text TEXT NOT NULL,
        mood INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await _createFocusTable(db);
    await _createV3Tables(db);
    await _createV4Tables(db);
    await _createV8Tables(db);
    await _createV10Columns(db);
    await _createV11Tables(db);
    await _createV12Columns(db);
  }

  Future<void> _createFocusTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS focus_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        task_id INTEGER,
        task_title TEXT NOT NULL,
        start_at INTEGER NOT NULL,
        end_at INTEGER
      )
    ''');
  }

  /// 文件夹 / 附件 / 比赛 / 通知
  Future<void> _createV3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS folders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        scope TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_type TEXT NOT NULL,
        owner_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        path TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS competitions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        stage TEXT NOT NULL,
        level TEXT NOT NULL,
        signup_deadline INTEGER,
        start_at INTEGER,
        end_at INTEGER,
        location TEXT NOT NULL DEFAULT '',
        link TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        importance INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        attended INTEGER NOT NULL DEFAULT 0,
        result_rank TEXT NOT NULL DEFAULT 'pending',
        result_note TEXT NOT NULL DEFAULT '',
        result_at INTEGER,
        summary TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notices(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        key_points TEXT NOT NULL DEFAULT '',
        links TEXT NOT NULL DEFAULT '',
        importance INTEGER NOT NULL DEFAULT 1,
        read INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        deadline_at INTEGER,
        remind TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  /// 灵感 / 痛点 / 想法
  Future<void> _createV4Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ideas(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL DEFAULT 'idea',
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '',
        folder_id INTEGER,
        pinned INTEGER NOT NULL DEFAULT 0,
        rating INTEGER NOT NULL DEFAULT 0,
        review TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  /// v8：资源库 / 作业点评
  Future<void> _createV8Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resources(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'other',
        domain TEXT NOT NULL DEFAULT 'life',
        subject TEXT NOT NULL DEFAULT '',
        giver TEXT NOT NULL DEFAULT '',
        relation TEXT NOT NULL DEFAULT '',
        purpose TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        links TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_comments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        role TEXT NOT NULL DEFAULT 'teacher',
        person TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await _addColumnIfMissing(db, 'courses', 'note', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(db, 'courses', 'teacher_note', "TEXT NOT NULL DEFAULT ''");
  }

  /// v10：各板块通用链接 + 作业提交方式
  Future<void> _createV10Columns(Database db) async {
    await _addColumnIfMissing(db, 'courses', 'links', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(db, 'tasks', 'submit_method', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(db, 'tasks', 'links', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(db, 'notes', 'links', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(db, 'ideas', 'links', "TEXT NOT NULL DEFAULT ''");
  }

  /// v12：通知的截止时间 + 截止前多档提醒
  Future<void> _createV12Columns(Database db) async {
    await _addColumnIfMissing(db, 'notices', 'deadline_at', 'INTEGER');
    await _addColumnIfMissing(db, 'notices', 'remind', "TEXT NOT NULL DEFAULT ''");
  }

  /// v11：考试 / 课程成绩
  Future<void> _createV11Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exams(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        course_id INTEGER,
        course_name TEXT NOT NULL DEFAULT '',
        start_at INTEGER NOT NULL,
        end_at INTEGER,
        location TEXT NOT NULL DEFAULT '',
        seat TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        remind TEXT NOT NULL DEFAULT '1440,60',
        links TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS grades(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id INTEGER,
        course_name TEXT NOT NULL,
        credit REAL NOT NULL DEFAULT 0,
        score REAL,
        gpa REAL,
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE courses ADD COLUMN remind TEXT NOT NULL DEFAULT '30,15'");
      await _createFocusTable(db);
    }
    if (oldVersion < 3) {
      await _createV3Tables(db);
      await _addColumnIfMissing(db, 'tasks', 'folder_id', 'INTEGER');
      await _addColumnIfMissing(db, 'tasks', 'comp_id', 'INTEGER');
      await _addColumnIfMissing(db, 'notes', 'folder_id', 'INTEGER');
    }
    if (oldVersion < 4) {
      await _createV4Tables(db);
    }
    if (oldVersion < 5) {
      await _addColumnIfMissing(db, 'competitions', 'attended', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'competitions', 'result_rank', "TEXT NOT NULL DEFAULT 'pending'");
      await _addColumnIfMissing(db, 'competitions', 'result_note', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'competitions', 'result_at', 'INTEGER');
    }
    if (oldVersion < 6) {
      await _addColumnIfMissing(db, 'tasks', 'score', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'tasks', 'reviewer', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'tasks', 'review_note', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'tasks', 'evaluated_at', 'INTEGER');
      await _addColumnIfMissing(db, 'tasks', 'summary', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'competitions', 'summary', "TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 7) {
      await _addColumnIfMissing(db, 'notes', 'rating', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'notes', 'review', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, 'ideas', 'rating', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'ideas', 'review', "TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 8) {
      await _createV8Tables(db);
    }
    if (oldVersion < 9) {
      await _addColumnIfMissing(db, 'resources', 'links', "TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 10) {
      await _createV10Columns(db);
    }
    if (oldVersion < 11) {
      await _createV11Tables(db);
    }
    if (oldVersion < 12) {
      await _createV12Columns(db);
    }
  }

  Future<void> _addColumnIfMissing(Database db, String table, String column, String type) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => (row['name'] as String?) == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }
}
