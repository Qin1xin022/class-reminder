import 'dart:convert';
import 'dart:io';

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

  // xlsx（PK 头 = zip）
  if (name.endsWith('.xlsx') || (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B)) {
    try {
      final dec = SpreadsheetDecoder.decodeBytes(bytes);
      final grid = _sheetToGrid(dec.tables[dec.tables.keys.first]?.rows);
      final list = parseGrid(grid, periods);
      if (list.isNotEmpty) return list;
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
