import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../theme/tokens.dart';
import '../widgets/links.dart';

const List<int> kCourseColors = [
  0xFF4C6FFF,
  0xFF7B5CFF,
  0xFFE8590C,
  0xFF2B8A3E,
  0xFFD6336C,
  0xFF0CA678,
  0xFF1971C2,
  0xFFB08900,
];

class CourseEditScreen extends StatefulWidget {
  const CourseEditScreen({super.key, this.course});

  final Course? course;

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late int _weekday;
  late int _startMin;
  late int _endMin;
  late int _weekStart;
  late int _weekEnd;
  late int _color;
  late List<int> _remind;
  late final TextEditingController _note;
  late final TextEditingController _teacherNote;
  late final TextEditingController _links;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _weekday = c?.weekday ?? DateTime.now().weekday;
    _startMin = c?.startMin ?? 8 * 60;
    _endMin = c?.endMin ?? 9 * 60 + 40;
    _weekStart = c?.weekStart ?? 1;
    _weekEnd = c?.weekEnd ?? 16;
    _color = c?.color ?? kCourseColors.first;
    _remind = List<int>.from(c?.remindList ?? const [30, 15]);
    _note = TextEditingController(text: c?.note ?? '');
    _teacherNote = TextEditingController(text: c?.teacherNote ?? '');
    _links = TextEditingController(text: c?.links ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    _note.dispose();
    _teacherNote.dispose();
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.course != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑课程' : '新增课程'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: '课程名，例如：高等数学'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _teacher,
                  decoration: const InputDecoration(hintText: '老师（可选）'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _location,
                  decoration: const InputDecoration(hintText: '教室（可选）'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _row('星期', _weekdayChips()),
          const SizedBox(height: 8),
          _timeRow('开始', _startMin, (v) => setState(() => _startMin = v)),
          const SizedBox(height: 8),
          _timeRow('结束', _endMin, (v) => setState(() => _endMin = v)),
          const SizedBox(height: 18),
          _row('周次范围', _weekRange()),
          const SizedBox(height: 18),
          _row('上课前提醒', _remindChips()),
          const SizedBox(height: 18),
          _row('课程备注（自己的，比如：这门课要带计算器）',
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(hintText: '选填'),
              )),
          const SizedBox(height: 18),
          _row('老师提醒要干嘛（会保存，上课前 10 分钟单独提醒你）',
              TextField(
                controller: _teacherNote,
                maxLines: 2,
                decoration: const InputDecoration(hintText: '比如：下次带实验报告、交作业'),
              )),
          const SizedBox(height: 18),
          LinksField(
            controller: _links,
            label: '课程相关链接（每行一个：课件网盘、课程群、参考资料…）',
          ),
          const SizedBox(height: 18),
          _row('颜色', _colorPicker()),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(isEdit ? '保存修改' : '添加课程'),
          ),
          const SizedBox(height: 10),
          Text(
            '提示：可同时选多个提前量（默认 30 分钟 + 15 分钟各响一次）。保存后会自动为「未来 3 周」的每次课安排提醒，每次打开 App 自动往后延期。',
            style: TextStyle(fontSize: 11, color: context.faint, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(label, style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600)),
        ),
        child,
      ],
    );
  }

  Widget _weekdayChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [1, 2, 3, 4, 5, 6, 7].map((d) {
        final selected = _weekday == d;
        return ChoiceChip(
          label: Text(weekdayLabel(d), style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
          selected: selected,
          selectedColor: Color(_color),
          backgroundColor: context.card,
          showCheckmark: false,
          onSelected: (_) => setState(() => _weekday = d),
        );
      }).toList(),
    );
  }

  Widget _timeRow(String label, int value, ValueChanged<int> onChanged) {
    return Material(
      color: context.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final t = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
          );
          if (t != null) onChanged(t.hour * 60 + t.minute);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          child: Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Text(hhmm(value), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Icon(Icons.chevron_right, size: 18, color: context.faint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weekRange() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Row(
            children: [
              const Text('起始周', style: TextStyle(fontSize: 13)),
              const Spacer(),
              _stepper(_weekStart, (v) {
                if (v >= 1 && v <= _weekEnd) setState(() => _weekStart = v);
              }),
            ],
          ),
          const Divider(height: 1),
          Row(
            children: [
              const Text('结束周', style: TextStyle(fontSize: 13)),
              const Spacer(),
              _stepper(_weekEnd, (v) {
                if (v >= _weekStart && v <= 30) setState(() => _weekEnd = v);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepper(int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value - 1),
          icon: const Icon(Icons.remove_circle_outline, size: 18),
        ),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline, size: 18),
        ),
      ],
    );
  }

  Widget _remindChips() {
    const options = [30, 15, 10, 5, 0];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((m) {
        final selected = _remind.contains(m);
        return FilterChip(
          label: Text(
            m == 0 ? '上课时' : '$m 分钟前',
            style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub),
          ),
          selected: selected,
          selectedColor: Color(_color),
          backgroundColor: context.card,
          checkmarkColor: Colors.white,
          showCheckmark: false,
          onSelected: (v) => setState(() {
            if (v) {
              _remind.add(m);
              _remind.sort((a, b) => b.compareTo(a));
            } else {
              _remind.remove(m);
            }
          }),
        );
      }).toList(),
    );
  }

  Widget _colorPicker() {
    return Wrap(
      spacing: 10,
      children: kCourseColors.map((c) {
        final selected = _color == c;
        return GestureDetector(
          onTap: () => setState(() => _color = c),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: selected ? Border.all(color: context.text, width: 2.5) : null,
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
          ),
        );
      }).toList(),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('课程名不能为空')));
      return;
    }
    if (_endMin <= _startMin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('结束时间要晚于开始时间')));
      return;
    }
    final course = Course(
      id: widget.course?.id,
      name: name,
      teacher: _teacher.text.trim(),
      location: _location.text.trim(),
      weekday: _weekday,
      startMin: _startMin,
      endMin: _endMin,
      weekStart: _weekStart,
      weekEnd: _weekEnd,
      color: _color,
      remind: _remind.isEmpty ? '0' : _remind.join(','),
      note: _note.text.trim(),
      teacherNote: _teacherNote.text.trim(),
      links: _links.text.trim(),
    );
    await context.read<AppState>().saveCourse(course);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这门课？'),
        content: const Text('已关联的待办会保留，但不再显示课程名。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().deleteCourse(widget.course!.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
