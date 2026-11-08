import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../utils/rich_doc.dart';

/// 仿 vivo 原子笔记的行级富文本编辑器。
/// 每行一个块：普通文字（可加粗/斜体/下划线/删除线/高亮/字号/颜色/对齐/编号列表）、
/// 待办勾选行、图片行。底部工具栏作用于当前聚焦的行。
class RichEditor extends StatefulWidget {
  const RichEditor({super.key, this.initialContent, this.hint = '记点什么…'});

  final String? initialContent;
  final String hint;

  @override
  State<RichEditor> createState() => RichEditorState();
}

class RichEditorState extends State<RichEditor> {
  List<RichLine> _lines = [];
  List<TextEditingController> _ctrls = [];
  int _focusIndex = 0;
  // 工具栏面板：none / style / align / list / color
  String _panel = 'none';

  static const _fontSizes = [12, 14, 16, 18, 20, 24];
  static const _colors = <int?, String>{
    null: '默认',
    0xFFD6336C: '红',
    0xFFF76707: '橙',
    0xFFFAB005: '黄',
    0xFF2F9E44: '绿',
    0xFF1971C2: '蓝',
    0xFF6741D9: '紫',
  };

  @override
  void initState() {
    super.initState();
    _reset(widget.initialContent);
  }

  void _reset(String? content) {
    _lines = decodeRichDoc(content);
    _ctrls = _lines.map((l) => TextEditingController(text: l.text)).toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// 导出 content 字符串（编辑页保存时调用）
  String export() {
    for (var i = 0; i < _lines.length && i < _ctrls.length; i++) {
      if (!_lines[i].isImage) _lines[i].text = _ctrls[i].text;
    }
    return encodeRichDoc(_lines);
  }

  RichLine get _current => _lines[_focusIndex.clamp(0, _lines.length - 1)];

  void _ensureTextLine() {
    if (_current.isImage) _insertAfter(_focusIndex, RichLine());
  }

  void _insertAfter(int index, RichLine line) {
    setState(() {
      _lines.insert(index + 1, line);
      _ctrls.insert(index + 1, TextEditingController(text: line.text));
      _focusIndex = index + 1;
    });
  }

  void _removeLine(int index) {
    if (_lines.length <= 1) return;
    setState(() {
      _lines.removeAt(index);
      _ctrls.removeAt(index).dispose();
      _focusIndex = _focusIndex.clamp(0, _lines.length - 1);
    });
  }

  void _toggleStyle(String s) {
    _ensureTextLine();
    setState(() {
      final l = _current;
      l.styles.contains(s) ? l.styles.remove(s) : l.styles.add(s);
    });
  }

  Future<void> _pickImage() async {
    try {
      final f = await FilePicker.pickFile(dialogTitle: '选择图片', type: FileType.image);
      if (f == null || f.path == null) return;
      final path = await copyImageIntoAppDir(f.path!);
      _insertAfter(_focusIndex, RichLine(imagePath: path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选图失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              itemCount: _lines.length,
              itemBuilder: (_, i) => _buildRow(i),
            ),
          ),
          _buildToolbar(),
          if (_panel != 'none') _buildPanel(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 行
  Widget _buildRow(int i) {
    final line = _lines[i];
    if (line.isImage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Image.file(File(line.imagePath!), fit: BoxFit.contain),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: () => _removeLine(i),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget? leading;
    if (line.todo) {
      leading = SizedBox(
        width: 26,
        child: Checkbox(
          visualDensity: VisualDensity.compact,
          value: line.done,
          onChanged: (v) => setState(() => line.done = v ?? false),
        ),
      );
    } else {
      final prefix = switch (line.list) {
        1 => '• ',
        2 => '${_numberPrefix(i)}. ',
        3 => '${_letterPrefix(i)}. ',
        _ => null,
      };
      if (prefix != null) {
        leading = SizedBox(
          width: 30,
          child: Text(prefix, style: TextStyle(fontSize: line.fontSize - 1, color: context.sub)),
        );
      }
    }

    final style = TextStyle(
      fontSize: line.fontSize.toDouble(),
      color: line.color == null ? context.text : Color(line.color!),
      fontWeight: line.isBold ? FontWeight.w700 : FontWeight.normal,
      fontStyle: line.isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: TextDecoration.combine([
        if (line.isUnderline) TextDecoration.underline,
        if (line.isStrike) TextDecoration.lineThrough,
      ]),
      backgroundColor: line.isHighlight
          ? (context.isDark ? const Color(0xFF5C4A1E) : const Color(0xFFFFF3BF))
          : null,
      height: 1.5,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) Padding(padding: const EdgeInsets.only(top: 12), child: leading),
        Expanded(
          child: TextField(
            controller: _ctrls[i],
            style: line.done
                ? style.copyWith(
                    decoration: TextDecoration.combine([TextDecoration.lineThrough]),
                    color: context.faint,
                  )
                : style,
            textAlign: line.align == 1 ? TextAlign.center : (line.align == 2 ? TextAlign.right : TextAlign.start),
            minLines: 1,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: _lines.length == 1 ? widget.hint : '',
              hintStyle: TextStyle(fontSize: 14, color: context.faint),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            textInputAction: TextInputAction.newline,
            onChanged: (_) => _focusIndex = i,
            onTap: () => setState(() => _focusIndex = i),
            onSubmitted: (_) => _insertAfter(i, RichLine()),
          ),
        ),
      ],
    );
  }

  String _numberPrefix(int i) {
    var n = 1;
    for (var k = i - 1; k >= 0; k--) {
      if (_lines[k].list != 2 || _lines[k].isImage) break;
      n++;
    }
    return '$n';
  }

  String _letterPrefix(int i) {
    var n = 1;
    for (var k = i - 1; k >= 0; k--) {
      if (_lines[k].list != 3 || _lines[k].isImage) break;
      n++;
    }
    return String.fromCharCode(0x61 + n - 1);
  }

  // ------------------------------------------------------------- 工具栏
  Widget _buildToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: context.card,
        border: Border(top: BorderSide(color: context.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        children: [
          _tool(Icons.text_fields, label: 'Aa', active: _panel == 'style', onTap: () => setState(() => _panel = _panel == 'style' ? 'none' : 'style')),
          _tool(Icons.format_align_left_outlined, active: _panel == 'align', onTap: () => setState(() => _panel = _panel == 'align' ? 'none' : 'align')),
          _tool(Icons.format_list_bulleted, active: _panel == 'list', onTap: () => setState(() => _panel = _panel == 'list' ? 'none' : 'list')),
          _tool(Icons.check_box_outlined, active: _current.todo, onTap: () {
            _ensureTextLine();
            setState(() {
              _current.todo = !_current.todo;
              if (!_current.todo) _current.done = false;
            });
          }),
          _tool(Icons.image_outlined, onTap: _pickImage),
          _tool(Icons.add_circle_outline, onTap: () => _insertAfter(_focusIndex, RichLine())),
          const Spacer(),
          _tool(Icons.delete_outline, onTap: () => _removeLine(_focusIndex)),
        ],
      ),
    );
  }

  Widget _tool(IconData icon, {bool active = false, VoidCallback? onTap, String? label, bool isActive = false}) {
    final sel = active || isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: label != null
          ? TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(38, 36),
                padding: EdgeInsets.zero,
                backgroundColor: sel ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel ? Theme.of(context).colorScheme.primary : context.sub,
                ),
              ),
            )
          : IconButton(
              onPressed: onTap,
              icon: Icon(icon, size: 20),
              visualDensity: VisualDensity.compact,
              color: sel ? Theme.of(context).colorScheme.primary : context.sub,
            ),
    );
  }

  // ------------------------------------------------------------- 面板
  Widget _buildPanel() {
    final l = _current;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF23252C) : const Color(0xFFF4F5F9),
        border: Border(top: BorderSide(color: context.divider)),
      ),
      child: switch (_panel) {
        'style' => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _miniBtn('B', active: l.isBold, bold: true, onTap: () => _toggleStyle('b')),
                  _miniBtn('I', active: l.isItalic, italic: true, onTap: () => _toggleStyle('i')),
                  _miniBtn('U', active: l.isUnderline, underline: true, onTap: () => _toggleStyle('u')),
                  _miniBtn('S', active: l.isStrike, strike: true, onTap: () => _toggleStyle('s')),
                  _miniBtn('高亮', active: l.isHighlight, onTap: () => _toggleStyle('hl')),
                  const SizedBox(width: 6),
                  for (final fs in _fontSizes)
                    ChoiceChip(
                      label: Text('$fs', style: const TextStyle(fontSize: 11)),
                      selected: l.fontSize == fs,
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                      onSelected: (_) {
                        _ensureTextLine();
                        setState(() => _current.fontSize = fs);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('字体颜色', style: TextStyle(fontSize: 11, color: context.faint)),
                  for (final entry in _colors.entries)
                    GestureDetector(
                      onTap: () {
                        _ensureTextLine();
                        setState(() => _current.color = entry.key);
                      },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: entry.key == null
                              ? (context.isDark ? const Color(0xFF2A2D35) : Colors.white)
                              : Color(entry.key!),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: l.color == entry.key
                                ? Theme.of(context).colorScheme.primary
                                : context.divider,
                            width: l.color == entry.key ? 2.2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: entry.key == null
                            ? Text('默认', style: TextStyle(fontSize: 8, color: context.sub))
                            : (l.color == entry.key
                                ? const Icon(Icons.check, size: 13, color: Colors.white)
                                : null),
                      ),
                    ),
                ],
              ),
            ],
          ),
        'align' => Wrap(
            spacing: 8,
            children: [
              for (var a = 0; a < 3; a++)
                IconButton.filledTonal(
                  onPressed: () {
                    _ensureTextLine();
                    setState(() => _current.align = a);
                  },
                  isSelected: l.align == a,
                  icon: Icon(switch (a) {
                    1 => Icons.format_align_center,
                    2 => Icons.format_align_right,
                    _ => Icons.format_align_left,
                  }, size: 18),
                ),
            ],
          ),
        'list' => Wrap(
            spacing: 8,
            children: [
              for (var v = 0; v <= 3; v++)
                ChoiceChip(
                  label: Text(switch (v) { 1 => '• 圆点', 2 => '1. 数字', 3 => 'a. 字母', _ => '无列表' },
                      style: const TextStyle(fontSize: 12)),
                  selected: l.list == v,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                  onSelected: (_) {
                    _ensureTextLine();
                    setState(() => _current.list = v);
                  },
                ),
            ],
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _miniBtn(String label, {bool active = false, bool bold = false, bool italic = false, bool underline = false, bool strike = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Theme.of(context).colorScheme.primary.withOpacity(0.2) : context.isDark ? const Color(0xFF2A2D35) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            decoration: TextDecoration.combine([
              if (underline) TextDecoration.underline,
              if (strike) TextDecoration.lineThrough,
            ]),
            color: active ? Theme.of(context).colorScheme.primary : context.sub,
          ),
        ),
      ),
    );
  }
}
