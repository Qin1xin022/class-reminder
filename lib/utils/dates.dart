// 极简日期/时间工具。刻意不依赖 intl，避免版本冲突。
String two(int v) => v.toString().padLeft(2, '0');

/// 分钟数（从 00:00 起）→ "08:05"
String hhmm(int minutes) {
  final m = minutes < 0 ? 0 : minutes;
  return '${two(m ~/ 60)}:${two(m % 60)}';
}

String hhmmOf(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

const List<String> kWeekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String weekdayLabel(int weekday) {
  final i = weekday - 1;
  if (i < 0 || i > 6) return '';
  return kWeekdays[i];
}

String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String fmtMd(DateTime d) => '${two(d.month)}/${two(d.day)}';

String fmtDateTime(DateTime? d) => d == null ? '' : '${fmtDate(d)} ${hhmmOf(d)}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? millisToDate(int? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

int? dateToMillis(DateTime? d) => d?.millisecondsSinceEpoch;

/// 提醒提前量 → 中文
String offsetLabel(int minutes) {
  if (minutes <= 0) return '准时';
  if (minutes % 1440 == 0) return '${minutes ~/ 1440}天前';
  if (minutes % 60 == 0) return '${minutes ~/ 60}小时前';
  return '$minutes分钟前';
}

/// 提前量 → 「还有多久」口吻（用于上课提醒：还有 30 分钟上课）
String untilLabel(int minutes) {
  if (minutes <= 0) return '现在';
  if (minutes % 1440 == 0) return '还有 ${minutes ~/ 1440} 天';
  if (minutes % 60 == 0) {
    final h = minutes ~/ 60;
    return '还有 $h 小时';
  }
  if (minutes > 60) return '还有 ${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
  return '还有 $minutes 分钟';
}

/// 逾期判定：结束时间过去 1 秒之后才算逾期（结束那一刻还不算）
bool isOverdueAt(DateTime? end, {DateTime? now}) {
  if (end == null) return false;
  final n = now ?? DateTime.now();
  return n.isAfter(end.add(const Duration(seconds: 1)));
}

/// 距离截止还剩多久
String leftText(DateTime due) {
  final now = DateTime.now();
  final diff = due.difference(now);
  if (isOverdueAt(due, now: now)) {
    final over = now.difference(due);
    if (over.inDays >= 1) return '已逾期 ${over.inDays} 天';
    if (over.inHours >= 1) return '已逾期 ${over.inHours} 小时';
    return '已逾期 ${over.inMinutes} 分钟';
  }
  if (diff.inSeconds <= 0) return '马上截止';
  if (diff.inMinutes < 60) return '还剩 ${diff.inMinutes} 分钟';
  if (diff.inHours < 24) return '还剩 ${diff.inHours} 小时';
  return '还剩 ${diff.inDays} 天';
}

/// 今天 / 明天 / 10-31
String friendlyDay(DateTime d) {
  final today = dateOnly(DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff == 2) return '后天';
  if (diff == -1) return '昨天';
  return fmtMd(d);
}
