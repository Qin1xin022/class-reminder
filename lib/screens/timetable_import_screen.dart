import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../services/timetable_file_import.dart';
import '../services/timetable_parser.dart';

/// 课表导入预览：识别出的课程草稿先摆出来让用户核对，
/// 每条可勾选/修改，确认后才写库。识别有误差也不怕导错。
class TimetableImportScreen extends StatefulWidget {
  const TimetableImportScreen({
    super.key,
    required this.candidates,
    required this.sourceLabel,
  });

  final List<Course> candidates;
  final String sourceLabel;

  @override
  State<TimetableImportScreen> createState() => _TimetableImportScreenState();
}

class _TimetableImportScreenState extends State<TimetableImportScreen> {
  late List<Course> _list;
  late List<bool> _sel;

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.candidates);
    _sel = List.filled(_list.length, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final count = _sel.where((e) => e).length;
    return Scaffold(
      appBar: AppBar(title: Text('核对课表（${widget.sourceLabel}）')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '识别到 ${_list.length} 门课，可能有误差。点任意一条可以改，'
              '取消勾选的不会导入。导入后周次按「开学第一周周一」(${s.termStart}) 计算。',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: context.faint),
            ),
          ),
          Expanded(
            child: _list.isEmpty
                ? Center(
                    child: Text('没有识别出课程，换个截图/文件试试',
                        style: TextStyle(color: context.faint)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    itemCount: _list.length,
                    itemBuilder: (_, i) => _card(context, i),
                  ),
          ),
          if (_list.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        final all = _sel.every((e) => e);
                        for (var i = 0; i < _sel.length; i++) {
                          _sel[i] = !all;
                        }
                      }),
                      child: Text(_sel.every((e) => e) ? '全不选' : '全选'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.check, size: 18),
                      label: Text('导入所选 ($count)'),
                      onPressed: count == 0 ? null : _import,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, int i) {
    final c = _list[i];
    final color = Color(c.color);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: CheckboxListTile(
        value: _sel[i],
        onChanged: (v) => setState(() => _sel[i] = v ?? true),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        title: Text(
          c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${weekdayLabel(c.weekday)} ${hhmm(c.startMin)}-${hhmm(c.endMin)}'
          ' · ${c.weekStart}-${c.weekEnd}周'
          '${c.location.isEmpty ? '' : ' · ${c.location}'}'
          '${c.teacher.isEmpty ? '' : ' · ${c.teacher}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, height: 1.4),
        ),
        secondary: GestureDetector(
          onTap: () => _edit(i),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.edit_outlined, size: 17),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(int i) async {
    final s = context.read<AppState>();
    final periods = s.periods;
    final c = _list[i];
    final nameCtrl = TextEditingController(text: c.name);
    final locCtrl = TextEditingController(text: c.location);
    final teacherCtrl = TextEditingController(text: c.teacher);
    var weekday = c.weekday;
    int startMin = c.startMin, endMin = c.endMin;
    var ws = c.weekStart, we = c.weekEnd;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('修改课程'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '课程名'),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: weekday,
                        decoration: const InputDecoration(labelText: '星期'),
                        items: [
                          for (var d = 1; d <= 7; d++)
                            DropdownMenuItem(value: d, child: Text(weekdayLabel(d))),
                        ],
                        onChanged: (v) => setD(() => weekday = v ?? 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        initialValue: '$ws-$we',
                        decoration: const InputDecoration(labelText: '周次，如 1-16'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final m = RegExp(r'(\d+)\D+(\d+)').firstMatch(v);
                          if (m != null) {
                            ws = int.parse(m.group(1)!);
                            we = int.parse(m.group(2)!);
                          }
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final t = await _pickTime(ctx, startMin);
                          if (t != null) setD(() => startMin = t);
                        },
                        child: Text('上课 ${hhmm(startMin)}'),
                      ),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('~')),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final t = await _pickTime(ctx, endMin);
                          if (t != null) setD(() => endMin = t);
                        },
                        child: Text('下课 ${hhmm(endMin)}'),
                      ),
                    ),
                  ]),
                  // 常用节次快捷按钮
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var p = 0;
                          p + 1 < periods.length;
                          p += 1)
                        ActionChip(
                          label: Text('第${p + 1}-${math.min(p + 2, periods.length)}节'),
                          onPressed: () => setD(() {
                            startMin = periods[p].$1;
                            endMin = periods[math.min(p + 1, periods.length - 1)].$2;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: locCtrl,
                    decoration: const InputDecoration(labelText: '地点（可空）'),
                  ),
                  TextField(
                    controller: teacherCtrl,
                    decoration: const InputDecoration(labelText: '老师（可空）'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('del'),
              child: const Text('删除这条', style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (ok == 'del') {
      setState(() {
        _list.removeAt(i);
        _sel.removeAt(i);
      });
      return;
    }
    if (ok == true) {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) return;
      setState(() {
        if (endMin <= startMin) endMin = startMin + 50;
        _list[i] = Course(
          name: name,
          teacher: teacherCtrl.text.trim(),
          location: locCtrl.text.trim(),
          weekday: weekday,
          startMin: startMin,
          endMin: endMin,
          weekStart: ws.clamp(1, 30),
          weekEnd: we.clamp(ws, 30),
          color: c.color,
          remind: c.remind,
        );
      });
    }
  }

  Future<int?> _pickTime(BuildContext ctx, int minutes) async {
    final t = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _import() async {
    final maps = <Map<String, Object?>>[];
    for (var i = 0; i < _list.length; i++) {
      if (!_sel[i]) continue;
      final c = _list[i];
      maps.add({
        'name': c.name,
        'teacher': c.teacher,
        'location': c.location,
        'weekday': c.weekday,
        'startMin': c.startMin,
        'endMin': c.endMin,
        'weekStart': c.weekStart,
        'weekEnd': c.weekEnd,
        'color': '${c.color}',
        'remind': c.remind,
      });
    }
    final r = await context.read<AppState>().importSeedCourses(maps);
    if (!mounted) return;
    Navigator.of(context).pop(r.added);
  }
}

// ---------------------------------------------------------------------------
// 入口：从文件 / 图片 / 粘贴文本 生成候选课程
// ---------------------------------------------------------------------------

/// 弹出导入方式选择，返回导入条数（null=用户取消）
Future<int?> showTimetableImportMenu(BuildContext context) async {
  final mode = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('从文件导入'),
            subtitle: const Text('教务系统导出的 xlsx / csv / html / json',
                style: TextStyle(fontSize: 11.5)),
            onTap: () => Navigator.of(ctx).pop('file'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('从图片导入'),
            subtitle: const Text('对着课表截图拍照/选图，手机本地识别，不上传',
                style: TextStyle(fontSize: 11.5)),
            onTap: () => Navigator.of(ctx).pop('image'),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste_outlined),
            title: const Text('从粘贴的文本导入'),
            subtitle: const Text('在教务网站全选复制课表，粘过来即可',
                style: TextStyle(fontSize: 11.5)),
            onTap: () => Navigator.of(ctx).pop('text'),
          ),
        ],
      ),
    ),
  );
  if (mode == null || !context.mounted) return null;

  final s = context.read<AppState>();
  List<Course> list;
  String label;

  switch (mode) {
    case 'file':
      final picked = await FilePicker.pickFile(
        dialogTitle: '选择课表文件',
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv', 'tsv', 'html', 'htm', 'xls', 'json'],
      );
      if (picked == null || !context.mounted) return null;
      final path = picked.path;
      if (path == null) return null;
      label = picked.name;
      try {
        list = await parseCourseFile(path, s.periods);
      } catch (e) {
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('解析失败：$e\n建议用 .xlsx 或网页复制文本')));
        return null;
      }
      break;
    case 'image':
      final picked = await FilePicker.pickFile(dialogTitle: '选择课表截图', type: FileType.image);
      if (picked == null || !context.mounted) return null;
      final path = picked.path;
      if (path == null) return null;
      label = '图片识别';
      if (!context.mounted) return null;
      final snack = ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在识别（手机本地，不上传）…'), duration: Duration(seconds: 20)),
      );
      try {
        list = await parseCourseImage(path, s.periods);
      } catch (e) {
        snack.close();
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('识别失败：$e')));
        return null;
      }
      snack.close();
      break;
    case 'text':
      final text = await _pasteTextDialog(context);
      if (text == null || text.trim().isEmpty || !context.mounted) return null;
      label = '粘贴文本';
      list = parseLooseText(text.trim(), s.periods);
      break;
    default:
      return null;
  }

  if (!context.mounted) return null;
  if (list.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('没认出课程。文件导入建议用 xlsx；图片尽量裁掉多余部分再试；'
          '或在教务网站全选复制课表文字，用「粘贴文本」导入。'),
      duration: Duration(seconds: 4),
    ));
    return null;
  }
  return Navigator.of(context).push<int>(
    MaterialPageRoute(
      builder: (_) => TimetableImportScreen(candidates: list, sourceLabel: label),
    ),
  );
}

Future<String?> _pasteTextDialog(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('粘贴课表文本'),
      content: SizedBox(
        width: 340,
        height: 220,
        child: TextField(
          controller: ctrl,
          maxLines: null,
          expands: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '在教务网站上课表页面全选复制，粘到这里。\n每行一门课也可以：\n'
                '周一 第1-2节 1-16周 高等数学 教404',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('解析')),
      ],
    ),
  );
}

/// OCR：手机本地识别，不上传。
/// 先按「周一~周日」列头锚点重建表格；失败就退回整段文本解析。
Future<List<Course>> parseCourseImage(String path, List<(int, int)> periods) async {
  final input = InputImage.fromFilePath(path);
  final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  final RecognizedText result;
  try {
    result = await recognizer.processImage(input);
  } finally {
    await recognizer.close();
  }

  // 拼行：同一水平线上的 element 合并成一行（中文不插空格）
  final lines = _mergeLines(result);
  if (lines.isEmpty) return const [];

  // 列头锚点
  final anchors = <int, double>{}; // 星期 → x
  for (final l in lines) {
    final wd = weekdayFromWord(l.text);
    if (wd == null) continue;
    final rest = l.text.replaceAll(RegExp(r'[周一二三四五六日星期天]'), '').trim();
    if (rest.length <= 8 && (!anchors.containsKey(wd) || l.box.center.dx < anchors[wd]!)) {
      anchors[wd] = l.box.center.dx;
    }
  }

  if (anchors.length >= 3) {
    final list = _gridFromOcr(lines, anchors, periods);
    if (list.isNotEmpty) return list;
  }
  return parseLooseText(lines.map((l) => l.text).join('\n'), periods);
}

class _OcrLine {
  _OcrLine(this.text, this.box);
  final String text;
  final Rect box;
}

List<_OcrLine> _mergeLines(RecognizedText result) {
  final elems = <_OcrLine>[];
  for (final block in result.blocks) {
    for (final line in block.lines) {
      final box = line.boundingBox;
      if (box == null) continue;
      final text = line.text.trim();
      if (text.isEmpty) continue;
      elems.add(_OcrLine(text, box));
    }
  }
  if (elems.isEmpty) return const [];
  // 平均行高 → 聚类容差
  final avgH = elems.map((e) => e.box.height).reduce((a, b) => a + b) / elems.length;
  final tol = avgH * 0.6;
  elems.sort((a, b) {
    final d = a.box.top.compareTo(b.box.top);
    return d != 0 ? d : a.box.left.compareTo(b.box.left);
  });
  final out = <_OcrLine>[];
  var cur = <_OcrLine>[];
  var curY = elems.first.box.center.dy;
  void flush() {
    if (cur.isEmpty) return;
    cur.sort((a, b) => a.box.left.compareTo(b.box.left));
    final buf = StringBuffer();
    for (var i = 0; i < cur.length; i++) {
      final t = cur[i].text;
      final prevLatin = i > 0 && _isLatin(cur[i - 1].text);
      final curLatin = _isLatin(t);
      if (buf.isNotEmpty && prevLatin && curLatin) buf.write(' ');
      buf.write(t);
    }
    final left = cur.map((e) => e.box.left).reduce(math.min);
    final right = cur.map((e) => e.box.right).reduce(math.max);
    final top = cur.map((e) => e.box.top).reduce(math.min);
    final bottom = cur.map((e) => e.box.bottom).reduce(math.max);
    out.add(_OcrLine(buf.toString(), Rect.fromLTRB(left, top, right, bottom)));
    cur = <_OcrLine>[];
  }

  for (final e in elems) {
    if (cur.isEmpty) {
      curY = e.box.center.dy;
    } else if ((e.box.center.dy - curY).abs() > tol) {
      flush();
      curY = e.box.center.dy;
    }
    cur.add(e);
  }
  flush();
  return out;
}

bool _isLatin(String t) => RegExp(r'[A-Za-z0-9]$').hasMatch(t);

/// 按列头锚点把行分到 7 列里，每列内按行距切成格子
List<Course> _gridFromOcr(List<_OcrLine> lines, Map<int, double> anchors, List<(int, int)> periods) {
  final sortedCols = anchors.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  final boundaries = <double>[];
  for (var i = 0; i + 1 < sortedCols.length; i++) {
    boundaries.add((sortedCols[i].value + sortedCols[i + 1].value) / 2);
  }
  double? colOf(double x) {
    if (x < boundaries.first) return null; // 行标签区
    for (var i = 0; i < sortedCols.length; i++) {
      final lo = i == 0 ? boundaries.first : boundaries[i - 1];
      final hi = i == sortedCols.length - 1 ? double.infinity : boundaries[i];
      if (x >= lo && x < hi) return sortedCols[i].key.toDouble();
    }
    return null;
  }

  final avgH = lines.map((l) => l.box.height).reduce((a, b) => a + b) / lines.length;
  final cellGap = avgH * 1.1;
  // 行标签（第一列左边）：节次
  final labelLines = lines.where((l) => l.box.center.dx < boundaries.first && l.text.length <= 10).toList()
    ..sort((a, b) => a.box.top.compareTo(b.box.top));

  final byCol = <int, List<_OcrLine>>{};
  for (final l in lines) {
    if (anchors.entries.any((a) => l.text == a.key.toString() || weekdayFromWord(l.text) != null && l.text.length <= 8)) {
      continue; // 列头本身
    }
    final col = colOf(l.box.center.dx);
    if (col == null) continue;
    byCol.putIfAbsent(col.toInt(), () => []).add(l);
  }

  final out = <Course>[];
  for (final e in byCol.entries) {
    final colLines = e.value..sort((a, b) => a.box.top.compareTo(b.box.top));
    var group = <_OcrLine>[];
    void flushGroup() {
      if (group.isEmpty) return;
      final top = group.map((g) => g.box.top).reduce(math.min);
      final bottom = group.map((g) => g.box.bottom).reduce(math.max);
      final text = group.map((g) => g.text).join('\n');
      final p = parseCellText(text);
      // 找覆盖这个 y 区间的行标签 → 节次
      int? sp, ep;
      for (final lab in labelLines) {
        if (lab.box.center.dy >= top - cellGap && lab.box.center.dy <= bottom + cellGap) {
          final lp = parseCellText(lab.text);
          sp ??= lp.startPeriod;
          ep ??= lp.endPeriod;
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
        group = <_OcrLine>[];
        return;
      }
      if (p.name.isNotEmpty && weekdayFromWord(p.name) == null) {
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
      group = <_OcrLine>[];
    }

    for (final l in colLines) {
      if (group.isNotEmpty &&
          l.box.top - group.last.box.bottom > cellGap) {
        flushGroup();
      }
      group.add(l);
    }
    flushGroup();
  }
  return out;
}
