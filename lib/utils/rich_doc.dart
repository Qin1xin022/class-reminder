import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 行级富文本（仿 vivo 原子笔记）：
/// content 字段存 JSON 行数组；兼容旧纯文本（不是 JSON 就当成一行普通文字）。
///
/// 行结构：
/// { "t":"text", "s":"文字", "st":"b,i,u,s,hl", "fs":16, "c":"FFFF0000",
///   "al":0, "li":0, "td":false, "dn":false }
/// { "t":"img", "img":"/path/to.jpg" }
/// st: b粗体 i斜体 u下划line s删除线 hl高亮  al: 0左 1中 2右  li: 0无 1圆点 2数字 3字母
class RichLine {
  String text;
  Set<String> styles;
  int fontSize;
  int? color; // 0xRRGGBB
  int align;
  int list;
  bool todo;
  bool done;
  String? imagePath;

  RichLine({
    this.text = '',
    Set<String>? styles,
    this.fontSize = 16,
    this.color,
    this.align = 0,
    this.list = 0,
    this.todo = false,
    this.done = false,
    this.imagePath,
  }) : styles = styles ?? <String>{};

  bool get isImage => imagePath != null && imagePath!.isNotEmpty;
  bool get isBold => styles.contains('b');
  bool get isItalic => styles.contains('i');
  bool get isUnderline => styles.contains('u');
  bool get isStrike => styles.contains('s');
  bool get isHighlight => styles.contains('hl');

  Map<String, Object?> toMap() => isImage
      ? {'t': 'img', 'img': imagePath}
      : {
          't': 'text',
          's': text,
          'st': styles.join(','),
          'fs': fontSize,
          if (color != null) 'c': color!.toRadixString(16),
          'al': align,
          'li': list,
          'td': todo,
          'dn': done,
        };

  static RichLine fromMap(Map<Object?, Object?> m) {
    if ((m['t'] as String?) == 'img') {
      return RichLine(imagePath: (m['img'] as String?) ?? '');
    }
    final st = ((m['st'] as String?) ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final cRaw = m['c'] as String?;
    return RichLine(
      text: (m['s'] as String?) ?? '',
      styles: st,
      fontSize: (m['fs'] as num?)?.toInt() ?? 16,
      color: cRaw == null || cRaw.isEmpty ? null : int.tryParse(cRaw, radix: 16),
      align: (m['al'] as num?)?.toInt() ?? 0,
      list: (m['li'] as num?)?.toInt() ?? 0,
      todo: (m['td'] as bool?) ?? false,
      done: (m['dn'] as bool?) ?? false,
    );
  }
}

/// 解析 content → 行列表；旧纯文本 → 单行
List<RichLine> decodeRichDoc(String? content) {
  final raw = (content ?? '').trim();
  if (raw.isEmpty) return [RichLine()];
  if (!raw.startsWith('[')) return [RichLine(text: content ?? '')];
  try {
    final arr = jsonDecode(raw) as List<dynamic>;
    return arr.map((e) => RichLine.fromMap(e as Map<Object?, Object?>)).toList();
  } catch (_) {
    return [RichLine(text: content ?? '')];
  }
}

/// 行列表 → content 字符串
String encodeRichDoc(List<RichLine> lines) {
  final kept = lines.where((l) => !(l.isImage || l.text.trim().isNotEmpty)).toList();
  if (kept.length == 1 && kept.first.fontSize == 16 && kept.first.styles.isEmpty) {
    final l = kept.first;
    if (l.color == null && l.align == 0 && l.list == 0 && !l.todo) {
      return l.text; // 普通单行存纯文本，省空间也兼容旧展示
    }
  }
  return jsonEncode(kept.map((l) => l.toMap()).toList());
}

/// 列表预览：取第一段文字（最多 max 字符）
String richDocPreview(String? content, {int max = 60}) {
  final lines = decodeRichDoc(content);
  final buf = StringBuffer();
  for (final l in lines) {
    if (l.isImage) {
      buf.write('[图片] ');
      continue;
    }
    if (l.text.trim().isEmpty) continue;
    buf.write(l.text.trim());
    buf.write(' ');
    if (buf.length >= max) break;
  }
  var s = buf.toString().trim();
  if (s.length > max) s = '${s.substring(0, max)}…';
  return s;
}

/// 统计图片行数
int richDocImageCount(String? content) =>
    decodeRichDoc(content).where((l) => l.isImage).length;

/// 把外部图片复制进 App 私有目录，返回新路径；失败返回原路径
Future<String> copyImageIntoAppDir(String srcPath) async {
  try {
    final f = File(srcPath);
    if (!await f.exists()) return srcPath;
    final dir = await getApplicationDocumentsDirectory();
    final dest = Directory(p.join(dir.path, 'rich_images'));
    if (!await dest.exists()) await dest.create(recursive: true);
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(srcPath)}';
    final out = p.join(dest.path, name);
    await f.copy(out);
    return out;
  } catch (_) {
    return srcPath;
  }
}
