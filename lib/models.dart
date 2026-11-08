import 'package:flutter/material.dart';

/// 一条待办的三种形态：作业 / 自习计划 / 工作提醒
enum TaskType { homework, study, work }

TaskType taskTypeFromCode(String code) {
  if (code == 'study') return TaskType.study;
  if (code == 'work') return TaskType.work;
  return TaskType.homework;
}

extension TaskTypeX on TaskType {
  String get code {
    if (this == TaskType.study) return 'study';
    if (this == TaskType.work) return 'work';
    return 'homework';
  }

  String get label {
    if (this == TaskType.study) return '自习';
    if (this == TaskType.work) return '工作';
    return '作业';
  }

  Color get color {
    if (this == TaskType.study) return const Color(0xFF2B8A3E);
    if (this == TaskType.work) return const Color(0xFF1971C2);
    return const Color(0xFFE8590C);
  }

  IconData get icon {
    if (this == TaskType.study) return Icons.self_improvement;
    if (this == TaskType.work) return Icons.work_outline;
    return Icons.menu_book_outlined;
  }
}

class Course {
  final int? id;
  final String name;
  final String teacher;
  final String location;
  final int weekday; // 1=周一 ... 7=周日
  final int startMin; // 从 00:00 起的分钟数
  final int endMin;
  final int weekStart;
  final int weekEnd;
  final int color; // ARGB
  final String remind; // "30,15" 分钟前提醒，可多档
  final String note; // 课程备注（自己的）
  final String teacherNote; // 老师提醒要干嘛
  final String links; // 课程相关链接（一行一个）

  const Course({
    this.id,
    required this.name,
    this.teacher = '',
    this.location = '',
    required this.weekday,
    required this.startMin,
    required this.endMin,
    this.weekStart = 1,
    this.weekEnd = 16,
    this.color = 0xFF4C6FFF,
    this.remind = '30,15',
    this.note = '',
    this.teacherNote = '',
    this.links = '',
  });

  List<String> get linkList =>
      links.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  List<int> get remindList {
    final list = <int>[];
    for (final part in remind.split(',')) {
      final v = int.tryParse(part.trim());
      if (v != null && v >= 0) list.add(v);
    }
    return list;
  }

  Course copyWith({
    int? id,
    String? name,
    String? teacher,
    String? location,
    int? weekday,
    int? startMin,
    int? endMin,
    int? weekStart,
    int? weekEnd,
    int? color,
    String? remind,
    String? note,
    String? teacherNote,
    String? links,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      teacher: teacher ?? this.teacher,
      location: location ?? this.location,
      weekday: weekday ?? this.weekday,
      startMin: startMin ?? this.startMin,
      endMin: endMin ?? this.endMin,
      weekStart: weekStart ?? this.weekStart,
      weekEnd: weekEnd ?? this.weekEnd,
      color: color ?? this.color,
      remind: remind ?? this.remind,
      note: note ?? this.note,
      teacherNote: teacherNote ?? this.teacherNote,
      links: links ?? this.links,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'teacher': teacher,
        'location': location,
        'weekday': weekday,
        'start_min': startMin,
        'end_min': endMin,
        'week_start': weekStart,
        'week_end': weekEnd,
        'color': color,
        'remind': remind,
        'note': note,
        'teacher_note': teacherNote,
        'links': links,
      };

  factory Course.fromMap(Map<String, Object?> m) => Course(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        teacher: (m['teacher'] as String?) ?? '',
        location: (m['location'] as String?) ?? '',
        weekday: (m['weekday'] as int?) ?? 1,
        startMin: (m['start_min'] as int?) ?? 480,
        endMin: (m['end_min'] as int?) ?? 570,
        weekStart: (m['week_start'] as int?) ?? 1,
        weekEnd: (m['week_end'] as int?) ?? 16,
        color: (m['color'] as int?) ?? 0xFF4C6FFF,
        remind: (m['remind'] as String?) ?? '30,15',
        note: (m['note'] as String?) ?? '',
        teacherNote: (m['teacher_note'] as String?) ?? '',
        links: (m['links'] as String?) ?? '',
      );
}

class TaskItem {
  final int? id;
  final String title;
  final TaskType type;
  final int? courseId;
  final int? folderId;
  final int? compId;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? dueAt; // 截止时间
  final String remind; // "0,60,1440" 分钟前
  final bool done;
  final String note;
  final DateTime createdAt;

  /// 评价：老师打分、领导评语等
  final String score; // 可填 95 / A / 优
  final String reviewer; // 老师 / 领导 / 同学 / 自评 / 平台
  final String reviewNote; // 评语
  final DateTime? evaluatedAt;

  /// 总结 / 复盘
  final String summary;

  /// 提交方式：怎么交这份作业 / 工作（线上平台、纸质、发谁…）
  final String submitMethod;

  /// 相关链接（提交入口、参考资料），一行一个
  final String links;

  const TaskItem({
    this.id,
    required this.title,
    this.type = TaskType.homework,
    this.courseId,
    this.folderId,
    this.compId,
    this.startAt,
    this.endAt,
    this.dueAt,
    this.remind = '0,60,1440',
    this.done = false,
    this.note = '',
    required this.createdAt,
    this.score = '',
    this.reviewer = '',
    this.reviewNote = '',
    this.evaluatedAt,
    this.summary = '',
    this.submitMethod = '',
    this.links = '',
  });

  List<String> get linkList =>
      links.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  bool get hasSubmitMethod => submitMethod.trim().isNotEmpty;

  bool get hasEvaluation => score.isNotEmpty || reviewNote.isNotEmpty;
  bool get hasSummary => summary.trim().isNotEmpty;

  /// 「老师 95 分」这类展示文案
  String get evaluationText {
    final parts = <String>[
      if (score.isNotEmpty) score,
      if (reviewer.isNotEmpty) reviewer,
    ];
    return parts.join(' · ');
  }

  List<int> get remindList {
    final list = <int>[];
    for (final part in remind.split(',')) {
      final v = int.tryParse(part.trim());
      if (v != null && v >= 0) list.add(v);
    }
    return list;
  }

  /// 自定义提醒时间点（remind 里以 a<毫秒时间戳> 存的条目）
  List<DateTime> get customRemindList {
    final list = <DateTime>[];
    for (final part in remind.split(',')) {
      final p = part.trim();
      if (p.startsWith('a')) {
        final ms = int.tryParse(p.substring(1));
        if (ms != null) list.add(DateTime.fromMillisecondsSinceEpoch(ms));
      }
    }
    return list;
  }

  TaskItem copyWith({
    int? id,
    String? title,
    TaskType? type,
    int? courseId,
    int? folderId,
    int? compId,
    DateTime? startAt,
    DateTime? endAt,
    DateTime? dueAt,
    String? remind,
    bool? done,
    String? note,
    String? score,
    String? reviewer,
    String? reviewNote,
    DateTime? evaluatedAt,
    String? summary,
    String? submitMethod,
    String? links,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      courseId: courseId ?? this.courseId,
      folderId: folderId ?? this.folderId,
      compId: compId ?? this.compId,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      dueAt: dueAt ?? this.dueAt,
      remind: remind ?? this.remind,
      done: done ?? this.done,
      note: note ?? this.note,
      createdAt: createdAt,
      score: score ?? this.score,
      reviewer: reviewer ?? this.reviewer,
      reviewNote: reviewNote ?? this.reviewNote,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      summary: summary ?? this.summary,
      submitMethod: submitMethod ?? this.submitMethod,
      links: links ?? this.links,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'type': type.code,
        'course_id': courseId,
        'folder_id': folderId,
        'comp_id': compId,
        'start_at': dateToMillisStatic(startAt),
        'end_at': dateToMillisStatic(endAt),
        'due_at': dateToMillisStatic(dueAt),
        'remind': remind,
        'done': done ? 1 : 0,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
        'score': score,
        'reviewer': reviewer,
        'review_note': reviewNote,
        'evaluated_at': dateToMillisStatic(evaluatedAt),
        'summary': summary,
        'submit_method': submitMethod,
        'links': links,
      };

  factory TaskItem.fromMap(Map<String, Object?> m) => TaskItem(
        id: m['id'] as int?,
        title: (m['title'] as String?) ?? '',
        type: taskTypeFromCode((m['type'] as String?) ?? 'homework'),
        courseId: m['course_id'] as int?,
        folderId: m['folder_id'] as int?,
        compId: m['comp_id'] as int?,
        startAt: m['start_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['start_at'] as int),
        endAt: m['end_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['end_at'] as int),
        dueAt: m['due_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['due_at'] as int),
        remind: (m['remind'] as String?) ?? '0',
        done: ((m['done'] as int?) ?? 0) == 1,
        note: (m['note'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        score: (m['score'] as String?) ?? '',
        reviewer: (m['reviewer'] as String?) ?? '',
        reviewNote: (m['review_note'] as String?) ?? '',
        evaluatedAt: m['evaluated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['evaluated_at'] as int),
        summary: (m['summary'] as String?) ?? '',
        submitMethod: (m['submit_method'] as String?) ?? '',
        links: (m['links'] as String?) ?? '',
      );
}

int? dateToMillisStatic(DateTime? d) => d?.millisecondsSinceEpoch;

class NoteItem {
  final int? id;
  final String title;
  final String content;
  final String tags;
  final int? courseId;
  final int? folderId;
  final bool pinned;

  /// 自评 0–5 星（0 = 未评）
  final int rating;

  /// 自评 / 收获：这条值不值得、学到什么
  final String review;
  final String links; // 参考链接，一行一个
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteItem({
    this.id,
    required this.title,
    this.content = '',
    this.tags = '',
    this.courseId,
    this.folderId,
    this.pinned = false,
    this.rating = 0,
    this.review = '',
    this.links = '',
    required this.createdAt,
    required this.updatedAt,
  });

  List<String> get linkList =>
      links.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  NoteItem copyWith({
    int? id,
    String? title,
    String? content,
    String? tags,
    int? courseId,
    int? folderId,
    bool? pinned,
    int? rating,
    String? review,
    String? links,
    DateTime? updatedAt,
  }) {
    return NoteItem(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      courseId: courseId ?? this.courseId,
      folderId: folderId ?? this.folderId,
      pinned: pinned ?? this.pinned,
      rating: rating ?? this.rating,
      review: review ?? this.review,
      links: links ?? this.links,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get hasReview => review.trim().isNotEmpty || rating > 0;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'content': content,
        'tags': tags,
        'course_id': courseId,
        'folder_id': folderId,
        'pinned': pinned ? 1 : 0,
        'rating': rating,
        'review': review,
        'links': links,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory NoteItem.fromMap(Map<String, Object?> m) => NoteItem(
        id: m['id'] as int?,
        title: (m['title'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        tags: (m['tags'] as String?) ?? '',
        courseId: m['course_id'] as int?,
        folderId: m['folder_id'] as int?,
        pinned: ((m['pinned'] as int?) ?? 0) == 1,
        rating: (m['rating'] as int?) ?? 0,
        review: (m['review'] as String?) ?? '',
        links: (m['links'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
      );
}

class ReviewItem {
  final int? id;
  final String dateKey; // yyyy-MM-dd
  final String doneText;
  final String blockerText;
  final String tomorrowText;
  final int mood; // 1..5
  final DateTime createdAt;

  const ReviewItem({
    this.id,
    required this.dateKey,
    this.doneText = '',
    this.blockerText = '',
    this.tomorrowText = '',
    this.mood = 3,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'date_key': dateKey,
        'done_text': doneText,
        'blocker_text': blockerText,
        'tomorrow_text': tomorrowText,
        'mood': mood,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ReviewItem.fromMap(Map<String, Object?> m) => ReviewItem(
        id: m['id'] as int?,
        dateKey: (m['date_key'] as String?) ?? '',
        doneText: (m['done_text'] as String?) ?? '',
        blockerText: (m['blocker_text'] as String?) ?? '',
        tomorrowText: (m['tomorrow_text'] as String?) ?? '',
        mood: (m['mood'] as int?) ?? 3,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );
}

/// 一次专注记录：点「开始」写入，点「结束」补上 endAt。
class FocusSession {
  final int? id;
  final TaskType type;
  final int? taskId;
  final String taskTitle;
  final DateTime startAt;
  final DateTime? endAt;

  const FocusSession({
    this.id,
    this.type = TaskType.study,
    this.taskId,
    this.taskTitle = '',
    required this.startAt,
    this.endAt,
  });

  bool get running => endAt == null;

  /// 已累计秒数（进行中的按当前时间算）
  int get seconds {
    final end = endAt ?? DateTime.now();
    final v = end.difference(startAt).inSeconds;
    return v < 0 ? 0 : v;
  }

  String get label => taskTitle.isEmpty ? type.label : taskTitle;

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.code,
        'task_id': taskId,
        'task_title': taskTitle,
        'start_at': startAt.millisecondsSinceEpoch,
        'end_at': endAt?.millisecondsSinceEpoch,
      };

  factory FocusSession.fromMap(Map<String, Object?> m) => FocusSession(
        id: m['id'] as int?,
        type: taskTypeFromCode((m['type'] as String?) ?? 'study'),
        taskId: m['task_id'] as int?,
        taskTitle: (m['task_title'] as String?) ?? '',
        startAt: DateTime.fromMillisecondsSinceEpoch((m['start_at'] as int?) ?? 0),
        endAt: m['end_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['end_at'] as int),
      );
}

// ---------------------------------------------------------------- 重要程度
enum Importance { normal, important, urgent }

const List<String> kImportanceLabels = ['普通', '重要', '紧急'];

Importance importanceFromCode(int? v) {
  if (v != null && v >= 2) return Importance.urgent;
  if (v == 1) return Importance.important;
  return Importance.normal;
}

extension ImportanceX on Importance {
  int get code => index;
  String get label => kImportanceLabels[index];
  Color get color => const [Color(0xFF868E96), Color(0xFFE8590C), Color(0xFFD6336C)][index];
  IconData get icon => const [Icons.flag_outlined, Icons.flag, Icons.priority_high][index];
}

// ---------------------------------------------------------------- 文件夹（多级）
class Folder {
  final int? id;
  final String name;
  final int? parentId;
  final String scope; // 'task' | 'note' | 'comp' | 'notice'
  final DateTime createdAt;

  const Folder({
    this.id,
    required this.name,
    this.parentId,
    this.scope = 'task',
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'parent_id': parentId,
        'scope': scope,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Folder.fromMap(Map<String, Object?> m) => Folder(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        parentId: m['parent_id'] as int?,
        scope: (m['scope'] as String?) ?? 'task',
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );
}

// ---------------------------------------------------------------- 附件
class AttachmentItem {
  final int? id;
  final String ownerType; // task / note / comp / notice
  final int ownerId;
  final String name;
  final String path;
  final int size;
  final DateTime createdAt;

  const AttachmentItem({
    this.id,
    required this.ownerType,
    required this.ownerId,
    required this.name,
    required this.path,
    this.size = 0,
    required this.createdAt,
  });

  String get ext {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }

  bool get isImage => const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'].contains(ext);

  String get sizeText {
    if (size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  IconData get icon {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
      case 'wps':
        return Icons.description_outlined;
      case 'ppt':
      case 'pptx':
      case 'dps':
        return Icons.slideshow_outlined;
      case 'xls':
      case 'xlsx':
      case 'csv':
      case 'et':
        return Icons.table_chart_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color get color {
    switch (ext) {
      case 'pdf':
        return const Color(0xFFD6336C);
      case 'doc':
      case 'docx':
      case 'wps':
        return const Color(0xFF1971C2);
      case 'ppt':
      case 'pptx':
      case 'dps':
        return const Color(0xFFE8590C);
      case 'xls':
      case 'xlsx':
      case 'csv':
      case 'et':
        return const Color(0xFF2B8A3E);
      default:
        return const Color(0xFF868E96);
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'owner_type': ownerType,
        'owner_id': ownerId,
        'name': name,
        'path': path,
        'size': size,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory AttachmentItem.fromMap(Map<String, Object?> m) => AttachmentItem(
        id: m['id'] as int?,
        ownerType: (m['owner_type'] as String?) ?? '',
        ownerId: (m['owner_id'] as int?) ?? 0,
        name: (m['name'] as String?) ?? '',
        path: (m['path'] as String?) ?? '',
        size: (m['size'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );
}

// ---------------------------------------------------------------- 比赛
/// 评价来源
const List<String> kReviewers = ['老师', '领导', '同学', '自评', '平台'];

const List<String> kCompStages = ['初赛', '复赛', '决赛', '其他'];
const List<String> kCompLevels = ['校级', '市级', '省级', '国家级', '国际级', '其他'];

/// 参赛结果。'pending' 表示还没出结果。
const List<String> kCompResultCodes = ['pending', 'first', 'second', 'third', 'honor', 'finalist', 'join', 'fail'];

String compResultLabel(String code) {
  switch (code) {
    case 'first':
      return '一等奖';
    case 'second':
      return '二等奖';
    case 'third':
      return '三等奖';
    case 'honor':
      return '优秀奖';
    case 'finalist':
      return '晋级 / 入围';
    case 'join':
      return '参与';
    case 'fail':
      return '未获奖';
    default:
      return '未出结果';
  }
}

Color compResultColor(String code) {
  switch (code) {
    case 'first':
      return const Color(0xFFC77D00);
    case 'second':
      return const Color(0xFF6B7280);
    case 'third':
      return const Color(0xFFA9612F);
    case 'honor':
      return const Color(0xFF7048E8);
    case 'finalist':
      return const Color(0xFF2B8A3E);
    case 'join':
      return const Color(0xFF4C6FFF);
    case 'fail':
      return const Color(0xFF868E96);
    default:
      return const Color(0xFFADB5BD);
  }
}

IconData compResultIcon(String code) {
  switch (code) {
    case 'first':
    case 'second':
    case 'third':
      return Icons.emoji_events;
    case 'honor':
      return Icons.workspace_premium_outlined;
    case 'finalist':
      return Icons.trending_up;
    case 'join':
      return Icons.flag_outlined;
    case 'fail':
      return Icons.sentiment_neutral_outlined;
    default:
      return Icons.hourglass_empty;
  }
}

class Competition {
  final int? id;
  final String name;
  final String stage;
  final String level;
  final DateTime? signupDeadline; // 报名截止
  final DateTime? startAt;
  final DateTime? endAt;
  final String location;
  final String link;
  final String note;
  final int importance;
  final DateTime createdAt;

  /// 已经参加过（含往年补录的历史比赛）
  final bool attended;

  /// 参赛结果，见 kCompResultCodes
  final String resultRank;
  final String resultNote; // 具体名次说明，如「省级二等奖 · 队长」
  final DateTime? resultAt;

  /// 比赛总结 / 复盘
  final String summary;

  const Competition({
    this.id,
    required this.name,
    this.stage = '初赛',
    this.level = '校级',
    this.signupDeadline,
    this.startAt,
    this.endAt,
    this.location = '',
    this.link = '',
    this.note = '',
    this.importance = 1,
    required this.createdAt,
    this.attended = false,
    this.resultRank = 'pending',
    this.resultNote = '',
    this.resultAt,
    this.summary = '',
  });

  /// 结束时间过去 1 秒后才算结束（结束那一刻还不算）
  bool get ended =>
      endAt != null && DateTime.now().isAfter(endAt!.add(const Duration(seconds: 1)));

  bool get running {
    if (ended) return false;
    if (startAt != null) {
      return DateTime.now().isAfter(startAt!.add(const Duration(seconds: 1)));
    }
    return false;
  }

  /// 有奖项（一二三等奖 / 优秀奖 / 晋级）
  bool get awarded => const ['first', 'second', 'third', 'honor', 'finalist'].contains(resultRank);

  /// 是否算「参加过」：手动标记、已过结束时间、或已填结果
  bool get isPast => attended || ended || resultRank != 'pending' || resultAt != null;

  /// 已结束但结果还没填，提醒补录成绩
  bool get resultMissing => isPast && resultRank == 'pending';

  String get statusLabel {
    if (isPast) return '已参加';
    if (running) return '进行中';
    return '未开始';
  }

  Color get statusColor {
    if (isPast) return const Color(0xFF868E96);
    if (running) return const Color(0xFF2B8A3E);
    return const Color(0xFF4C6FFF);
  }

  String get resultLabel => compResultLabel(resultRank);

  Importance get level_ => importanceFromCode(importance);

  Competition copyWith({
    int? id,
    String? name,
    String? stage,
    String? level,
    DateTime? signupDeadline,
    DateTime? startAt,
    DateTime? endAt,
    String? location,
    String? link,
    String? note,
    int? importance,
    bool? attended,
    String? resultRank,
    String? resultNote,
    DateTime? resultAt,
    String? summary,
  }) => Competition(
        id: id ?? this.id,
        name: name ?? this.name,
        stage: stage ?? this.stage,
        level: level ?? this.level,
        signupDeadline: signupDeadline ?? this.signupDeadline,
        startAt: startAt ?? this.startAt,
        endAt: endAt ?? this.endAt,
        location: location ?? this.location,
        link: link ?? this.link,
        note: note ?? this.note,
        importance: importance ?? this.importance,
        createdAt: createdAt,
        attended: attended ?? this.attended,
        resultRank: resultRank ?? this.resultRank,
        resultNote: resultNote ?? this.resultNote,
        resultAt: resultAt ?? this.resultAt,
        summary: summary ?? this.summary,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'stage': stage,
        'level': level,
        'signup_deadline': signupDeadline?.millisecondsSinceEpoch,
        'start_at': startAt?.millisecondsSinceEpoch,
        'end_at': endAt?.millisecondsSinceEpoch,
        'location': location,
        'link': link,
        'note': note,
        'importance': importance,
        'created_at': createdAt.millisecondsSinceEpoch,
        'attended': attended ? 1 : 0,
        'result_rank': resultRank,
        'result_note': resultNote,
        'result_at': resultAt?.millisecondsSinceEpoch,
        'summary': summary,
      };

  factory Competition.fromMap(Map<String, Object?> m) => Competition(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        stage: (m['stage'] as String?) ?? '初赛',
        level: (m['level'] as String?) ?? '校级',
        signupDeadline: m['signup_deadline'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['signup_deadline'] as int),
        startAt: m['start_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['start_at'] as int),
        endAt: m['end_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['end_at'] as int),
        location: (m['location'] as String?) ?? '',
        link: (m['link'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        importance: (m['importance'] as int?) ?? 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        attended: ((m['attended'] as int?) ?? 0) == 1,
        resultRank: (m['result_rank'] as String?) ?? 'pending',
        resultNote: (m['result_note'] as String?) ?? '',
        resultAt: m['result_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['result_at'] as int),
        summary: (m['summary'] as String?) ?? '',
      );
}

// ---------------------------------------------------------------- 灵感 / 社会痛点 / 个人想法
enum IdeaKind { idea, pain, thought }

IdeaKind ideaKindFromCode(String code) {
  if (code == 'pain') return IdeaKind.pain;
  if (code == 'thought') return IdeaKind.thought;
  return IdeaKind.idea;
}

extension IdeaKindX on IdeaKind {
  String get code {
    if (this == IdeaKind.pain) return 'pain';
    if (this == IdeaKind.thought) return 'thought';
    return 'idea';
  }

  String get label => const ['灵感', '痛点', '想法'][index];

  String get hint => const [
        '一闪而过的点子、可以做的产品/选题/活动…',
        '社会、校园、时代里让人不舒服的地方，痛点就是机会',
        '你的观点、推理、方案，可以很长，也可以只是一句话',
      ][index];

  Color get color => const [Color(0xFF7048E8), Color(0xFFD6336C), Color(0xFF1971C2)][index];

  IconData get icon =>
      const [Icons.lightbulb_outline, Icons.report_problem_outlined, Icons.psychology_outlined][index];
}

class IdeaItem {
  final int? id;
  final IdeaKind kind;
  final String title;
  final String content;
  final String tags;
  final int? folderId;
  final bool pinned;

  /// 自评 0–5 星（0 = 未评）
  final int rating;

  /// 自评 / 收获：这条值不值得、学到什么
  final String review;
  final String links; // 参考链接，一行一个
  final DateTime createdAt;
  final DateTime updatedAt;

  const IdeaItem({
    this.id,
    this.kind = IdeaKind.idea,
    required this.title,
    this.content = '',
    this.tags = '',
    this.folderId,
    this.pinned = false,
    this.rating = 0,
    this.review = '',
    this.links = '',
    required this.createdAt,
    required this.updatedAt,
  });

  List<String> get linkList =>
      links.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  List<String> get tagList =>
      tags.split(RegExp(r'[,，\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  IdeaItem copyWith({
    int? id,
    IdeaKind? kind,
    String? title,
    String? content,
    String? tags,
    int? folderId,
    bool? pinned,
    int? rating,
    String? review,
    String? links,
    DateTime? updatedAt,
  }) {
    return IdeaItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      folderId: folderId ?? this.folderId,
      pinned: pinned ?? this.pinned,
      rating: rating ?? this.rating,
      review: review ?? this.review,
      links: links ?? this.links,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get hasReview => review.trim().isNotEmpty || rating > 0;

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.code,
        'title': title,
        'content': content,
        'tags': tags,
        'folder_id': folderId,
        'pinned': pinned ? 1 : 0,
        'rating': rating,
        'review': review,
        'links': links,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory IdeaItem.fromMap(Map<String, Object?> m) => IdeaItem(
        id: m['id'] as int?,
        kind: ideaKindFromCode((m['kind'] as String?) ?? 'idea'),
        title: (m['title'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        tags: (m['tags'] as String?) ?? '',
        folderId: m['folder_id'] as int?,
        pinned: ((m['pinned'] as int?) ?? 0) == 1,
        rating: (m['rating'] as int?) ?? 0,
        review: (m['review'] as String?) ?? '',
        links: (m['links'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
      );
}

// ---------------------------------------------------------------- 通知（班群 / 年级 / 学院 / 公司）
const List<String> kNoticeSources = ['班群', '年级', '学院', '教务处', '公司', '其他'];

/// 通知默认提前量：普通 / 重要 / 紧急 各一套，越紧急提醒档位越多
const List<List<int>> kNoticeRemindDefaults = [
  [1440, 0], // 普通：1 天前 + 截止时
  [1440, 120, 0], // 重要：1 天前 / 2 小时前 / 截止时
  [4320, 1440, 120, 30, 0], // 紧急：3 天前 / 1 天前 / 2 小时前 / 30 分钟前 / 截止时
];

/// 通知可选的提醒档位（分钟）
const List<int> kNoticeRemindPresets = [0, 30, 60, 120, 360, 1440, 2880, 4320];

class NoticeItem {
  final int? id;
  final String source;
  final String title;
  final String content;
  final String keyPoints; // 一行一条
  final String links; // 一行一个
  final int importance;
  final bool read;
  final bool pinned;
  final DateTime createdAt;

  /// 截止时间（报名截止、材料提交截止…），可空。设了才会在截止前提醒。
  final DateTime? deadlineAt;

  /// 提前提醒量 "1440,120,0" 分钟前；为空时按重要程度取默认档
  final String remind;

  const NoticeItem({
    this.id,
    required this.source,
    required this.title,
    this.content = '',
    this.keyPoints = '',
    this.links = '',
    this.importance = 1,
    this.read = false,
    this.pinned = false,
    required this.createdAt,
    this.deadlineAt,
    this.remind = '',
  });

  List<String> get keyPointList =>
      keyPoints.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  List<String> get linkList =>
      links.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  bool get hasDeadline => deadlineAt != null;

  /// 逾期：截止时间过去 1 秒之后才算
  bool get isOverdue =>
      deadlineAt != null && DateTime.now().isAfter(deadlineAt!.add(const Duration(seconds: 1)));

  List<int> get remindList {
    final list = <int>[];
    for (final part in remind.split(',')) {
      final v = int.tryParse(part.trim());
      if (v != null && v >= 0 && !list.contains(v)) list.add(v);
    }
    if (list.isEmpty) {
      return kNoticeRemindDefaults[importance.clamp(0, 2)];
    }
    return list;
  }

  NoticeItem copyWith({
    int? id,
    String? source,
    String? title,
    String? content,
    String? keyPoints,
    String? links,
    int? importance,
    bool? read,
    bool? pinned,
    DateTime? createdAt,
    DateTime? deadlineAt,
    bool clearDeadline = false,
    String? remind,
  }) => NoticeItem(
        id: id ?? this.id,
        source: source ?? this.source,
        title: title ?? this.title,
        content: content ?? this.content,
        keyPoints: keyPoints ?? this.keyPoints,
        links: links ?? this.links,
        importance: importance ?? this.importance,
        read: read ?? this.read,
        pinned: pinned ?? this.pinned,
        createdAt: createdAt ?? this.createdAt,
        deadlineAt: clearDeadline ? null : (deadlineAt ?? this.deadlineAt),
        remind: remind ?? this.remind,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'source': source,
        'title': title,
        'content': content,
        'key_points': keyPoints,
        'links': links,
        'importance': importance,
        'read': read ? 1 : 0,
        'pinned': pinned ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'deadline_at': deadlineAt?.millisecondsSinceEpoch,
        'remind': remind,
      };

  factory NoticeItem.fromMap(Map<String, Object?> m) => NoticeItem(
        id: m['id'] as int?,
        source: (m['source'] as String?) ?? '班群',
        title: (m['title'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        keyPoints: (m['key_points'] as String?) ?? '',
        links: (m['links'] as String?) ?? '',
        importance: (m['importance'] as int?) ?? 1,
        read: ((m['read'] as int?) ?? 0) == 1,
        pinned: ((m['pinned'] as int?) ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        deadlineAt: m['deadline_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['deadline_at'] as int),
        remind: (m['remind'] as String?) ?? '',
      );
}

/// 资源库：收到的一份资源（家里/学校/公司/其他给的）
enum ResourceSource { family, school, company, other }

extension ResourceSourceX on ResourceSource {
  String get code {
    if (this == ResourceSource.family) return 'family';
    if (this == ResourceSource.school) return 'school';
    if (this == ResourceSource.company) return 'company';
    return 'other';
  }

  String get label {
    if (this == ResourceSource.family) return '家里给的';
    if (this == ResourceSource.school) return '学校给的';
    if (this == ResourceSource.company) return '公司给的';
    return '其他';
  }

  IconData get icon {
    if (this == ResourceSource.family) return Icons.home_outlined;
    if (this == ResourceSource.school) return Icons.school_outlined;
    if (this == ResourceSource.company) return Icons.business_center_outlined;
    return Icons.category_outlined;
  }

  Color get color {
    if (this == ResourceSource.family) return const Color(0xFFE8590C);
    if (this == ResourceSource.school) return const Color(0xFF1971C2);
    if (this == ResourceSource.company) return const Color(0xFF2B8A3E);
    return const Color(0xFF7048E8);
  }
}

ResourceSource resourceSourceFromCode(String code) {
  if (code == 'family') return ResourceSource.family;
  if (code == 'school') return ResourceSource.school;
  if (code == 'company') return ResourceSource.company;
  return ResourceSource.other;
}

/// 方面：生活 / 学习 / 工作
enum ResourceDomain { life, study, work }

extension ResourceDomainX on ResourceDomain {
  String get code {
    if (this == ResourceDomain.life) return 'life';
    if (this == ResourceDomain.study) return 'study';
    return 'work';
  }

  String get label {
    if (this == ResourceDomain.life) return '生活';
    if (this == ResourceDomain.study) return '学习';
    return '工作';
  }

  IconData get icon {
    if (this == ResourceDomain.life) return Icons.nights_stay_outlined;
    if (this == ResourceDomain.study) return Icons.menu_book_outlined;
    return Icons.work_outline;
  }
}

ResourceDomain resourceDomainFromCode(String code) {
  if (code == 'life') return ResourceDomain.life;
  if (code == 'study') return ResourceDomain.study;
  return ResourceDomain.work;
}

/// 给的人的关系：亲戚 / 老师 / 同学 / 同事 / 领导 / 其他
enum ResourceRelation { relative, teacher, classmate, colleague, leader, other }

extension ResourceRelationX on ResourceRelation {
  String get code {
    switch (this) {
      case ResourceRelation.relative:
        return 'relative';
      case ResourceRelation.teacher:
        return 'teacher';
      case ResourceRelation.classmate:
        return 'classmate';
      case ResourceRelation.colleague:
        return 'colleague';
      case ResourceRelation.leader:
        return 'leader';
      case ResourceRelation.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case ResourceRelation.relative:
        return '亲戚';
      case ResourceRelation.teacher:
        return '老师';
      case ResourceRelation.classmate:
        return '同学';
      case ResourceRelation.colleague:
        return '同事';
      case ResourceRelation.leader:
        return '领导';
      case ResourceRelation.other:
        return '其他人';
    }
  }
}

ResourceRelation resourceRelationFromCode(String code) {
  switch (code) {
    case 'relative':
      return ResourceRelation.relative;
    case 'teacher':
      return ResourceRelation.teacher;
    case 'classmate':
      return ResourceRelation.classmate;
    case 'colleague':
      return ResourceRelation.colleague;
    case 'leader':
      return ResourceRelation.leader;
    default:
      return ResourceRelation.other;
  }
}

class ResourceItem {
  final int? id;
  final String title;
  final ResourceSource source;
  final ResourceDomain domain;
  final String subject; // 哪一科 / 哪一方面
  final String giver; // 具体谁给的（名字）
  final ResourceRelation relation; // 关系
  final String purpose; // 用于做什么
  final String note;
  final List<String> links; // 相关链接（可多个）
  final DateTime createdAt;
  final DateTime updatedAt;

  const ResourceItem({
    this.id,
    required this.title,
    this.source = ResourceSource.other,
    this.domain = ResourceDomain.life,
    this.subject = '',
    this.giver = '',
    this.relation = ResourceRelation.other,
    this.purpose = '',
    this.note = '',
    this.links = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// 「妈妈 · 亲戚」这类展示文案
  String get giverText {
    final parts = <String>[if (giver.isNotEmpty) giver, relation.label];
    return parts.join(' · ');
  }

  ResourceItem copyWith({
    int? id,
    String? title,
    ResourceSource? source,
    ResourceDomain? domain,
    String? subject,
    String? giver,
    ResourceRelation? relation,
    String? purpose,
    String? note,
    List<String>? links,
    DateTime? updatedAt,
  }) {
    return ResourceItem(
      id: id ?? this.id,
      title: title ?? this.title,
      source: source ?? this.source,
      domain: domain ?? this.domain,
      subject: subject ?? this.subject,
      giver: giver ?? this.giver,
      relation: relation ?? this.relation,
      purpose: purpose ?? this.purpose,
      note: note ?? this.note,
      links: links ?? this.links,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'source': source.code,
        'domain': domain.code,
        'subject': subject,
        'giver': giver,
        'relation': relation.code,
        'purpose': purpose,
        'note': note,
        'links': links.join('\n'),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ResourceItem.fromMap(Map<String, Object?> m) => ResourceItem(
        id: m['id'] as int?,
        title: (m['title'] as String?) ?? '',
        source: resourceSourceFromCode((m['source'] as String?) ?? 'other'),
        domain: resourceDomainFromCode((m['domain'] as String?) ?? 'life'),
        subject: (m['subject'] as String?) ?? '',
        giver: (m['giver'] as String?) ?? '',
        relation: resourceRelationFromCode((m['relation'] as String?) ?? 'other'),
        purpose: (m['purpose'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        links: ((m['links'] as String?) ?? '')
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
      );
}

/// 作业 / 工作的点评（可多条：老师、领导、自己）
class TaskComment {
  final int? id;
  final int taskId;
  final String role; // teacher / leader / self
  final String person; // 具体是谁
  final String content;
  final DateTime createdAt;

  const TaskComment({
    this.id,
    required this.taskId,
    this.role = 'teacher',
    this.person = '',
    required this.content,
    required this.createdAt,
  });

  String get roleLabel {
    if (role == 'leader') return '领导';
    if (role == 'self') return '自己';
    return '老师';
  }

  IconData get roleIcon {
    if (role == 'leader') return Icons.badge_outlined;
    if (role == 'self') return Icons.person_outline;
    return Icons.school_outlined;
  }

  Color get roleColor {
    if (role == 'leader') return const Color(0xFF1971C2);
    if (role == 'self') return const Color(0xFF7048E8);
    return const Color(0xFF2B8A3E);
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'task_id': taskId,
        'role': role,
        'person': person,
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory TaskComment.fromMap(Map<String, Object?> m) => TaskComment(
        id: m['id'] as int?,
        taskId: (m['task_id'] as int?) ?? 0,
        role: (m['role'] as String?) ?? 'teacher',
        person: (m['person'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );
}

/// 一场考试
class Exam {
  final int? id;
  final String name;
  final int? courseId;
  final String courseName;
  final DateTime startAt;
  final DateTime? endAt;
  final String location;
  final String seat;
  final String note;
  final String remind; // 提前量，分钟，逗号分隔
  final String links; // 相关链接，一行一个
  final DateTime createdAt;

  const Exam({
    this.id,
    required this.name,
    this.courseId,
    this.courseName = '',
    required this.startAt,
    this.endAt,
    this.location = '',
    this.seat = '',
    this.note = '',
    this.remind = '1440,60',
    this.links = '',
    required this.createdAt,
  });

  List<int> get remindList => remind
      .split(',')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .where((e) => e >= 0)
      .toList();

  List<String> get linkList =>
      links.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  bool get isOver =>
      DateTime.now().isAfter((endAt ?? startAt).add(const Duration(seconds: 1)));

  Exam copyWith({
    int? id,
    String? name,
    int? courseId,
    String? courseName,
    DateTime? startAt,
    DateTime? endAt,
    String? location,
    String? seat,
    String? note,
    String? remind,
    String? links,
  }) {
    return Exam(
      id: id ?? this.id,
      name: name ?? this.name,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      location: location ?? this.location,
      seat: seat ?? this.seat,
      note: note ?? this.note,
      remind: remind ?? this.remind,
      links: links ?? this.links,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'course_id': courseId,
        'course_name': courseName,
        'start_at': startAt.millisecondsSinceEpoch,
        'end_at': endAt?.millisecondsSinceEpoch,
        'location': location,
        'seat': seat,
        'note': note,
        'remind': remind,
        'links': links,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Exam.fromMap(Map<String, Object?> m) => Exam(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        courseId: m['course_id'] as int?,
        courseName: (m['course_name'] as String?) ?? '',
        startAt: DateTime.fromMillisecondsSinceEpoch((m['start_at'] as int?) ?? 0),
        endAt: m['end_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['end_at'] as int),
        location: (m['location'] as String?) ?? '',
        seat: (m['seat'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        remind: (m['remind'] as String?) ?? '1440,60',
        links: (m['links'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );
}

/// 一门课的成绩（算绩点用）
class Grade {
  final int? id;
  final int? courseId;
  final String courseName;
  final double credit; // 学分
  final double? score; // 百分制成绩
  final double? gpa; // 绩点（不填按分数自动换算）
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Grade({
    this.id,
    this.courseId,
    required this.courseName,
    this.credit = 0,
    this.score,
    this.gpa,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// 展示用绩点：手填优先，否则按分数换算
  double? get gpaValue => gpa ?? (score == null ? null : gpaOfScore(score!));

  /// 换算后的绩点是否来自自动换算
  bool get gpaIsAuto => gpa == null && score != null;

  Grade copyWith({
    int? id,
    int? courseId,
    String? courseName,
    double? credit,
    double? score,
    double? gpa,
    String? note,
    DateTime? updatedAt,
  }) {
    return Grade(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      credit: credit ?? this.credit,
      score: score ?? this.score,
      gpa: gpa ?? this.gpa,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'course_id': courseId,
        'course_name': courseName,
        'credit': credit,
        'score': score,
        'gpa': gpa,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Grade.fromMap(Map<String, Object?> m) => Grade(
        id: m['id'] as int?,
        courseId: m['course_id'] as int?,
        courseName: (m['course_name'] as String?) ?? '',
        credit: (m['credit'] as num?)?.toDouble() ?? 0,
        score: (m['score'] as num?)?.toDouble(),
        gpa: (m['gpa'] as num?)?.toDouble(),
        note: (m['note'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
      );
}

/// 常见 4.0 制绩点换算（可手填覆盖）
double gpaOfScore(double score) {
  if (score >= 90) return 4.0;
  if (score >= 85) return 3.7;
  if (score >= 82) return 3.3;
  if (score >= 78) return 3.0;
  if (score >= 75) return 2.7;
  if (score >= 72) return 2.3;
  if (score >= 68) return 2.0;
  if (score >= 64) return 1.5;
  if (score >= 60) return 1.0;
  return 0;
}
