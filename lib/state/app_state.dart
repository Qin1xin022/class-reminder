import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../models.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';

/// 全局状态：数据库读写 + 通知重排 + 小组件刷新。
class AppState extends ChangeNotifier {
  List<Course> courses = [];
  List<TaskItem> tasks = [];
  List<NoteItem> notes = [];
  List<FocusSession> focusSessions = [];
  List<Folder> folders = [];
  List<Competition> competitions = [];
  List<NoticeItem> notices = [];
  List<IdeaItem> ideas = [];
  List<ResourceItem> resources = [];
  List<TaskComment> taskComments = [];
  List<Exam> exams = [];
  List<Grade> grades = [];
  List<AttachmentItem> attachments = [];
  Map<String, ReviewItem> reviews = {};
  String termStart = '';
  bool ready = false;

  // 外观偏好（设置页可改，存 settings 表）
  int themeSeed = kDefaultSeed.value;
  bool darkMode = false;
  double fontScale = 1.0; // 0.85 小 / 1.0 标准 / 1.15 大

  // ---------------------------------------------------------------- 读取
  Future<void> load() async {
    final db = await AppDb.I.db;
    courses = (await db.query('courses', orderBy: 'weekday ASC, start_min ASC'))
        .map(Course.fromMap)
        .toList();
    tasks = (await db.query('tasks', orderBy: 'done ASC, due_at ASC')).map(TaskItem.fromMap).toList();
    notes = (await db.query('notes', orderBy: 'pinned DESC, updated_at DESC')).map(NoteItem.fromMap).toList();
    focusSessions = (await db.query('focus_sessions', orderBy: 'start_at DESC')).map(FocusSession.fromMap).toList();
    folders = (await db.query('folders', orderBy: 'name ASC')).map(Folder.fromMap).toList();
    competitions =
        (await db.query('competitions', orderBy: 'start_at ASC')).map(Competition.fromMap).toList();
    notices = (await db.query('notices', orderBy: 'pinned DESC, created_at DESC')).map(NoticeItem.fromMap).toList();
    ideas = (await db.query('ideas', orderBy: 'pinned DESC, updated_at DESC')).map(IdeaItem.fromMap).toList();
    resources =
        (await db.query('resources', orderBy: 'created_at DESC')).map(ResourceItem.fromMap).toList();
    taskComments =
        (await db.query('task_comments', orderBy: 'created_at DESC')).map(TaskComment.fromMap).toList();
    exams = (await db.query('exams', orderBy: 'start_at ASC')).map(Exam.fromMap).toList();
    grades = (await db.query('grades', orderBy: 'course_name ASC')).map(Grade.fromMap).toList();
    attachments = (await db.query('attachments', orderBy: 'created_at ASC')).map(AttachmentItem.fromMap).toList();
    final revRows = await db.query('reviews', orderBy: 'date_key DESC');
    reviews = <String, ReviewItem>{};
    for (final row in revRows) {
      final item = ReviewItem.fromMap(row);
      reviews[item.dateKey] = item;
    }
    final settingRows = await db.query('settings', where: 'key = ?', whereArgs: ['term_start']);
    if (settingRows.isEmpty) {
      termStart = _defaultTermStart();
      await db.insert('settings', {'key': 'term_start', 'value': termStart},
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      termStart = (settingRows.first['value'] as String?) ?? _defaultTermStart();
    }
    final allSettings = await db.query('settings');
    for (final row in allSettings) {
      final key = row['key'] as String?;
      final value = row['value'] as String?;
      if (key == 'theme_seed' && value != null) {
        themeSeed = int.tryParse(value) ?? kDefaultSeed.value;
      } else if (key == 'dark_mode' && value != null) {
        darkMode = value == '1';
      } else if (key == 'font_scale' && value != null) {
        fontScale = double.tryParse(value) ?? 1.0;
      }
    }
    ready = true;
    notifyListeners();
    syncSideEffects();
  }

  String _defaultTermStart() {
    final now = dateOnly(DateTime.now());
    return fmtDate(now.subtract(Duration(days: now.weekday - 1)));
  }

  Future<void> setTermStart(DateTime monday) async {
    termStart = fmtDate(dateOnly(monday));
    final db = await AppDb.I.db;
    await db.insert('settings', {'key': 'term_start', 'value': termStart},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
    syncSideEffects();
  }

  Future<void> _saveSetting(String key, String value) async {
    final db = await AppDb.I.db;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setThemeSeed(Color color) async {
    themeSeed = color.value;
    await _saveSetting('theme_seed', '$themeSeed');
    notifyListeners();
  }

  Future<void> setDarkMode(bool on) async {
    darkMode = on;
    await _saveSetting('dark_mode', on ? '1' : '0');
    notifyListeners();
  }

  Future<void> setFontScale(double scale) async {
    fontScale = scale;
    await _saveSetting('font_scale', '$scale');
    notifyListeners();
  }

  int get currentWeek => weekOf(DateTime.now());

  int weekOf(DateTime day) {
    final start = termStart.isEmpty ? null : DateTime.tryParse(termStart);
    if (start == null) return 1;
    final diff = dateOnly(day).difference(dateOnly(start)).inDays;
    final w = (diff / 7).floor() + 1;
    return w < 1 ? 1 : w;
  }

  List<Course> coursesOfDay(int weekday, {int? week}) {
    final w = week ?? currentWeek;
    final list = courses
        .where((c) => c.weekday == weekday && w >= c.weekStart && w <= c.weekEnd)
        .toList()
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    return list;
  }

  Course? courseById(int? id) {
    if (id == null) return null;
    for (final c in courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 未完成，按截止时间升序（无截止的排后面）
  List<TaskItem> get pending {
    final list = tasks.where((t) => !t.done).toList()
      ..sort((a, b) {
        final ad = a.dueAt?.millisecondsSinceEpoch ?? 1 << 62;
        final bd = b.dueAt?.millisecondsSinceEpoch ?? 1 << 62;
        return ad.compareTo(bd);
      });
    return list;
  }

  List<TaskItem> get pendingForToday {
    final end = dateOnly(DateTime.now()).add(const Duration(days: 1));
    return pending.where((t) => t.dueAt == null || dateOnly(t.dueAt!).isBefore(end)).toList();
  }

  int get overdueCount {
    return tasks.where((t) => !t.done && isOverdueAt(t.dueAt)).length;
  }

  // ---------------------------------------------------------------- 写入
  Future<void> saveCourse(Course c) async {
    final db = await AppDb.I.db;
    if (c.id == null) {
      await db.insert('courses', c.toMap());
    } else {
      await db.update('courses', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    }
    await load();
  }

  Future<void> deleteCourse(int id) async {
    final db = await AppDb.I.db;
    await db.delete('courses', where: 'id = ?', whereArgs: [id]);
    await db.update('tasks', {'course_id': null}, where: 'course_id = ?', whereArgs: [id]);
    await load();
  }

  Future<int> saveTask(TaskItem t) async {
    final db = await AppDb.I.db;
    int id;
    if (t.id == null) {
      id = await db.insert('tasks', t.toMap());
    } else {
      await db.update('tasks', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
      id = t.id!;
    }
    await load();
    return id;
  }

  Future<void> toggleTask(TaskItem t) async {
    final db = await AppDb.I.db;
    await db.update('tasks', {'done': t.done ? 0 : 1}, where: 'id = ?', whereArgs: [t.id]);
    await load();
  }

  Future<void> deleteTask(int id) async {
    final db = await AppDb.I.db;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
    await db.delete('task_comments', where: 'task_id = ?', whereArgs: [id]);
    await load();
  }

  Future<int> saveNote(NoteItem n) async {
    final db = await AppDb.I.db;
    int id;
    if (n.id == null) {
      id = await db.insert('notes', n.toMap());
    } else {
      await db.update('notes', n.toMap(), where: 'id = ?', whereArgs: [n.id]);
      id = n.id!;
    }
    await load();
    return id;
  }

  Future<void> deleteNote(int id) async {
    final db = await AppDb.I.db;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  // ---------------------------------------------------------------- 灵感 / 痛点 / 想法
  int get ideaCount => ideas.length;

  int ideaCountOf(IdeaKind kind) => ideas.where((e) => e.kind == kind).length;

  Future<int> saveIdea(IdeaItem item) async {
    final db = await AppDb.I.db;
    int id;
    if (item.id == null) {
      id = await db.insert('ideas', item.toMap());
    } else {
      await db.update('ideas', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
      id = item.id!;
    }
    await load();
    return id;
  }

  Future<void> deleteIdea(int id) async {
    final db = await AppDb.I.db;
    await db.delete('ideas', where: 'id = ?', whereArgs: [id]);
    await db.delete('attachments', where: 'owner_type = ? AND owner_id = ?', whereArgs: ['idea', id]);
    await load();
  }

  Future<void> toggleIdeaPin(IdeaItem item) async {
    final db = await AppDb.I.db;
    await db.update('ideas', {'pinned': item.pinned ? 0 : 1}, where: 'id = ?', whereArgs: [item.id]);
    await load();
  }

  // ---------------------------------------------------------------- 资源库
  /// 按多级分类逐级筛选
  List<ResourceItem> resourcesFiltered({
    ResourceSource? source,
    ResourceDomain? domain,
    String? subject,
  }) {
    return resources.where((r) {
      if (source != null && r.source != source) return false;
      if (domain != null && r.domain != domain) return false;
      if (subject != null && subject.isNotEmpty && r.subject != subject) return false;
      return true;
    }).toList();
  }

  /// 当前筛选下还有哪些科目可选（供下一级 chips）
  List<String> resourceSubjects({
    ResourceSource? source,
    ResourceDomain? domain,
  }) {
    final set = <String>{};
    for (final r in resources) {
      if (source != null && r.source != source) continue;
      if (domain != null && r.domain != domain) continue;
      if (r.subject.trim().isNotEmpty) set.add(r.subject.trim());
    }
    return set.toList()..sort();
  }

  Future<int> saveResource(ResourceItem r) async {
    final db = await AppDb.I.db;
    int id;
    if (r.id == null) {
      id = await db.insert('resources', r.toMap());
    } else {
      await db.update('resources', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
      id = r.id!;
    }
    await load();
    return id;
  }

  Future<void> deleteResource(int id) async {
    final db = await AppDb.I.db;
    await db.delete('resources', where: 'id = ?', whereArgs: [id]);
    await db.delete('attachments', where: 'owner_type = ? AND owner_id = ?', whereArgs: ['resource', id]);
    await load();
  }

  // ---------------------------------------------------------------- 考试 & 成绩
  /// 未来（未结束）的考试，按时间升序
  List<Exam> get upcomingExams {
    final now = DateTime.now();
    final list = exams.where((e) => !e.isOver).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return list;
  }

  /// 最近一场还没开始的考试
  Exam? get nextExam {
    final now = DateTime.now();
    for (final e in upcomingExams) {
      if (e.startAt.isAfter(now)) return e;
    }
    return null;
  }

  Future<int> saveExam(Exam e) async {
    final db = await AppDb.I.db;
    int id;
    if (e.id == null) {
      id = await db.insert('exams', e.toMap());
    } else {
      await db.update('exams', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
      id = e.id!;
    }
    await load();
    syncSideEffects();
    return id;
  }

  Future<void> deleteExam(int id) async {
    final db = await AppDb.I.db;
    await db.delete('exams', where: 'id = ?', whereArgs: [id]);
    await db.delete('attachments', where: 'owner_type = ? AND owner_id = ?', whereArgs: ['exam', id]);
    await load();
    syncSideEffects();
  }

  /// 加权平均绩点 / 加权平均分 / 总学分（只算有成绩的课）
  ({double? gpa, double? avgScore, double credits, int counted}) get gpaStats {
    final scored = grades.where((g) => g.gpaValue != null && g.credit > 0).toList();
    if (scored.isEmpty) return (gpa: null, avgScore: null, credits: 0, counted: 0);
    double wSum = 0, gpSum = 0, sSum = 0, cSum = 0;
    for (final g in scored) {
      wSum += g.credit;
      gpSum += g.credit * g.gpaValue!;
      if (g.score != null) sSum += g.credit * g.score!;
      cSum += g.credit;
    }
    return (
      gpa: wSum == 0 ? null : gpSum / wSum,
      avgScore: cSum == 0 ? null : sSum / cSum,
      credits: wSum,
      counted: scored.length,
    );
  }

  Future<int> saveGrade(Grade g) async {
    final db = await AppDb.I.db;
    int id;
    if (g.id == null) {
      id = await db.insert('grades', g.toMap());
    } else {
      await db.update('grades', g.toMap(), where: 'id = ?', whereArgs: [g.id]);
      id = g.id!;
    }
    await load();
    return id;
  }

  Future<void> deleteGrade(int id) async {
    final db = await AppDb.I.db;
    await db.delete('grades', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  /// 从内置种子（assets/timetable_seed.json）导入课表。
  /// 同名 + 同星期 且时间有重叠的现有课程视为重复，跳过。
  Future<({int added, int skipped})> importSeedCourses(List<dynamic> seed) async {
    final db = await AppDb.I.db;
    int added = 0, skipped = 0;
    for (final raw in seed) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final wd = (raw['weekday'] as num?)?.toInt() ?? 1;
      final sm = (raw['startMin'] as num?)?.toInt() ?? 480;
      final em = (raw['endMin'] as num?)?.toInt() ?? 570;
      final dup = courses.any((c) =>
          c.name == name && c.weekday == wd && sm < c.endMin && c.startMin < em);
      if (dup) {
        skipped++;
        continue;
      }
      final color = int.tryParse((raw['color'] as String?) ?? '') ?? 0xFF4C6FFF;
      await db.insert('courses', {
        'name': name,
        'teacher': (raw['teacher'] as String?) ?? '',
        'location': (raw['location'] as String?) ?? '',
        'weekday': wd,
        'start_min': sm,
        'end_min': em,
        'week_start': (raw['weekStart'] as num?)?.toInt() ?? 1,
        'week_end': (raw['weekEnd'] as num?)?.toInt() ?? 16,
        'color': color,
        'remind': (raw['remind'] as String?) ?? '30,15',
        'note': '',
        'teacher_note': '',
        'links': '',
      });
      added++;
    }
    await load();
    syncSideEffects();
    return (added: added, skipped: skipped);
  }

  // ---------------------------------------------------------------- 作业点评
  List<TaskComment> commentsOf(int taskId) =>
      taskComments.where((c) => c.taskId == taskId).toList();

  Future<int> saveTaskComment(TaskComment c) async {
    final db = await AppDb.I.db;
    int id;
    if (c.id == null) {
      id = await db.insert('task_comments', c.toMap());
    } else {
      await db.update('task_comments', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
      id = c.id!;
    }
    await load();
    return id;
  }

  Future<void> deleteTaskComment(int id) async {
    final db = await AppDb.I.db;
    await db.delete('task_comments', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  Future<void> saveReview(ReviewItem r) async {
    final db = await AppDb.I.db;
    await db.rawInsert(
      'INSERT OR REPLACE INTO reviews(id, date_key, done_text, blocker_text, tomorrow_text, mood, created_at) '
      'VALUES(?,?,?,?,?,?,?)',
      [r.id, r.dateKey, r.doneText, r.blockerText, r.tomorrowText, r.mood, r.createdAt.millisecondsSinceEpoch],
    );
    await load();
  }

  ReviewItem? reviewOf(String dateKey) => reviews[dateKey];

  // ---------------------------------------------------------------- 专注计时
  FocusSession? get runningFocus {
    for (final s in focusSessions) {
      if (s.running) return s;
    }
    return null;
  }

  Future<void> startFocus(TaskType type, {int? taskId, String taskTitle = ''}) async {
    if (runningFocus != null) return;
    final db = await AppDb.I.db;
    await db.insert('focus_sessions', {
      'type': type.code,
      'task_id': taskId,
      'task_title': taskTitle,
      'start_at': DateTime.now().millisecondsSinceEpoch,
      'end_at': null,
    });
    await load();
  }

  /// 结束计时并保存；不足 1 分钟的记录直接丢弃，避免误点。
  Future<void> stopFocus({bool discardShort = true}) async {
    final r = runningFocus;
    if (r == null) return;
    final db = await AppDb.I.db;
    if (discardShort && r.seconds < 60) {
      await db.delete('focus_sessions', where: 'id = ?', whereArgs: [r.id]);
    } else {
      await db.update(
        'focus_sessions',
        {'end_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [r.id],
      );
    }
    await load();
  }

  Future<void> deleteFocus(int id) async {
    final db = await AppDb.I.db;
    await db.delete('focus_sessions', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  /// 某天的专注秒数（含进行中的那一次）
  int focusSecondsOfDay(DateTime day) {
    final d = dateOnly(day);
    var total = 0;
    for (final s in focusSessions) {
      if (dateOnly(s.startAt) == d) total += s.seconds;
    }
    return total;
  }

  int get todayFocusSeconds => focusSecondsOfDay(DateTime.now());

  int get weekFocusSeconds {
    final now = DateTime.now();
    final monday = dateOnly(now).subtract(Duration(days: now.weekday - 1));
    var total = 0;
    for (final s in focusSessions) {
      if (!dateOnly(s.startAt).isBefore(monday)) total += s.seconds;
    }
    return total;
  }

  Map<TaskType, int> get todayFocusByType {
    final d = dateOnly(DateTime.now());
    final map = <TaskType, int>{};
    for (final s in focusSessions) {
      if (dateOnly(s.startAt) != d) continue;
      map[s.type] = (map[s.type] ?? 0) + s.seconds;
    }
    return map;
  }

  // ---------------------------------------------------------------- 文件夹
  List<Folder> foldersOf(String scope, int? parentId) {
    final list = folders.where((f) => f.scope == scope && f.parentId == parentId).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Folder? folderById(int? id) {
    if (id == null) return null;
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// 从根到该文件夹的路径（用于面包屑）
  List<Folder> folderPath(int? id) {
    final out = <Folder>[];
    var cur = folderById(id);
    var guard = 0;
    while (cur != null && guard < 32) {
      out.insert(0, cur);
      cur = folderById(cur.parentId);
      guard++;
    }
    return out;
  }

  Future<int> createFolder(String name, String scope, int? parentId) async {
    final db = await AppDb.I.db;
    final id = await db.insert('folders', {
      'name': name,
      'parent_id': parentId,
      'scope': scope,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await load();
    return id;
  }

  Future<void> renameFolder(int id, String name) async {
    final db = await AppDb.I.db;
    await db.update('folders', {'name': name}, where: 'id = ?', whereArgs: [id]);
    await load();
  }

  /// 删除文件夹：子文件夹与其中内容上移到父级，不连带删除数据
  Future<void> deleteFolder(int id) async {
    final db = await AppDb.I.db;
    final folder = folderById(id);
    final parent = folder?.parentId;
    await db.update('folders', {'parent_id': parent}, where: 'parent_id = ?', whereArgs: [id]);
    if (folder?.scope == 'note') {
      await db.update('notes', {'folder_id': parent}, where: 'folder_id = ?', whereArgs: [id]);
    } else if (folder?.scope == 'idea') {
      await db.update('ideas', {'folder_id': parent}, where: 'folder_id = ?', whereArgs: [id]);
    } else {
      await db.update('tasks', {'folder_id': parent}, where: 'folder_id = ?', whereArgs: [id]);
    }
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  int folderItemCount(Folder f) {
    final subCount = folders.where((x) => x.scope == f.scope && x.parentId == f.id).length;
    if (f.scope == 'note') {
      return notes.where((n) => n.folderId == f.id).length + subCount;
    }
    if (f.scope == 'idea') {
      return ideas.where((n) => n.folderId == f.id).length + subCount;
    }
    return tasks.where((t) => t.folderId == f.id && !t.done).length + subCount;
  }

  // ---------------------------------------------------------------- 附件
  List<AttachmentItem> attachmentsOf(String ownerType, int? ownerId) {
    if (ownerId == null) return const [];
    return attachments.where((a) => a.ownerType == ownerType && a.ownerId == ownerId).toList();
  }

  /// 先把文件复制进 App 私有目录（新建条目还没 id 时用），返回待入库的附件
  Future<AttachmentItem?> stageAttachment(String ownerType, String srcPath, String name) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final dest = p.join(dir.path, 'attachments', '${ownerType}_${stamp}_$safeName');
      await Directory(p.dirname(dest)).create(recursive: true);
      final copied = await File(srcPath).copy(dest);
      final size = await copied.length();
      return AttachmentItem(
        ownerType: ownerType,
        ownerId: 0,
        name: name,
        path: dest,
        size: size,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('附件复制失败: $e');
      return null;
    }
  }

  Future<AttachmentItem?> importAttachment(String ownerType, int ownerId, String srcPath, String name) async {
    final staged = await stageAttachment(ownerType, srcPath, name);
    if (staged == null) return null;
    final db = await AppDb.I.db;
    final id = await db.insert('attachments', {
      'owner_type': ownerType,
      'owner_id': ownerId,
      'name': staged.name,
      'path': staged.path,
      'size': staged.size,
      'created_at': staged.createdAt.millisecondsSinceEpoch,
    });
    await load();
    return AttachmentItem(
      id: id,
      ownerType: ownerType,
      ownerId: ownerId,
      name: staged.name,
      path: staged.path,
      size: staged.size,
      createdAt: staged.createdAt,
    );
  }

  Future<void> deleteAttachment(AttachmentItem a) async {
    final db = await AppDb.I.db;
    if (a.id != null) {
      await db.delete('attachments', where: 'id = ?', whereArgs: [a.id]);
    }
    try {
      final f = File(a.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await load();
  }

  /// 把「新条目还没保存时先选好的附件」落到数据库
  Future<void> attachPending(String ownerType, int ownerId, List<AttachmentItem> pending) async {
    for (final a in pending) {
      final db = await AppDb.I.db;
      await db.insert('attachments', {
        'owner_type': ownerType,
        'owner_id': ownerId,
        'name': a.name,
        'path': a.path,
        'size': a.size,
        'created_at': a.createdAt.millisecondsSinceEpoch,
      });
    }
    await load();
  }

  // ---------------------------------------------------------------- 比赛
  List<Competition> get upcomingCompetitions {
    final list = competitions.where((c) => !c.ended && !c.isPast).toList()
      ..sort((a, b) {
        final ad = (a.startAt ?? a.signupDeadline)?.millisecondsSinceEpoch ?? (1 << 62);
        final bd = (b.startAt ?? b.signupDeadline)?.millisecondsSinceEpoch ?? (1 << 62);
        return ad.compareTo(bd);
      });
    return list;
  }

  /// 参加过的比赛（含往年补录），按时间倒序
  List<Competition> get pastCompetitions {
    final list = competitions.where((c) => c.isPast).toList()
      ..sort((a, b) {
        final ad = (a.resultAt ?? a.endAt ?? a.startAt)?.millisecondsSinceEpoch ?? 0;
        final bd = (b.resultAt ?? b.endAt ?? b.startAt)?.millisecondsSinceEpoch ?? 0;
        return bd.compareTo(ad);
      });
    return list;
  }

  /// 获奖统计：{first: 1, second: 2, ...}
  Map<String, int> get compResultStats {
    final map = <String, int>{};
    for (final c in competitions) {
      if (!c.isPast) continue;
      map[c.resultRank] = (map[c.resultRank] ?? 0) + 1;
    }
    return map;
  }

  int get awardedCount => competitions.where((c) => c.awarded).length;
  int get pastCompCount => competitions.where((c) => c.isPast).length;

  List<TaskItem> prepTasksOf(int compId) =>
      tasks.where((t) => t.compId == compId).toList()..sort((a, b) => (a.done ? 1 : 0).compareTo(b.done ? 1 : 0));

  Future<int> saveCompetition(Competition c) async {
    final db = await AppDb.I.db;
    if (c.id == null) {
      final id = await db.insert('competitions', c.toMap());
      await load();
      return id;
    }
    await db.update('competitions', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    await load();
    return c.id!;
  }

  Future<void> deleteCompetition(int id) async {
    final db = await AppDb.I.db;
    await db.delete('competitions', where: 'id = ?', whereArgs: [id]);
    await db.update('tasks', {'comp_id': null}, where: 'comp_id = ?', whereArgs: [id]);
    await db.delete('attachments', where: 'owner_type = ? AND owner_id = ?', whereArgs: ['comp', id]);
    await load();
  }

  // ---------------------------------------------------------------- 通知
  int get unreadNoticeCount => notices.where((n) => !n.read).length;

  /// 最近一个还没到截止时间的通知（首页用来提示「最近截止」）
  NoticeItem? get nextDeadlineNotice {
    final now = DateTime.now();
    NoticeItem? best;
    for (final n in notices) {
      final d = n.deadlineAt;
      if (d == null) continue;
      if (now.isAfter(d.add(const Duration(seconds: 1)))) continue;
      if (best == null || d.isBefore(best.deadlineAt!)) best = n;
    }
    return best;
  }

  /// 重要 / 紧急且 3 天内截止的通知条数
  int get urgentNoticeDueCount {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 3));
    return notices.where((n) {
      final d = n.deadlineAt;
      if (d == null || n.importance < 1) return false;
      return d.isAfter(now) && d.isBefore(limit);
    }).length;
  }

  Future<int> saveNotice(NoticeItem n) async {
    final db = await AppDb.I.db;
    if (n.id == null) {
      final id = await db.insert('notices', n.toMap());
      await load();
      syncSideEffects();
      return id;
    }
    await db.update('notices', n.toMap(), where: 'id = ?', whereArgs: [n.id]);
    await load();
    syncSideEffects();
    return n.id!;
  }

  Future<void> deleteNotice(int id) async {
    final db = await AppDb.I.db;
    await db.delete('notices', where: 'id = ?', whereArgs: [id]);
    await db.delete('attachments', where: 'owner_type = ? AND owner_id = ?', whereArgs: ['notice', id]);
    await load();
    syncSideEffects();
  }

  Future<void> markNoticeRead(int id, bool read) async {
    final db = await AppDb.I.db;
    await db.update('notices', {'read': read ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    await load();
  }

  Future<void> toggleNoticePin(NoticeItem n) async {
    final db = await AppDb.I.db;
    await db.update('notices', {'pinned': n.pinned ? 0 : 1}, where: 'id = ?', whereArgs: [n.id]);
    await load();
  }

  // ---------------------------------------------------------------- 通知
  Future<void> rescheduleAll() async {
    if (!NotificationService.supported) return;
    await NotificationService.cancelAll();
    final now = DateTime.now();
    final today = dateOnly(now);

    // 课程：未来 22 天的每一次课，按每门课设置的多个提前量分别提醒
    for (final c in courses) {
      final cid = c.id ?? 0;
      final offsets = c.remindList;
      final hasTeacherNote = c.teacherNote.trim().isNotEmpty;
      if (offsets.isEmpty && !hasTeacherNote) continue;
      for (var i = 0; i <= 21; i++) {
        final day = today.add(Duration(days: i));
        if (day.weekday != c.weekday) continue;
        final w = weekOf(day);
        if (w < c.weekStart || w > c.weekEnd) continue;
        final start = DateTime(day.year, day.month, day.day, c.startMin ~/ 60, c.startMin % 60);
        for (var k = 0; k < offsets.length && k < 6; k++) {
          final remindAt = start.subtract(Duration(minutes: offsets[k]));
          if (remindAt.isBefore(now)) continue;
          final title = offsets[k] == 0
              ? '现在上课：${c.name}'
              : '${untilLabel(offsets[k])}上课：${c.name}';
          await NotificationService.scheduleAt(
            remindAt,
            title,
            '${hhmm(c.startMin)}-${hhmm(c.endMin)}${c.location.isEmpty ? '' : ' · ${c.location}'}',
            200000 + cid * 1000 + i * 10 + k,
            payload: 'course:$cid',
          );
        }
        // 老师提醒：与上课提醒同档位同步推送，内容是老师说要干嘛
        if (hasTeacherNote) {
          for (var k = 0; k < offsets.length && k < 6; k++) {
            final remindAt = start.subtract(Duration(minutes: offsets[k]));
            if (remindAt.isBefore(now)) continue;
            final title = offsets[k] == 0
                ? '【老师提醒】现在上课：${c.name}'
                : '【老师提醒】${untilLabel(offsets[k])}上课：${c.name}';
            await NotificationService.scheduleAt(
              remindAt,
              title,
              c.teacherNote.trim(),
              400000 + cid * 1000 + i * 10 + k,
              payload: 'course:$cid',
            );
          }
        }
      }
    }

    // 考试：按每场考试设置的提前量提醒（默认 1 天前 / 1 小时前）
    for (final e in exams) {
      if (e.isOver) continue;
      final eid = e.id ?? 0;
      final offsets = e.remindList;
      for (var k = 0; k < offsets.length && k < 6; k++) {
        final when = e.startAt.subtract(Duration(minutes: offsets[k]));
        if (when.isBefore(now)) continue;
        final title = offsets[k] == 0
            ? '马上开考：${e.name}'
            : '${offsetLabel(offsets[k])}考试：${e.name}';
        final body = [
          if (e.courseName.isNotEmpty) e.courseName,
          fmtDateTime(e.startAt),
          if (e.location.isNotEmpty) e.location,
          if (e.seat.isNotEmpty) '座位 ${e.seat}',
        ].join(' · ');
        await NotificationService.scheduleAt(when, title, body, 500000 + eid * 10 + k,
            payload: 'exam:$eid');
      }
    }

    // 作业 / 自习 / 工作：按截止时间（或开始时间）提前提醒
    for (final t in tasks) {
      if (t.done) continue;
      final base = t.dueAt ?? t.startAt ?? t.endAt;
      if (base == null) continue;
      final tid = t.id ?? 0;
      final offsets = t.remindList;
      for (var k = 0; k < offsets.length && k < 9; k++) {
        final when = base.subtract(Duration(minutes: offsets[k]));
        if (when.isBefore(now)) continue;
        final title = offsets[k] == 0 ? '截止提醒：${t.title}' : '${offsetLabel(offsets[k])}：${t.title}';
        final body = t.dueAt == null
            ? '${t.type.label} · ${fmtDateTime(base)}'
            : '${t.type.label} · 截止 ${fmtDateTime(t.dueAt)}';
        await NotificationService.scheduleAt(when, title, body, 100000 + tid * 10 + k, payload: 'task:$tid');
      }
      // 自定义提醒时间点（用户指定的具体时刻，与提前量无关）
      final customs = t.customRemindList;
      for (var k = 0; k < customs.length && k < 4; k++) {
        final when = customs[k];
        if (when.isBefore(now)) continue;
        await NotificationService.scheduleAt(
          when,
          '定时提醒：${t.title}',
          '${t.type.label} · ${fmtDateTime(when)}${t.dueAt == null ? '' : ' · 截止 ${fmtDateTime(t.dueAt)}'}',
          150000 + tid * 10 + k,
          payload: 'task:$tid',
        );
      }
    }

    // 通知：重要 / 紧急的通知在截止前多档提醒（1 天前、2 小时前…）
    for (final n in notices) {
      final dl = n.deadlineAt;
      if (dl == null) continue;
      if (now.isAfter(dl.add(const Duration(seconds: 1)))) continue;
      final nid = n.id ?? 0;
      final imp = importanceFromCode(n.importance);
      final offsets = n.remindList;
      final point = n.keyPointList;
      for (var k = 0; k < offsets.length && k < 9; k++) {
        final when = dl.subtract(Duration(minutes: offsets[k]));
        if (when.isBefore(now)) continue;
        final title = offsets[k] == 0
            ? (imp == Importance.normal ? '截止提醒：${n.title}' : '【${imp.label}】今天截止：${n.title}')
            : '${offsetLabel(offsets[k])}截止：${n.title}';
        final body = [
          n.source,
          imp.label,
          '截止 ${fmtDateTime(dl)}',
          if (point.isNotEmpty) point.first,
        ].join(' · ');
        await NotificationService.scheduleAt(when, title, body, 600000 + nid * 10 + k, payload: 'notice:$nid');
      }
    }

    // 比赛：报名截止 + 开始前，按重要程度给不同密度的提醒
    for (final c in competitions) {
      if (c.ended || c.isPast) continue;
      final cid = c.id ?? 0;
      final imp = c.level_;
      final signupOffsets = switch (imp) {
        Importance.normal => const [1440],
        Importance.important => const [2880, 1440],
        Importance.urgent => const [4320, 2880, 1440],
      };
      final startOffsets = switch (imp) {
        Importance.normal => const [1440, 60, 0],
        Importance.important => const [2880, 1440, 120, 60, 0],
        Importance.urgent => const [4320, 2880, 1440, 360, 120, 30, 0],
      };
      final spots = <DateTime, String>{};
      if (c.signupDeadline != null) {
        for (final m in signupOffsets) {
          spots[c.signupDeadline!.subtract(Duration(minutes: m))] =
              m == 1440 ? '明天报名截止：${c.name}' : '${offsetLabel(m)}报名截止：${c.name}';
        }
      }
      if (c.startAt != null) {
        for (final m in startOffsets) {
          spots[c.startAt!.subtract(Duration(minutes: m))] = switch (m) {
            0 => '现在开始：${c.name}（${c.stage}）',
            1440 => '明天比赛：${c.name}（${c.stage}）',
            60 => '1 小时后开始：${c.name}（${c.stage}）',
            _ => '${offsetLabel(m)}开赛：${c.name}（${c.stage}）',
          };
        }
      }
      var k = 0;
      for (final e in spots.entries) {
        k++;
        if (e.key.isBefore(now)) continue;
        final body = [
          '${c.stage} · ${c.level}',
          if (c.location.isNotEmpty) c.location,
          if (c.endAt != null) '结束 ${fmtDateTime(c.endAt)}',
        ].join(' · ');
        await NotificationService.scheduleAt(
          e.key,
          e.value,
          body,
          300000 + cid * 100 + k,
          payload: 'comp:$cid',
        );
      }
    }
  }

  Future<void> sendTestNotification() async {
    await NotificationService.requestPermissions();
    await NotificationService.scheduleAt(
      DateTime.now().add(const Duration(seconds: 5)),
      '测试提醒 ✅',
      '如果你看到这条通知，说明通知链路是通的。',
      999999,
    );
  }

  // ---------------------------------------------------------------- 小组件
  /// 小组件要显示的四段文字（引导页预览也用它，保证和桌面一致）
  Map<String, String> get widgetTexts {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final cs = coursesOfDay(now.weekday);
    final footer = '更新于 ${hhmmOf(now)} · 打开 App 自动刷新';

    final courseBody = cs.isEmpty
        ? '今天没有课，安排点自己的事吧'
        : cs
            .map((c) =>
                '${hhmm(c.startMin)}-${hhmm(c.endMin)}  ${c.name}${c.location.isEmpty ? '' : '  @${c.location}'}')
            .join('\n');

    final p = pending.take(5).toList();
    final taskBody = p.isEmpty
        ? '暂无未完成待办 🎉'
        : p
            .map((t) => t.dueAt == null
                ? '· ${t.title}'
                : '· ${t.title}  ${friendlyDay(t.dueAt!)} ${hhmmOf(t.dueAt!)}')
            .join('\n');

    // ---- 今日概览
    Course? next;
    for (final c in cs) {
      if (c.endMin > nowMin) {
        next = c;
        break;
      }
    }
    final ups = upcomingCompetitions.take(3).toList();
    final overview = <String>[
      '今天 ${cs.length} 节课 · 待办 ${pending.length} 项',
      if (next != null)
        '下一节 ${hhmm(next.startMin)} ${next.name}${next.location.isEmpty ? '' : ' @${next.location}'}'
      else if (cs.isNotEmpty)
        '今天的课已经上完了',
      if (ups.isNotEmpty && (ups.first.startAt ?? ups.first.signupDeadline) != null)
        '比赛 ${ups.first.name} · ${leftText((ups.first.startAt ?? ups.first.signupDeadline)!)}',
      '今日专注 ${_hm(todayFocusSeconds)}',
    ];

    // ---- 比赛提醒
    String compTitle;
    String compBody;
    if (ups.isNotEmpty) {
      compTitle = '比赛提醒 · ${upcomingCompetitions.length} 场待参加';
      compBody = ups
          .map((c) {
            final anchor = c.startAt ?? c.signupDeadline;
            final tail = anchor == null ? '' : ' · ${leftText(anchor)}';
            return '· ${c.name}（${c.stage}）$tail';
          })
          .join('\n');
    } else {
      compTitle = '比赛战绩 · 参加过 $pastCompCount 场';
      final wins = kCompResultCodes
          .where((k) => k != 'pending' && (compResultStats[k] ?? 0) > 0)
          .map((k) => '${compResultLabel(k)} ${compResultStats[k]}')
          .join(' · ');
      compBody = pastCompCount == 0
          ? '还没有记录比赛，去「比赛」里加一场'
          : '获奖 $awardedCount 场${wins.isEmpty ? '' : '\n$wins'}';
    }

    // ---- 灵感记录
    final recentIdeas = ideas.take(4).toList();
    final ideaBody = recentIdeas.isEmpty
        ? '还没有记录，去「记录 → 灵感」随手写一条'
        : recentIdeas
            .map((i) => '· [${i.kind.label}] ${_ellipsis(i.title, 14)}')
            .join('\n');
    final ideaTitle = '灵感记录 · 共 ${ideas.length} 条';

    // ---- 专注统计
    final running = runningFocus;
    final focusBody = <String>[
      if (running != null) '正在进行：${running.label}',
      '今日 ${_hm(todayFocusSeconds)} · ${focusSessions.where((s) => dateOnly(s.startAt) == dateOnly(now)).length} 段',
      '本周 ${_hm(weekFocusSeconds)}',
    ].join('\n');

    return {
      'course_title': '今日课程 · ${fmtMd(now)} ${weekdayLabel(now.weekday)}',
      'course_body': courseBody,
      'task_title': '待办提醒 · ${pending.length} 项未完成',
      'task_body': taskBody,
      'overview_title': '今日概览 · ${fmtMd(now)} ${weekdayLabel(now.weekday)}',
      'overview_body': overview.join('\n'),
      'comp_title': compTitle,
      'comp_body': compBody,
      'idea_title': ideaTitle,
      'idea_body': ideaBody,
      'focus_title': '专注统计 · 今日 ${_hm(todayFocusSeconds)}',
      'focus_body': focusBody,
      'widget_footer': footer,
    };
  }

  /// 结构化数据：原生小组件据此现算「正在上 / 下一节 / 还剩多久」，
  /// 不打开 App 也会随系统刷新更新（不再是写死的文本）。
  String get widgetPayload {
    final now = DateTime.now();
    final cs = coursesOfDay(now.weekday);
    final p = pending.take(8).toList();
    final ups = upcomingCompetitions.take(3).toList();
    final data = <String, Object?>{
      'updated': now.millisecondsSinceEpoch,
      'date': fmtMd(now),
      'weekday': weekdayLabel(now.weekday),
      'courses': [
        for (final c in cs) {'s': c.startMin, 'e': c.endMin, 'n': c.name, 'l': c.location},
      ],
      'tasks': [
        for (final t in p) {'t': t.title, 'd': t.dueAt?.millisecondsSinceEpoch},
      ],
      'taskCount': pending.length,
      'comps': [
        for (final c in ups)
          {'n': c.name, 'a': (c.startAt ?? c.signupDeadline)?.millisecondsSinceEpoch, 's': c.stage},
      ],
      'ideas': [
        for (final i in ideas.take(4)) {'k': i.kind.label, 't': i.title},
      ],
      'ideaCount': ideas.length,
      'focusToday': todayFocusSeconds,
      'focusWeek': weekFocusSeconds,
      'focusRunning': runningFocus?.label ?? '',
      'pastComp': pastCompCount,
      'awarded': awardedCount,
    };
    return jsonEncode(data);
  }

  Future<void> refreshWidgets() async {
    await WidgetService.update(widgetTexts, widgetPayload);
  }

  void syncSideEffects() {
    rescheduleAll().catchError((Object e) => debugPrint('reschedule error: $e'));
    refreshWidgets().catchError((Object e) => debugPrint('widget error: $e'));
  }

  // ---------------------------------------------------------------- 备份
  Future<String> exportBackup() async {
    final data = <String, Object?>{
      'app': 'class_reminder',
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'courses': courses.map((e) => e.toMap()).toList(),
      'tasks': tasks.map((e) => e.toMap()).toList(),
      'notes': notes.map((e) => e.toMap()).toList(),
      'reviews': reviews.values.map((e) => e.toMap()).toList(),
      'focus': focusSessions.map((e) => e.toMap()).toList(),
      'folders': folders.map((e) => e.toMap()).toList(),
      'competitions': competitions.map((e) => e.toMap()).toList(),
      'notices': notices.map((e) => e.toMap()).toList(),
      'ideas': ideas.map((e) => e.toMap()).toList(),
      'resources': resources.map((e) => e.toMap()).toList(),
      'task_comments': taskComments.map((e) => e.toMap()).toList(),
      'exams': exams.map((e) => e.toMap()).toList(),
      'grades': grades.map((e) => e.toMap()).toList(),
      'attachments': attachments.map((e) => e.toMap()).toList(),
      'settings': {
        'term_start': termStart,
        'theme_seed': '$themeSeed',
        'dark_mode': darkMode ? '1' : '0',
        'font_scale': '$fontScale',
      },
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> importBackup(String text) async {
    final dynamic decoded = jsonDecode(text.trim());
    if (decoded is! Map<String, dynamic>) throw '备份内容格式不对';
    if (decoded['app'] != 'class_reminder') throw '这不是本应用导出的备份';

    List<Map<String, Object?>> rows(dynamic v) {
      final out = <Map<String, Object?>>[];
      if (v is List) {
        for (final e in v) {
          if (e is Map) out.add(e.map((k, val) => MapEntry(k.toString(), val)));
        }
      }
      return out;
    }

    final db = await AppDb.I.db;
    await db.transaction((txn) async {
      await txn.delete('courses');
      await txn.delete('tasks');
      await txn.delete('notes');
      await txn.delete('reviews');
      await txn.delete('focus_sessions');
      await txn.delete('folders');
      await txn.delete('competitions');
      await txn.delete('notices');
      await txn.delete('ideas');
      await txn.delete('resources');
      await txn.delete('task_comments');
      await txn.delete('exams');
      await txn.delete('grades');
      await txn.delete('attachments');
      for (final m in rows(decoded['courses'])) {
        // 兼容旧备份/外部工具生成的 JSON：color 可能是 "0xFF..." 字符串
        final c = Map<String, Object?>.from(m);
        if (c['color'] is String) {
          c['color'] = int.tryParse(c['color'] as String) ?? 0xFF4C6FFF;
        }
        if (c['remind'] == null) c['remind'] = '30,15';
        await txn.insert('courses', c);
      }
      for (final m in rows(decoded['tasks'])) {
        await txn.insert('tasks', m);
      }
      for (final m in rows(decoded['notes'])) {
        await txn.insert('notes', m);
      }
      for (final m in rows(decoded['reviews'])) {
        await txn.insert('reviews', m);
      }
      for (final m in rows(decoded['focus'])) {
        await txn.insert('focus_sessions', m);
      }
      for (final m in rows(decoded['folders'])) {
        await txn.insert('folders', m);
      }
      for (final m in rows(decoded['competitions'])) {
        await txn.insert('competitions', m);
      }
      for (final m in rows(decoded['notices'])) {
        await txn.insert('notices', m);
      }
      for (final m in rows(decoded['ideas'])) {
        await txn.insert('ideas', m);
      }
      for (final m in rows(decoded['resources'])) {
        await txn.insert('resources', m);
      }
      for (final m in rows(decoded['task_comments'])) {
        await txn.insert('task_comments', m);
      }
      for (final m in rows(decoded['exams'])) {
        await txn.insert('exams', m);
      }
      for (final m in rows(decoded['grades'])) {
        await txn.insert('grades', m);
      }
      for (final m in rows(decoded['attachments'])) {
        await txn.insert('attachments', m);
      }
      final st = decoded['settings'];
      if (st is Map) {
        if (st['term_start'] is String) {
          await txn.insert('settings', {'key': 'term_start', 'value': st['term_start']},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final k in ['theme_seed', 'dark_mode', 'font_scale']) {
          if (st[k] != null) {
            await txn.insert('settings', {'key': k, 'value': '${st[k]}'},
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
    });
    await load();
  }
}

String _hm(int seconds) {
  if (seconds < 60) return '0 分钟';
  final m = seconds ~/ 60;
  if (m < 60) return '$m 分钟';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h 小时' : '$h 小时 $r 分';
}

String _ellipsis(String s, int max) {
  final t = s.replaceAll('\n', ' ').trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…';
}
