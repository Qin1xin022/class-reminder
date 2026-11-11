import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../models.dart';
import 'timetable_parser.dart';

/// 从文件（xlsx/csv/html/json）解析课程草稿。
/// 教务系统导出的表格式五花八门，所以解析顺序是：
/// json → xlsx → csv → html（很多“xls”其实是伪装成 Excel 的 HTML），全部失败就报错。
Future<List<Course>> parseCourseFile(String path, List<(int, int)> periods) async {
  final bytes = await File(path).readAsBytes();
  if (bytes.isEmpty) return const [];
  final name = path.toLowerCase();

  // json：本 App 的备份格式（settings + courses）或纯课程数组
  if (name.endsWith('.json')) {
    return _fromJson(utf8.decode(bytes, allowMalformed: true), periods);
  }

  // xlsx（PK 头 = zip）。
  // 优先用自研解析：spreadsheet_decoder 不提供合并单元格范围，而教务导出的
  // 课表用「纵向合并」表示连堂课（一格占第1~4节，值只在首行），不读
  // mergeCells 会把连堂课当成第一节的单节课。
  if (name.endsWith('.xlsx') || (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B)) {
    try {
      final parsed = decodeXlsxWithMerges(bytes);
      if (parsed != null && parsed.isNotEmpty) {
        final sheets = <String, List<List<String>>>{
          for (final s in parsed) s.name: s.grid,
        };
        final spans = <String, Map<(int, int), int>>{
          for (final s in parsed)
            if (s.rowSpans.isNotEmpty) s.name: s.rowSpans,
        };
        final list = aggregateWorkbook(sheets, periods, sheetRowSpans: spans);
        if (list.isNotEmpty) return list;
      }
      // 兜底：spreadsheet_decoder（无合并信息，解析单节课程仍然正确）
      final dec = SpreadsheetDecoder.decodeBytes(bytes);
      final sheets = <String, List<List<String>>>{
        for (final k in dec.tables.keys) k: _sheetToGrid(dec.tables[k]?.rows),
      };
      final list = aggregateWorkbook(sheets, periods);
      if (list.isNotEmpty) return list;
      final grid = _sheetToGrid(dec.tables[dec.tables.keys.first]?.rows);
      return parseLooseText(grid.map((r) => r.join('\t')).join('\n'), periods);
    } catch (_) {
      // 掉到下面的通用尝试
    }
  }

  final text = utf8.decode(bytes, allowMalformed: true);

  // csv
  if (name.endsWith('.csv') || name.endsWith('.tsv')) {
    final grid = name.endsWith('.tsv')
        ? text.split(RegExp(r'\r?\n')).map((l) => l.split('\t')).toList()
        : _decodeCsv(text);
    final list = parseGrid(grid, periods);
    if (list.isNotEmpty) return list;
    return parseLooseText(text, periods);
  }

  // html（含伪装成 xls 的）
  if (name.endsWith('.htm') || name.endsWith('.html') || name.endsWith('.xls')) {
    final grid = _decodeHtml(text);
    if (grid.isNotEmpty) {
      final list = parseGrid(grid, periods);
      if (list.isNotEmpty) return list;
    }
  }

  // 最后兜底：当纯文本处理（教务网页复制的表格文本也能走这里）
  final loose = parseLooseText(text, periods);
  if (loose.isNotEmpty) return loose;
  // 试着把整个文件按 html 解一遍（有些 xlsx 请求失败但其实内容是 html）
  final grid = _decodeHtml(text);
  if (grid.isNotEmpty) {
    final list = parseGrid(grid, periods);
    if (list.isNotEmpty) return list;
    return parseLooseText(grid.map((r) => r.join('\t')).join('\n'), periods);
  }
  return const [];
}

List<Course> _fromJson(String raw, List<(int, int)> periods) {
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  List<dynamic> list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map && decoded['courses'] is List) {
    list = decoded['courses'] as List;
  } else {
    return const [];
  }
  final out = <Course>[];
  for (final e in list) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    // 兼容 snake_case（备份）与 camelCase（种子）两种键
    final name = (m['name'] ?? m['name'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final weekday = _asInt(m['weekday']) ?? 1;
    final sm = _asInt(m['startMin'] ?? m['start_min']) ?? 480;
    final em = _asInt(m['endMin'] ?? m['end_min']) ?? sm + 50;
    var color = _asInt(m['color']) ?? 0xFF4C6FFF;
    final colorStr = m['color']?.toString();
    if (colorStr != null && colorStr.startsWith('0x')) {
      color = int.tryParse(colorStr) ?? color;
    }
    if (color < 0xFF000000) color |= 0xFF000000;
    out.add(Course(
      name: name,
      teacher: (m['teacher'] ?? '').toString(),
      location: (m['location'] ?? '').toString(),
      weekday: weekday.clamp(1, 7),
      startMin: sm,
      endMin: em,
      weekStart: _asInt(m['weekStart'] ?? m['week_start']) ?? 1,
      weekEnd: _asInt(m['weekEnd'] ?? m['week_end']) ?? 16,
      color: color,
      remind: (m['remind'] ?? '30,15').toString(),
    ));
  }
  return out;
}

int? _asInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

List<List<String>> _sheetToGrid(List<List<dynamic>>? rows) {
  if (rows == null) return const [];
  return [
    for (final r in rows)
      [for (final c in r) (c ?? '').toString()],
  ];
}

/// 自研 xlsx 解析：带纵向合并单元格的行跨度。
/// 教务导出的课表用合并单元格表示连堂（如 C2:C5 = 周二第1~4节），
/// 第三方表格库只把值放在首行、拿不到合并范围，连堂课会被当成一节的课。
class _XlsxSheet {
  _XlsxSheet(this.name, this.grid, this.rowSpans);
  final String name;
  final List<List<String>> grid;
  final Map<(int, int), int> rowSpans; // (行0基, 列0基) → 向下覆盖行数
}

/// "C5" → (列0基=2, 行0基=4)
(int, int) _xlsxRefToRC(String ref) {
  var col = 0;
  var row = 0;
  for (var i = 0; i < ref.length; i++) {
    final ch = ref.codeUnitAt(i);
    if (ch >= 0x41 && ch <= 0x5A) {
      col = col * 26 + (ch - 0x40);
    } else if (ch >= 0x61 && ch <= 0x7A) {
      col = col * 26 + (ch - 0x60);
    } else if (ch >= 0x30 && ch <= 0x39) {
      row = row * 10 + (ch - 0x30);
    } else {
      break;
    }
  }
  return (col - 1, row - 1);
}

String _xmlUnescape(String s) {
  if (!s.contains('&')) return s;
  return s
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// 解析一个 `<si>` 条目：可能是 `<t>` 或富文本 `<r><t>..</t></r>…`，全部拼接
List<String> _parseSharedStrings(String xml) {
  final out = <String>[];
  for (final m in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(xml)) {
    final ts = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
        .allMatches(m.group(1)!)
        .map((t) => _xmlUnescape(t.group(1)!))
        .join();
    out.add(ts);
  }
  return out;
}

List<_XlsxSheet>? decodeXlsxWithMerges(List<int> bytes) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  ArchiveFile? findFile(String name) {
    final n = name.toLowerCase();
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name.toLowerCase() == n) return f;
    }
    return null;
  }

  String? readText(String name) {
    final f = findFile(name);
    if (f == null) return null;
    try {
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  final workbookXml = readText('xl/workbook.xml');
  final relsXml = readText('xl/_rels/workbook.xml.rels');
  if (workbookXml == null) return null;

  // sheet 名 → rId → 文件路径
  final relTarget = <String, String>{};
  if (relsXml != null) {
    for (final m in RegExp(
            r'<Relationship[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"[^>]*/?>')
        .allMatches(relsXml)) {
      var t = m.group(2)!;
      if (t.startsWith('/')) t = t.substring(1);
      if (!t.startsWith('xl/')) t = 'xl/$t';
      relTarget[m.group(1)!] = t;
    }
  }
  // r:id 属性可能带命名空间前缀（x14、r 等）
  final sheetRefs = <(String, String)>[]; // (name, rid)
  for (final m in RegExp(r'<sheet[^>]*/?>').allMatches(workbookXml)) {
    final tag = m.group(0)!;
    final name = RegExp(r'\bname="([^"]*)"').firstMatch(tag)?.group(1) ?? '';
    final rid = RegExp(r'\br:id="([^"]+)"').firstMatch(tag)?.group(1) ??
        RegExp(r'id="([^"]+)"').firstMatch(tag)?.group(1) ??
        '';
    if (name.isNotEmpty && rid.isNotEmpty) sheetRefs.add((name, rid));
  }

  final shared = _parseSharedStrings(readText('xl/sharedStrings.xml') ?? '');

  String cellValue(String attrs, String body) {
    final t = RegExp(r'\bt="(\w+)"').firstMatch(attrs)?.group(1);
    final isBody = RegExp(r'<is>(.*?)</is>', dotAll: true).firstMatch(body);
    if (t == 'inlineStr' && isBody != null) {
      return RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
          .allMatches(isBody.group(1)!)
          .map((m) => _xmlUnescape(m.group(1)!))
          .join();
    }
    // 注意 <v> 可能带属性（如 <v xml:space="preserve">，WPS 导出常见）
    final v = RegExp(r'<v[^>]*>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1);
    if (v == null) return '';
    final raw = _xmlUnescape(v);
    if (t == 's') {
      final i = int.tryParse(raw.trim());
      return (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
    }
    return raw; // str / n / 其他：直接用缓存值
  }

  final out = <_XlsxSheet>[];
  for (final (name, rid) in sheetRefs) {
    final path = relTarget[rid];
    if (path == null) continue;
    final xml = readText(path);
    if (xml == null) continue;

    final cells = <(int, int), String>{}; // (row0, col0) → text
    var maxR = 0, maxC = 0;
    for (final rm in RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true)
        .allMatches(xml)) {
      for (final cm in RegExp(r'<c\s([^>]*?)/>|<c\s([^>]*?)>(.*?)</c>',
              dotAll: true)
          .allMatches(rm.group(1)!)) {
        final attrs = cm.group(1) ?? cm.group(2) ?? '';
        final body = cm.group(3) ?? '';
        final ref = RegExp(r'\br="([A-Za-z]+\d+)"').firstMatch(attrs)?.group(1);
        if (ref == null) continue;
        final (c0, r0) = _xlsxRefToRC(ref);
        final text = cellValue(attrs, body);
        if (text.isEmpty) continue;
        cells[(r0, c0)] = text;
        if (r0 > maxR) maxR = r0;
        if (c0 > maxC) maxC = c0;
      }
    }
    if (cells.isEmpty) continue;

    // 合并单元格 → 首格的纵向跨度
    final spans = <(int, int), int>{};
    for (final mm in RegExp(r'<mergeCell[^>]*ref="([^"]+)"').allMatches(xml)) {
      final parts = mm.group(1)!.split(':');
      if (parts.isEmpty) continue;
      final (c0, r0) = _xlsxRefToRC(parts[0]);
      var rEnd = r0;
      if (parts.length == 2) {
        final (_, r1) = _xlsxRefToRC(parts[1]);
        rEnd = math.max(r0, r1);
      }
      if (rEnd > r0 && cells.containsKey((r0, c0))) {
        // 只在「向下跨行」时记跨度；同行多列的水平合并不影响节次
        spans[(r0, c0)] = rEnd - r0 + 1;
      }
    }

    final grid = List.generate(
        maxR + 1,
        (r) => List.generate(
            maxC + 1, (c) => cells[(r, c)] ?? '', growable: false),
        growable: false);
    out.add(_XlsxSheet(name, grid, spans));
  }
  return out;
}

/// 把工作簿里所有 sheet 都解一遍再合并。
/// 有的教务 App 导出的是「每周一页」：sheet 名叫 第1周~第20周，每周只有
/// 该周上的课——只读第一个 sheet 会因为那一周恰好没课而「认不出课程」。
/// sheet 名带「第N周」的，把同一门课在各个周的出现合并成连续周次范围；
/// 不带的 sheet 直接并进结果。
List<Course> aggregateWorkbook(
    Map<String, List<List<String>>> sheets, List<(int, int)> periods,
    {Map<String, Map<(int, int), int>>? sheetRowSpans}) {
  final plain = <Course>[];
  final perWeek = <int, Map<String, Course>>{};
  for (final e in sheets.entries) {
    final list = parseGrid(e.value, periods,
        rowSpans: sheetRowSpans?[e.key]);
    if (list.isEmpty) continue;
    final wk = _weekFromSheetName(e.key);
    if (wk == null) {
      plain.addAll(list);
      continue;
    }
    final bucket = perWeek.putIfAbsent(wk, () => {});
    for (final c in list) {
      final key =
          '${c.name}|${c.weekday}|${c.startMin}|${c.endMin}|${c.location}|${c.teacher}';
      bucket[key] = c;
    }
  }
  final agg = <String, Course>{};
  // 不带周次的 sheet（汇总表/总课表）先入，避免被周次 sheet 挤出结果
  for (final c in plain) {
    final key =
        '${c.name}|${c.weekday}|${c.startMin}|${c.endMin}|${c.location}|${c.teacher}';
    agg[key] = c;
  }
  perWeek.forEach((wk, bucket) {
    bucket.forEach((key, c) {
      // 格子文本里明确写了周次（不是默认的 1-16）就以文本为准，
      // 否则用 sheet 名里的周次
      final hasOwnWeeks = c.weekStart != 1 || c.weekEnd != 16;
      final ws = hasOwnWeeks ? c.weekStart : wk;
      final we = hasOwnWeeks ? c.weekEnd : wk;
      final prev = agg[key];
      if (prev == null) {
        agg[key] = _withWeeks(c, ws, we);
      } else {
        agg[key] = _withWeeks(prev, math.min(prev.weekStart, ws),
            math.max(prev.weekEnd, we));
      }
    });
  });
  return agg.values.toList();
}

int? _weekFromSheetName(String name) {
  final m = RegExp(r'第\s*(\d{1,2})\s*周').firstMatch(name) ??
      RegExp(r'(\d{1,2})\s*周').firstMatch(name) ??
      RegExp(r'week\s*(\d{1,2})', caseSensitive: false).firstMatch(name);
  if (m == null) return null;
  final v = int.tryParse(m.group(1)!);
  return (v != null && v >= 1 && v <= 30) ? v : null;
}

Course _withWeeks(Course c, int ws, int we) => Course(
      name: c.name,
      teacher: c.teacher,
      location: c.location,
      weekday: c.weekday,
      startMin: c.startMin,
      endMin: c.endMin,
      weekStart: ws,
      weekEnd: we,
      color: c.color,
      remind: c.remind,
    );

/// 极简 CSV 解析：支持引号包裹、逗号/分号分隔
List<List<String>> _decodeCsv(String raw) {
  final text = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
  final rows = <List<String>>[];
  final cell = StringBuffer();
  var row = <String>[];
  var inQuote = false;
  // 判断分隔符：取第一行里逗号和分号出现多的那个
  final firstLine = text.split(RegExp(r'\r?\n')).first;
  final sep = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? ';' : ',';
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuote) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuote = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      inQuote = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// 从 HTML 里抠出第一个较大的表格（教务导出的 “xls” 多是 HTML）
List<List<String>> _decodeHtml(String raw) {
  final tables = RegExp(r'<table[^>]*>([\s\S]*?)</table>', caseSensitive: false)
      .allMatches(raw)
      .toList();
  List<List<String>>? best;
  var bestCells = 0;
  for (final t in tables) {
    final body = t.group(1)!;
    final rows = <List<String>>[];
    for (final tr in RegExp(r'<tr[^>]*>([\s\S]*?)</tr>', caseSensitive: false)
        .allMatches(body)) {
      final cells = <String>[];
      for (final td in RegExp(r'<t[dh][^>]*>([\s\S]*?)</t[dh]>', caseSensitive: false)
          .allMatches(tr.group(1)!)) {
        cells.add(_htmlToText(td.group(1)!));
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    final n = rows.fold(0, (a, r) => a + r.length);
    if (n > bestCells) {
      bestCells = n;
      best = rows;
    }
  }
  return best ?? const [];
}

String _htmlToText(String raw) {
  var t = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  const entities = {
    '&nbsp;': ' ', '&amp;': '&', '&lt;': '<', '&gt;': '>',
    '&quot;': '"', '&#39;': "'", '&apos;': "'",
  };
  entities.forEach((k, v) => t = t.replaceAll(k, v));
  t = t.replaceAllMapped(
      RegExp(r'&#(\d+);'), (Match m) => String.fromCharCode(int.parse(m.group(1)!)));
  // 合并多余空格但保留换行
  final lines = t.split('\n').map((l) => l.trim().replaceAll(RegExp(r'\s+'), ' ').trim()).toList();
  return lines.where((l) => l.isNotEmpty).join('\n');
}
