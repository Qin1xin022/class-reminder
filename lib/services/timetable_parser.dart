import 'dart:math' as math;

import '../models.dart';

/// 课表解析：把「教务系统的课表文本/表格/OCR 结果」变成课程草稿。
/// 所有解析都只产出草稿（Course.id == null），导入前必须经过预览确认页，
/// 用户可以逐条勾选、修改后再入库——识别有误差也不怕。

/// 一段课表格子文本 → 结构化字段（不含星期；星期由网格列决定）
class ParsedCell {
  String name = '';
  String teacher = '';
  String location = '';
  int weekStart = 1;
  int weekEnd = 16;
  int? startPeriod; // 节次（1 起）
  int? endPeriod;
  int? startMin; // 直接给了时间（如 08:00-09:40）则优先用
  int? endMin;
}

final _weekRange = RegExp(r'(\d{1,2})\s*[-–—~至到]\s*(\d{1,2})\s*周');
bool ocrDebug = false;
final _weekSingle = RegExp(r'(?:第\s*)?(\d{1,2})\s*周');
final _weekFirst = RegExp(r'第\s*(\d{1,2})\s*周');
final _periodRange = RegExp(r'第?\s*(\d{1,2})\s*[-–—~至到]\s*(\d{1,2})\s*节');
final _periodSingle = RegExp(r'第\s*(\d{1,2})\s*节');
final _timeRange = RegExp(r'(\d{1,2}):(\d{2})\s*[-–—~至到]\s*(\d{1,2}):(\d{2})');
final _locationHint = RegExp(r'(楼|栋|室|馆|厅|操场|球场|机房|实训|报告厅|阶梯|教室|[A-Za-z]-?\d{3,4}|\b\d{3,4}\b)');
final _teacherHint = RegExp(r'(老师|教师|教授|讲师|副教授)$');

/// 「星期」列头 → 1..7
final Map<String, int> kWeekdayWords = {
  '周一': 1, '周二': 2, '周三': 3, '周四': 4, '周五': 5, '周六': 6, '周日': 7,
  '星期一': 1, '星期二': 2, '星期三': 3, '星期四': 4, '星期五': 5, '星期六': 6, '星期日': 7, '星期天': 7,
};

int? weekdayFromWord(String raw) {
  final t = raw.trim();
  // 「周一」常被 OCR 认成「周-」（一 → 横杠）；「周日」偶尔认成「周口」
  if (RegExp(r'^周\s*[-–—1]$').hasMatch(t)) return 1;
  if (RegExp(r'^周\s*[日口]$').hasMatch(t) && t != '周日') return 7;
  for (final e in kWeekdayWords.entries) {
    if (t.contains(e.key)) return e.value;
  }
  return null;
}

/// 解析一个格子/一段课程描述文本。
/// [text] 里可以是 「课程名\\n老师\\n1-16周\\nA栋201」 这种多行，也可以是一整行。
ParsedCell parseCellText(String raw) {
  final out = ParsedCell();
  var text = raw.replaceAll('\r', '').trim();
  if (text.isEmpty) return out;

  // 1) 周次
  final wm = _weekRange.firstMatch(text);
  if (wm != null) {
    out.weekStart = int.parse(wm.group(1)!);
    out.weekEnd = int.parse(wm.group(2)!);
  } else {
    final wf = _weekFirst.firstMatch(text) ?? _weekSingle.firstMatch(text);
    if (wf != null) out.weekStart = out.weekEnd = int.parse(wf.group(1)!);
  }
  if (out.weekEnd < out.weekStart) out.weekEnd = out.weekStart;
  // 单周/双周：在已有区间内取奇数/偶数周
  if (text.contains('单周')) {
    out.weekStart = out.weekStart.isOdd ? out.weekStart : out.weekStart + 1;
    out.weekEnd = out.weekEnd.isOdd ? out.weekEnd : out.weekEnd - 1;
  } else if (text.contains('双周')) {
    out.weekStart = out.weekStart.isEven ? out.weekStart : out.weekStart + 1;
    out.weekEnd = out.weekEnd.isEven ? out.weekEnd : out.weekEnd - 1;
  }
  if (out.weekEnd < out.weekStart) out.weekEnd = out.weekStart;

  // 2) 直接给时间的（08:00-09:40）
  final tm = _timeRange.firstMatch(text);
  if (tm != null) {
    final sh = int.parse(tm.group(1)!), sm = int.parse(tm.group(2)!);
    final eh = int.parse(tm.group(3)!), em = int.parse(tm.group(4)!);
    if (sh < 24 && eh < 24) {
      out.startMin = sh * 60 + sm;
      out.endMin = eh * 60 + em;
    }
  }

  // 3) 节次（把周次文本先摘掉，防止 “1-16周” 被误当节次）
  var forPeriod = text.replaceAll(_weekRange, ' ').replaceAll(_weekFirst, ' ');
  final pm = _periodRange.firstMatch(forPeriod) ?? _periodSingle.firstMatch(forPeriod);
  if (pm != null) {
    final a = int.tryParse(pm.group(1)!);
    final bRaw = pm.groupCount >= 2 ? pm.group(2) : null;
    final b = int.tryParse(bRaw ?? '') ?? a;
    if (a != null && a >= 1 && a <= 20) {
      out.startPeriod = a;
      out.endPeriod = (b == null || b < a) ? a : (b > 20 ? a : b);
    }
  } else {
    // 整格就是节次标签：如 “1,2节”“1、2”“第1-2节” 单独占一格
    final cm = RegExp(r'^\s*第?\s*(\d{1,2})\s*[,，、]\s*(\d{1,2})\s*节?\s*$').firstMatch(forPeriod);
    if (cm != null) {
      final a = int.tryParse(cm.group(1)!);
      final b = int.tryParse(cm.group(2)!);
      if (a != null && a >= 1 && a <= 20) {
        out.startPeriod = a;
        out.endPeriod = (b != null && b >= a && b <= 20) ? b : a;
      }
    }
  }

  // 4) 逐行分类：课程名 / 老师 / 地点
  // “课程名@教室”格式（部分教务 App）：@ 后面是地点。
  // 门牌号可能被 OCR 换行拆开（如 “@南霄3” / “27”），纯数字短行要续接回去。
  // 教室徽章的圆角边框可能被认成 “/”（如 “@//10-5/”），最后统一剔除。
  final atM = RegExp(r'@([^@\n]{1,30})').firstMatch(text);
  final atRooms = <String>[]; // 每个含「@教室」的行取到的地点（可跨行续接）
  if (atM != null && atM.group(1)!.trim().isNotEmpty) {
    atRooms.add(atM.group(1)!.trim());
  }
  final lines = text
      .split(RegExp(r'[\n;；]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final leftovers = <String>[];
  var seenAt = false; // 本格已出现过「@教室」行
  for (final line0 in lines) {
    // 「@教室」行：@ 后面的内容是地点；@ 前面若还有文字则是课程名片段
    if (line0.contains('@')) {
      seenAt = true;
      final idx = line0.indexOf('@');
      final before = line0.substring(0, idx).trim();
      if (before.isNotEmpty) leftovers.add(before);
      final room = line0.substring(idx + 1).trim();
      if (room.isNotEmpty) atRooms.add(room);
      continue;
    }
    // 换行拆开的门牌号：@ 行之后的纯数字短行续接地点
    if (seenAt && atRooms.isNotEmpty && RegExp(r'^\d{1,4}$').hasMatch(line0)) {
      atRooms[atRooms.length - 1] += line0;
      continue;
    }
    var line = line0
        .replaceAll(_weekRange, ' ')
        .replaceAll(_weekFirst, ' ')
        .replaceAll(_periodRange, ' ')
        .replaceAll(_periodSingle, ' ')
        .replaceAll(_timeRange, ' ')
        .replaceAll(RegExp(r'[(（]\s*[单双]?周?\s*[)]\)'), ' ')
        .replaceAll(RegExp(r'(单周|双周|周次|节)'), ' ')
        .trim();
    line = line.replaceAll(RegExp(r'^[-–—~·,，、:：@#\s]+|[-–—~·,，、:：@#\s]+$'), '');
    if (line.isEmpty) continue;
    // 纯符号行（如 “+”“-” 按钮）不是课程内容
    if (!RegExp(r'[A-Za-z0-9\u4e00-\u9fa5]').hasMatch(line)) continue;
    if (_teacherHint.hasMatch(line0) && line.length <= 12) {
      out.teacher = line;
      continue;
    }
    // 「@教室」行之后的短行（如换行拆开的“场”“-309”）是地点续接
    if (seenAt && atRooms.isNotEmpty && line0.length <= 4 && !RegExp(r'[周节]|:').hasMatch(line0)) {
      atRooms[atRooms.length - 1] += line0;
      continue;
    }
    // “@教室”格式下地点已经取到了，整行只可能是课程名片段
    if (atM == null && _locationHint.hasMatch(line0) && line.length <= 20) {
      out.location = out.location.isEmpty ? line : out.location;
      continue;
    }
    leftovers.add(line);
  }
  // 老师的兜底：有名字候选的前提下，形如 2~4 个汉字、以常见姓氏开头、
  // 且比名字短的独立短行才认，避免把「高等数学」「心理健康」这种当老师。
  // 「课程名@教室」格式的截图里没有老师行，短行都是课名片段，不做兜底。
  const kSurnames = '王李张刘陈杨赵黄周吴徐孙马朱胡郭何高林罗郑梁谢宋唐许韩冯邓'
      '曹彭曾肖田董袁潘于蒋蔡余杜叶程苏魏吕丁任沈姚卢姜崔钟谭陆汪范金石廖贾夏'
      '韦付方白邹孟熊秦邱江尹薛闫段雷侯龙史陶黎贺顾毛郝龚邵万钱严覃武戴莫孔向汤';
  if (out.teacher.isEmpty && atM == null && leftovers.length >= 2) {
    final nameLen = leftovers.first.length;
    for (final line in leftovers.skip(1)) {
      if (RegExp(r'^[\u4e00-\u9fa5]{2,4}$').hasMatch(line) &&
          kSurnames.contains(line[0]) &&
          line.length < nameLen &&
          !kWeekdayWords.keys.any(line.contains)) {
        out.teacher = line;
        leftovers.remove(line);
        break;
      }
    }
  }
  // 课程名可能被 OCR 拆成多行（如「大学生/心理健康/教育@4-10」），拼回去
  out.name = leftovers.isNotEmpty ? _joinOcrName(leftovers) : text.split('\n').first.trim();
  out.name = out.name
      .replaceAll(RegExp(r'@.*$'), '')
      .replaceAll(_weekRange, '')
      .replaceAll(_weekFirst, '')
      .replaceAll(_timeRange, '')
      .trim();
  if (out.name.length > 40) out.name = out.name.substring(0, 40);
  // 同一格可能混进相邻列的「@教室」行（x 切分误差，如 “@3-” 和 “@3-40”），
  // 取最长的一个——被切短的让位给完整的门牌号
  if (atRooms.isNotEmpty) {
    atRooms.sort((a, b) => b.length.compareTo(a.length));
    out.location = atRooms.first;
  }
  // 「@教室」捕获可能带上格内空格（如 “南霄3 27”）和徽章边框斜杠
  // （如 “//10-5/”），去掉
  out.location =
      out.location.replaceAll(RegExp(r'\s+|[/\\|]+'), '');
  return out;
}

/// 节次 → 分钟（用手机里配置的作息；超出范围的节次按 50 分钟/节往后排）
(int, int) periodsToMinutes(int startP, int endP, List<(int, int)> periods) {
  int at(int p) {
    final i = p - 1;
    if (i >= 0 && i < periods.length) return periods[i].$1;
    return 480 + (p - 1) * 50; // 兜底：8:00 起每节 50 分钟
  }
  int end(int p) {
    final i = p - 1;
    if (i >= 0 && i < periods.length) return periods[i].$2;
    return at(p) + 50;
  }
  final s = at(startP);
  final e = endP >= startP ? end(endP) : end(startP);
  return (s, e >= s ? e : s + 50);
}

/// 网格（行 × 列的文本矩阵）→ 课程列表。
/// 自动找「星期」表头行确定列，每行第一列若是节次/时间标签则作为该行的节次。
/// [rowSpans]：纵向合并单元格信息，key = (行索引, 列索引)，value = 该格往下
/// 覆盖的行数。教务导出的课表常用合并单元格表示连堂课（如「设计造型」合并
/// 第1~4节），值只存在首行——没有跨度信息就会把它当成单节课。
List<Course> parseGrid(
    List<List<String>> grid, List<(int, int)> periods,
    {Map<(int, int), int>? rowSpans}) {
  // 过滤全空行，但保留原始行号（rowSpans 用的是原始网格的行索引）
  final rows = <List<String>>[];
  final origRow = <int>[];
  for (var r = 0; r < grid.length; r++) {
    final row = grid[r].map((c) => c.trim()).toList();
    if (row.any((c) => c.isNotEmpty)) {
      rows.add(row);
      origRow.add(r);
    }
  }
  if (rows.isEmpty) return const [];

  // 找表头行：星期词最多的一行
  var headerIdx = -1;
  var headerCols = <int, int>{}; // 列号 → 星期
  var best = 0;
  for (var i = 0; i < rows.length && i < 6; i++) {
    final cols = <int, int>{};
    for (var j = 0; j < rows[i].length; j++) {
      final wd = weekdayFromWord(rows[i][j]);
      if (wd != null) cols[j] = wd;
    }
    if (cols.length > best) {
      best = cols.length;
      headerIdx = i;
      headerCols = cols;
    }
  }
  final out = <Course>[];
  if (headerIdx < 0 || headerCols.length < 2) return out;

  // 解析一行行首标签（星期列之前的格子）→ 节次/时间
  (int?, int?, int?, int?) rowLabelOf(List<String> row) {    int? sp, ep;
    int? rsMin, reMin;
    final labelCol = headerCols.keys.reduce((a, b) => a < b ? a : b);
    for (var j = 0; j < labelCol && j < row.length; j++) {
      final p = parseCellText(row[j]);
      if (p.startPeriod != null) {
        sp = p.startPeriod;
        ep = p.endPeriod;
      }
      if (p.startMin != null) {
        rsMin = p.startMin;
        reMin = p.endMin;
      }
    }
    return (sp, ep, rsMin, reMin);
  }

  for (var i = headerIdx + 1; i < rows.length; i++) {
    final row = rows[i];
    final (sp0, ep0, rowStartMin, rowEndMin) = rowLabelOf(row);
    final sp = sp0;
    final ep = ep0;
    for (final e in headerCols.entries) {
      final col = e.key;
      if (col >= row.length) continue;
      final cell = row[col];
      if (cell.isEmpty) continue;
      final p = parseCellText(cell);
      int sm, em;
      if (p.startMin != null) {
        sm = p.startMin!;
        em = p.endMin!;
      } else if (p.startPeriod != null) {
        final t = periodsToMinutes(p.startPeriod!, p.endPeriod!, periods);
        sm = t.$1;
        em = t.$2;
      } else if (sp != null) {
        // 合并单元格的连堂：跨度覆盖到哪一行，结束节就取到那一行的行标签
        var endP = ep ?? sp;
        final span = rowSpans?[(origRow[i], col)];
        if (span != null && span > 1) {
          final lastRow = math.min(i + span - 1, rows.length - 1);
          for (var k = i + 1; k <= lastRow; k++) {
            final (sp2, ep2, _, _) = rowLabelOf(rows[k]);
            final cand = ep2 ?? sp2;
            if (cand != null && cand > endP) endP = cand;
          }
        }
        final t = periodsToMinutes(sp, endP, periods);
        sm = t.$1;
        em = t.$2;
      } else if (rowStartMin != null) {
        sm = rowStartMin;
        em = rowEndMin ?? rowStartMin;
      } else {
        continue; // 定不出时间，放弃这个格子
      }
      out.add(Course(
        name: p.name.isEmpty ? cell.trim() : p.name,
        teacher: p.teacher,
        location: p.location,
        weekday: e.value,
        startMin: sm,
        endMin: em,
        weekStart: p.weekStart,
        weekEnd: p.weekEnd,
      ));
    }
  }
  return out;
}

/// 自由文本（整段复制/OCR 重建的行）→ 课程列表。
/// 支持「周一 1-16周 第1-2节 高等数学 A201」这类行；
/// 也支持带表头的制表符/多空格分隔的伪表格。
List<Course> parseLooseText(String text, List<(int, int)> periods) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((e) => e.replaceAll('\r', '').trimRight()) // 保留行首空白：制表符对齐靠它
      .where((e) => e.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) return const [];

  // A) 伪表格：某一行 ≥2 个星期词 → 表头；后面每行按分隔符拆格子
  for (var h = 0; h < lines.length; h++) {
    final words = lines[h]
        .split(RegExp(r'[\t|\s]+'))
        .where((t) => weekdayFromWord(t) != null)
        .length;
    if (words >= 2) {
      final header = lines[h].split(RegExp(r'[\t|\s]{1,}'));
      // 用格子数对齐表头里的星期词
      final cols = <int, int>{};
      for (var j = 0; j < header.length; j++) {
        final wd = weekdayFromWord(header[j]);
        if (wd != null) cols[j] = wd;
      }
      if (cols.length < 2) continue;
      final out = <Course>[];
      for (var i = h + 1; i < lines.length; i++) {
        final cells = lines[i].split(RegExp(r'\t|\s{2,}|\|'));
        int? sp, ep;
        final first = cells.isNotEmpty ? cells.first : '';
        final p0 = parseCellText(first);
        sp = p0.startPeriod;
        ep = p0.endPeriod;
        for (final e in cols.entries) {
          if (e.key >= cells.length) continue;
          final cell = cells[e.key].trim();
          if (cell.isEmpty) continue;
          final p = parseCellText(cell);
          int sm, em;
          if (p.startMin != null) {
            sm = p.startMin!;
            em = p.endMin!;
          } else if (p.startPeriod != null) {
            final t = periodsToMinutes(p.startPeriod!, p.endPeriod!, periods);
            sm = t.$1;
            em = t.$2;
          } else if (sp != null) {
            final t = periodsToMinutes(sp, ep ?? sp, periods);
            sm = t.$1;
            em = t.$2;
          } else {
            continue;
          }
          out.add(Course(
            name: p.name.isEmpty ? cell : p.name,
            teacher: p.teacher,
            location: p.location,
            weekday: e.value,
            startMin: sm,
            endMin: em,
            weekStart: p.weekStart,
            weekEnd: p.weekEnd,
          ));
        }
      }
      if (out.isNotEmpty) return out;
    }
  }

  // B) 每行自带星期：「周一 第1-2节 1-16周 高等数学 A201」
  final out = <Course>[];
  for (final line in lines) {
    final wd = weekdayFromWord(line);
    if (wd == null) continue;
    final p = parseCellText(line);
    if (p.name.isEmpty) continue;
    int sm, em;
    if (p.startMin != null) {
      sm = p.startMin!;
      em = p.endMin!;
    } else if (p.startPeriod != null) {
      final t = periodsToMinutes(p.startPeriod!, p.endPeriod!, periods);
      sm = t.$1;
      em = t.$2;
    } else {
      continue;
    }
    out.add(Course(
      name: p.name,
      teacher: p.teacher,
      location: p.location,
      weekday: wd,
      startMin: sm,
      endMin: em,
      weekStart: p.weekStart,
      weekEnd: p.weekEnd,
    ));
  }
  return out;
}

/// OCR 的一行文本及其包围盒（与具体 OCR 引擎解耦，方便单元测试）
class OcrTextLine {
  const OcrTextLine(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left, top, right, bottom;
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
  double get height => bottom - top;
}

bool _startsLatin(String t) => RegExp(r'^[A-Za-z0-9]').hasMatch(t);
bool _endsLatin(String t) => RegExp(r'[A-Za-z0-9]$').hasMatch(t);

/// 拼接被 OCR 拆行的课程名：中文直接连，英文/数字之间补空格
String _joinOcrName(List<String> parts) {
  final buf = StringBuffer();
  for (final p in parts) {
    if (buf.isNotEmpty && _endsLatin(buf.toString()) && _startsLatin(p)) {
      buf.write(' ');
    }
    buf.write(p);
  }
  return buf.toString();
}

/// 把 OCR 原始行按 y 聚类成「视觉行」，同一水平线上的元素合并成一行。
/// 中文相邻不插空格，英文/数字之间补一个空格。
List<OcrTextLine> mergeOcrLines(List<OcrTextLine> elems) {
  if (elems.isEmpty) return const [];
  final avgH = elems.map((e) => e.height).reduce((a, b) => a + b) / elems.length;
  final tol = avgH * 0.6;
  final sorted = [...elems]..sort((a, b) {
    final d = a.top.compareTo(b.top);
    return d != 0 ? d : a.left.compareTo(b.left);
  });
  final out = <OcrTextLine>[];
  var cur = <OcrTextLine>[];
  var curY = sorted.first.cy;
  void flush() {
    if (cur.isEmpty) return;
    cur.sort((a, b) => a.left.compareTo(b.left));
    final text = _joinOcrName(cur.map((e) => e.text).toList());
    out.add(OcrTextLine(
      text,
      cur.map((e) => e.left).reduce(math.min),
      cur.map((e) => e.top).reduce(math.min),
      cur.map((e) => e.right).reduce(math.max),
      cur.map((e) => e.bottom).reduce(math.max),
    ));
    cur = <OcrTextLine>[];
  }

  for (final e in sorted) {
    if (cur.isNotEmpty && (e.cy - curY).abs() > tol) {
      flush();
      curY = e.cy;
    }
    cur.add(e);
  }
  flush();
  return out;
}

/// 表头元素 → 星期（1~7）。支持三种写法：
/// 「周一/星期四」字样；「11/09」日期（按当前年份推算）；「今天/今日」。
/// 「周三列写成今天」的课表靠日期和今天兜底。
int? weekdayFromHeaderToken(String raw) {
  var t = raw.trim();
  if (t.isEmpty || t.length > 14) return null;
  final hasToday = t.contains('今天') || t.contains('今日');
  if (hasToday) {
    t = t.replaceAll('今天', '').replaceAll('今日', '').trim();
  }
  final dm = RegExp(r'(\d{1,2})\s*[/.]\s*(\d{1,2})').firstMatch(t);
  if (dm != null) {
    final m = int.tryParse(dm.group(1)!);
    final d = int.tryParse(dm.group(2)!);
    if (m != null && d != null && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      try {
        final date = DateTime(DateTime.now().year, m, d);
        // 只有当日期之外没有别的文字（或只有星期词）时才认为是表头
        final rest = t.replaceFirst(dm.group(0)!, ' ').trim();
        final w = rest.length <= 6 ? weekdayFromWord(rest) : null;
        if (w != null) return w;
        if (rest.isEmpty) return date.weekday;
      } catch (_) {}
    }
    return null; // 日期夹在普通文字里（如「教404」变体），不是表头
  }
  if (hasToday && t.isEmpty) return DateTime.now().weekday;
  if (t.length <= 6) return weekdayFromWord(t);
  return null;
}

/// 长文本行（整条表头被 OCR 合并成一条，如 “周一 11/09 周二 11/10 …”）
/// 里含多个「周X」词时，按字符位置比例估算每个词的 x 锚点。优先级最低。
void _addSplitHeaderCandidates(
    String t, OcrTextLine l, List<(int, double, double, int)> cands) {
  if (t.length < 8 || t.length > 80) return;
  final hits =
      RegExp(r'周[一二三四五六日天]|星期[一二三四五六日天]').allMatches(t).toList();
  if (hits.length < 2) return;
  final seen = <int>{};
  for (final m in hits) {
    final wd = weekdayFromWord(m.group(0)!);
    if (wd == null || !seen.add(wd)) continue;
    final f = (m.start + m.end) / 2 / t.length;
    cands.add((wd, l.left + (l.right - l.left) * f, l.top, 3));
  }
}

/// 从 OCR 原始行里找「星期列头」的 x 锚点。
/// 识别不出的列（如写「今天」的周三列）按左右邻列插值补齐。
Map<int, double> headerAnchors(List<OcrTextLine> lines) {
  final now = DateTime.now();
  // (weekday, x, top, priority)：字样 0 < 日期 1 < 今天 2
  final cands = <(int, double, double, int)>[];
  for (final l in lines) {
    final t = l.text.trim();
    if (t.isEmpty || t.length > 14) {
      _addSplitHeaderCandidates(t, l, cands);
      continue;
    }
    final hasToday = t.contains('今天') || t.contains('今日');
    var rest = hasToday ? t.replaceAll('今天', '').replaceAll('今日', '').trim() : t;
    final dm = RegExp(r'(\d{1,2})\s*[/.]\s*(\d{1,2})').firstMatch(rest);
    int? fromDate;
    if (dm != null) {
      final m = int.tryParse(dm.group(1)!);
      final d = int.tryParse(dm.group(2)!);
      if (m != null && d != null && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        try {
          fromDate = DateTime(now.year, m, d).weekday;
        } catch (_) {}
      }
      rest = rest.replaceFirst(dm.group(0)!, ' ').trim();
    }
    final fromWord = rest.isNotEmpty && rest.length <= 6 ? weekdayFromWord(rest) : null;
    if (fromWord != null) {
      cands.add((fromWord, l.cx, l.top, 0));
    } else if (fromDate != null && rest.isEmpty) {
      cands.add((fromDate, l.cx, l.top, 1));
    } else if (hasToday && rest.isEmpty && fromDate == null) {
      cands.add((now.weekday, l.cx, l.top, 2));
    }
  }
  if (cands.isEmpty) return const {};
  // 同一个星期取最靠上（表头在最上面）且优先级最高的候选
  cands.sort((a, b) {
    final p = a.$4.compareTo(b.$4);
    return p != 0 ? p : a.$3.compareTo(b.$3);
  });
  final byWd = <int, double>{};
  for (final c in cands) {
    byWd.putIfAbsent(c.$1, () => c.$2);
  }
  // 按 x 排序后，把缺的星期（如「今天」列没认出来）按位置插值补上
  final sorted = byWd.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  final out = <int, double>{};
  for (var i = 0; i < sorted.length; i++) {
    out[sorted[i].key] = sorted[i].value;
    if (i + 1 < sorted.length) {
      final gap = sorted[i + 1].key - sorted[i].key;
      if (gap > 1 && gap <= 4) {
        for (var m = sorted[i].key + 1; m < sorted[i + 1].key; m++) {
          final f = (m - sorted[i].key) / gap;
          out[m] = sorted[i].value + (sorted[i + 1].value - sorted[i].value) * f;
        }
      }
    }
  }
  return out;
}

/// 行标签（节次列）→ (起始节, 结束节)。
/// 兼容「第1-2节」「1,2节」和裸数字「1」（部分教务 App 就写个数字）。
(int?, int?) _labelPeriods(String t) {
  final p = parseCellText(t);
  if (p.startPeriod != null) return (p.startPeriod, p.endPeriod);
  final m = RegExp(r'^\D{0,6}(\d{1,2})\D{0,2}$').firstMatch(t.trim());
  if (m != null) {
    final v = int.tryParse(m.group(1)!);
    if (v != null && v >= 1 && v <= 20) return (v, v);
  }
  return (null, null);
}

/// 把 OCR 元素的 x 区间投影聚成「列带」：课表格子纵向对齐，
/// 同一列的元素横向大量重叠，列与列之间有空隙。
/// 做法：扫描线求「覆盖数 ≥ 2」的密集段做核心（单个横跨整行的元素
/// 不会把相邻列粘起来），很近的核心合并成列。
/// 返回按 x 排序的 (left, right) 列表。注意：核心比真实列窄，
/// 元素按中心就近归属（见 gridFromOcrLines 的 colOf）。
List<(double, double)> ocrColumnBands(List<OcrTextLine> lines, double avgH) {
  final ivs = <(double, double)>[];
  for (final l in lines) {
    if (l.right - l.left >= 2) ivs.add((l.left, l.right));
  }
  if (ivs.length < 3) return const [];
  final evts = <(double, int)>[];
  for (final iv in ivs) {
    evts.add((iv.$1, 1));
    evts.add((iv.$2, -1));
  }
  // 同一坐标先 +1 后 -1：相接的区间视作连续
  evts.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : b.$2.compareTo(a.$2));
  final cores = <(double, double)>[];
  var count = 0;
  double? open;
  for (final e in evts) {
    final prev = count;
    count += e.$2;
    if (count >= 2 && open == null) open = e.$1;
    if (prev >= 2 && count < 2 && open != null) {
      cores.add((open, e.$1));
      open = null;
    }
  }
  if (cores.isEmpty) return const [];
  // 同一列不同行的核心偶尔断开，间隙很小（远小于列间空隙）才合并。
  // 不做「按成员撑满边界」——宽元素会把相邻列链式粘成一条。
  final mergeGap = avgH * 0.3;
  final merged = <(double, double)>[cores.first];
  for (var i = 1; i < cores.length; i++) {
    final last = merged.last;
    if (cores[i].$1 - last.$2 <= mergeGap) {
      merged[merged.length - 1] = (last.$1, math.max(last.$2, cores[i].$2));
    } else {
      merged.add(cores[i]);
    }
  }
  return merged;
}

/// 判断一条列带是不是「节次标签带」：成员里有一串连续的裸数字
/// （1、2、3…，节数列的特征）。课程格子里偶尔也有数字行，
/// 但凑不齐 5 个以上连续编号。
bool _isPeriodLabelBand(List<OcrTextLine> lines, (double, double) band) {
  final digits = <int>[];
  for (final l in lines) {
    if (l.cx < band.$1 || l.cx > band.$2) continue;
    final m = RegExp(r'^\d{1,2}$').firstMatch(l.text.trim());
    if (m == null) continue;
    final v = int.tryParse(m.group(0)!);
    if (v != null && v >= 1 && v <= 20) digits.add(v);
  }
  if (digits.length < 5) return false;
  digits.sort();
  for (var i = 1; i < digits.length; i++) {
    if (digits[i] != digits[i - 1] + 1) return false;
  }
  return true;
}

/// 从内容元素的 x 分布聚出课程列带，并用表头锚点给每条带标上星期。
/// 返回按 x 排序的 (left, right, weekday)；方案不可靠时返回 null，
/// 调用方退回表头锚点中点边界。
List<(double, double, int)>? _pickColumnBands(
    List<OcrTextLine> lines, List<MapEntry<int, double>> anchors, double avgH) {
  final bands = ocrColumnBands(lines, avgH);
  if (bands.length < 3) return null;
  // 节数标签带不参与标星期
  final cb = bands.where((b) => !_isPeriodLabelBand(lines, b)).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  if (cb.length < 3) return null;
  // 锚点 → 距离最近的列带
  final matched = <(int, double)>[]; // (weekday, 锚点x)
  final matchedBandIdx = <int>{};
  for (final a in anchors) {
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < cb.length; i++) {
      final d = a.value < cb[i].$1
          ? cb[i].$1 - a.value
          : (a.value > cb[i].$2 ? a.value - cb[i].$2 : 0.0);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best >= 0 && bestD <= avgH * 0.8) {
      matched.add((a.key, a.value));
      matchedBandIdx.add(best);
    }
  }
  // 锚点认得太少，或多个锚点挤进同一条带（列被粘成一条）→ 不可信
  if (matched.length < 2 || matchedBandIdx.length < matched.length) return null;
  // 碎带噪声过多也不可信
  if (cb.length > anchors.length + 3) return null;
  // 最小二乘拟合 weekday ≈ a + b·x：列距均匀，缺列头/缺整列都能插值补齐
  final n = matched.length;
  final sx = matched.fold(0.0, (s, e) => s + e.$2);
  final sy = matched.fold(0.0, (s, e) => s + e.$1);
  final sxx = matched.fold(0.0, (s, e) => s + e.$2 * e.$2);
  final sxy = matched.fold(0.0, (s, e) => s + e.$1 * e.$2);
  final den = n * sxx - sx * sx;
  if (den <= 1e-6) return null;
  final slope = (n * sxy - sx * sy) / den;
  final inter = (sy - slope * sx) / n;
  if (slope <= 0.001) return null;
  final wds = cb
      .map((b) => (inter + slope * (b.$1 + b.$2) / 2).round().clamp(1, 7))
      .toList();
  // 两列标出同一个星期 = 拟合已经失真
  if (wds.toSet().length != wds.length) return null;
  return [for (var i = 0; i < cb.length; i++) (cb[i].$1, cb[i].$2, wds[i])];
}

/// 按「星期列头锚点 + 行标签」把 OCR 原始行重建为课程网格。
/// 每列内部切成格子（一格=一门课，可跨多行节次）。
/// 除了课程列表，还尽力从行标签里识别截图自带作息时间
/// （如 “1 08:00 08:45”），识别不到返回 null。
(List<Course>, List<(int, int)>?) gridFromOcrLines(
    List<OcrTextLine> lines, Map<int, double> anchors, List<(int, int)> periods) {
  final sortedCols = anchors.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  if (sortedCols.isEmpty) return (const [], null);

  final avgH = lines.map((l) => l.height).reduce((a, b) => a + b) / lines.length;
  final cellGap = avgH * 0.8; // 格内换行间隙很小，格子之间的空隙比这大

  bool isHeaderLike(OcrTextLine l) =>
      weekdayFromHeaderToken(l.text) != null ||
      kWeekdayWords.keys.where(l.text.contains).length >= 2;

  // 周次/节次/时间信息（这种行是格子里的备注，不是新课的开头）
  bool hasInfo(String t) =>
      t.contains('周') || t.contains('节') || _timeRange.hasMatch(t);

  // —— 网格 y 窗口：网格上方的标题栏/状态栏（「课表查询」「第10周」等）
  // 和下方的页脚不参与列带与内容，否则会把相邻列桥接粘成一条 ——
  final lo0Fallback = sortedCols.length >= 2
      ? sortedCols[0].value -
          ((sortedCols[0].value + sortedCols[1].value) / 2 - sortedCols[0].value)
      : sortedCols[0].value - 40;
  final hdrTops = lines.where(isHeaderLike).map((l) => l.top).toList();
  final labelTops = <double>[];
  var labelBottomMax = -1.0;
  for (final l in lines) {
    if (l.cx >= lo0Fallback) continue;
    if (_labelPeriods(l.text.trim()).$1 != null) {
      labelTops.add(l.top);
      labelBottomMax = math.max(labelBottomMax, l.bottom);
    }
  }
  labelTops.sort();
  double labelPitch = 0;
  final double? gridTop =
      hdrTops.isNotEmpty ? hdrTops.reduce(math.min) - avgH * 0.3 : null;
  double? gridBottom;
  if (labelTops.length >= 3) {
    final ds = <double>[
      for (var i = 1; i < labelTops.length; i++) labelTops[i] - labelTops[i - 1]
    ]..sort();
    labelPitch = ds[ds.length ~/ 2];
    gridBottom = labelBottomMax + labelPitch * 0.8;
  }
  bool inGrid(OcrTextLine l) =>
      (gridTop == null || l.bottom > gridTop) &&
      (gridBottom == null || l.top < gridBottom);

  // —— 列切分，首选「内容列带」方案：课表格子纵向对齐，同一列的元素横向
  // 高度重叠、列与列之间有空隙，按 x 投影聚出的列带比表头锚点的两两中点
  // 更可靠；表头锚点只负责给列带标星期。方案不可靠时退回表头中点边界。
  final gridLines = lines.where((l) => !isHeaderLike(l) && inGrid(l)).toList();
  final contentBands = _pickColumnBands(gridLines, sortedCols, avgH);
  // 第一列的左边界：列带方案用第一条内容带（核心）的左缘略放宽；
  // 中点方案按与第二列的间距对称外推，防止第一列内容被当标签丢掉
  final double lo0;
  if (contentBands != null) {
    lo0 = contentBands.first.$1 - avgH * 0.3;
  } else {
    lo0 = lo0Fallback;
  }

  int? colOf(double x) {
    if (x < lo0) return null; // 节次标签区
    final cb = contentBands;
    if (cb != null) {
      int? best;
      var bestD = double.infinity;
      for (var i = 0; i < cb.length; i++) {
        final b = cb[i];
        final d = x < b.$1 ? b.$1 - x : (x > b.$2 ? x - b.$2 : 0.0);
        if (d < bestD) {
          bestD = d;
          best = b.$3;
        }
      }
      return bestD <= avgH * 1.2 ? best : null;
    }
    for (var i = 0; i < sortedCols.length; i++) {
      final lo = i == 0 ? lo0 : (sortedCols[i - 1].value + sortedCols[i].value) / 2;
      final hi = i == sortedCols.length - 1
          ? double.infinity
          : (sortedCols[i].value + sortedCols[i + 1].value) / 2;
      if (x >= lo && x < hi) return sortedCols[i].key;
    }
    return null;
  }

  // 行标签（第一列左边）：节次数字和/或作息时间
  final labelLines = lines.where((l) => l.cx < lo0 && l.text.length <= 10).toList()
    ..sort((a, b) => a.top.compareTo(b.top));

  // 从行标签里顺带识别作息时间：「1 / 08:00 / 08:45」竖排，时间跟在节次数字下面
  final timeBuf = <int, List<int>>{};
  int? lastNum;
  double lastNumCy = -999;
  for (final lab in labelLines) {
    final t = lab.text.trim();
    final single = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    final pair = RegExp(r'^(\d{1,2}):(\d{2})\s+(\d{1,2}):(\d{2})$').firstMatch(t);
    if (single != null || pair != null) {
      if (lastNum == null || (lab.cy - lastNumCy).abs() > avgH * 4) continue;
      void add(int h, int m) {
        if (h < 24 && m < 60) timeBuf.putIfAbsent(lastNum!, () => []).add(h * 60 + m);
      }
      if (pair != null) {
        add(int.parse(pair.group(1)!), int.parse(pair.group(2)!));
        add(int.parse(pair.group(3)!), int.parse(pair.group(4)!));
      } else {
        add(int.parse(single!.group(1)!), int.parse(single.group(2)!));
      }
      continue;
    }
    final (lsp, _) = _labelPeriods(t);
    if (lsp != null) {
      lastNum = lsp;
      lastNumCy = lab.cy;
    }
  }
  List<(int, int)>? detected;
  if (timeBuf.length >= 3) {
    final nums = timeBuf.keys.toList()..sort();
    var ok = nums.first == 1;
    for (var i = 1; i < nums.length; i++) {
      if (nums[i] != nums[i - 1] + 1) ok = false;
    }
    final built = <(int, int)>[];
    (int, int)? prev;
    for (final n in nums) {
      final ts = timeBuf[n]!..sort();
      var st = ts.first, en = ts.last;
      if (en < st) (st, en) = (en, st);
      if (prev != null && st <= prev.$1) ok = false;
      // 个别节次缺时间（极少）：沿用上一节时长补齐
      while (ok && built.length + 1 < n) {
        final dur = prev == null ? 45 : prev.$2 - prev.$1;
        final base = prev?.$2 ?? 525;
        built.add((base + 1, base + 1 + (dur <= 0 ? 45 : dur)));
      }
      built.add((st, en));
      prev = (st, en);
    }
    if (ok) detected = built;
  }

  final byCol = <int, List<OcrTextLine>>{};
  for (final l in gridLines) {
    final col = colOf(l.cx);
    if (col == null) continue;
    byCol.putIfAbsent(col.toInt(), () => []).add(l);
  }

  final out = <Course>[];
  for (final e in byCol.entries) {
    final colLines = e.value
      ..sort((a, b) {
        // 同一视觉行的元素 top 可能差 1~2px，按半行高聚带后再按 x 排，
        // 保证「大学英语」「III-1」这类同层元素按从左到右拼接。
        final band = (a.height + b.height) / 4;
        final da = (a.cy / band).round().compareTo((b.cy / band).round());
        return da != 0 ? da : a.left.compareTo(b.left);
      });

    // 先把列内文本行切成格子组：
    // 1) 行距突变（格子之间有空隙）；2) 这类 App 的格子紧贴着排，
    //    靠「@教室」行做边界——@ 行（及其后续门牌号数字行）之后
    //    出现新的文字行就是下一门课。
    final groups = <List<OcrTextLine>>[];
    var group = <OcrTextLine>[];
    var seenRoom = false;
    for (final l in colLines) {
      final t = l.text.trim();
      final isRoom = t.contains('@');
      // 「@教室」行之后的短行是换行拆开的地点续接（如 “场”“-309”“27”），
      // 但必须是紧贴着的行——有间隙说明是下一门课的开头
      final cont = seenRoom &&
          !isRoom &&
          !hasInfo(t) &&
          group.isNotEmpty &&
          l.top - group.last.bottom <= avgH * 0.45 &&
          (RegExp(r'^-?\d{1,4}$').hasMatch(t) || t.length <= 2);
      final hasText = RegExp(r'[A-Za-z0-9\u4e00-\u9fa5]').hasMatch(t);
      final gapSplit = group.isNotEmpty && l.top - group.last.bottom > cellGap;
      // 新行本身也是「@教室」行：是同一格混进的两条教室行（x 切分误差），
      // 不拆组，交给 parseCellText 取最完整的一个
      final roomSplit = group.isNotEmpty &&
          seenRoom &&
          hasText &&
          !isRoom &&
          !cont &&
          !hasInfo(t);
      if (gapSplit || roomSplit) {
        groups.add(group);
        group = <OcrTextLine>[];
        seenRoom = false;
      }
      group.add(l);
      if (isRoom) seenRoom = true;
    }
    if (group.isNotEmpty) groups.add(group);

    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      if (ocrDebug) {
        // ignore: avoid_print
        print('DBG col=${e.key} group=${g.map((x) => x.text).join('/')}');
      }
      final top = g.map((x) => x.top).reduce(math.min);
      final bottom = g.map((x) => x.bottom).reduce(math.max);
      final text = g.map((x) => x.text).join('\n');
      final p = parseCellText(text);
      // 找覆盖这个 y 区间的行标签 → 节次。
      // 跨多行的大格子文字只占上半部分：若下一组紧贴着（间隙很小），
      // 用下一组的顶端所在行的行首当本格底边，节次能认得更全
      // （切口不能吃进下一组的行标签）。
      var labelHi = bottom + cellGap;
      if (gi + 1 < groups.length) {
        final nextTop = groups[gi + 1].map((x) => x.top).reduce(math.min);
        if (nextTop >= bottom && nextTop - bottom <= avgH * 2.5) {
          labelHi = math.max(labelHi, nextTop - (labelPitch > 0 ? labelPitch * 0.35 : 1));
        }
      }
      int? sp, ep;
      for (final lab in labelLines) {
        if (lab.cy >= top - cellGap && lab.cy <= labelHi) {
          final (lsp, lep) = _labelPeriods(lab.text);
          if (lsp != null) {
            if (sp == null) {
              sp = lsp;
              ep = lep ?? lsp;
            } else if (lsp >= sp) {
              // 跨多行的格子：ep 跟随范围内最后一个行标签（如 1、2 两行 → 1-2 节）
              ep = lep ?? lsp;
            }
          }
        }
      }
      int sm, em;
      if (p.startMin != null) {
        sm = p.startMin!;
        em = p.endMin!;
      } else if (p.startPeriod != null) {
        final t = periodsToMinutes(p.startPeriod!, p.endPeriod!, periods);
        sm = t.$1;
        em = t.$2;
      } else if (sp != null) {
        final t = periodsToMinutes(sp, ep ?? sp, periods);
        sm = t.$1;
        em = t.$2;
      } else {
        continue;
      }
      // 名字得有汉字/字母，过滤「+」之类的按钮误识别
      if (p.name.isNotEmpty &&
          weekdayFromWord(p.name) == null &&
          RegExp(r'[A-Za-z\u4e00-\u9fa5]').hasMatch(p.name)) {
        out.add(Course(
          name: p.name,
          teacher: p.teacher,
          location: p.location,
          weekday: e.key,
          startMin: sm,
          endMin: em,
          weekStart: p.weekStart,
          weekEnd: p.weekEnd,
        ));
      }
    }
  }
  return (out, detected);
}
