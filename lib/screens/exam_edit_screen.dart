import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import '../widgets/links.dart';

/// 添加 / 编辑一场考试
class ExamEditScreen extends StatefulWidget {
  const ExamEditScreen({super.key, this.exam});

  final Exam? exam;

  @override
  State<ExamEditScreen> createState() => _ExamEditScreenState();
}

class _ExamEditScreenState extends State<ExamEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final TextEditingController _seat;
  late final TextEditingController _note;
  late final TextEditingController _links;
  DateTime? _startAt;
  DateTime? _endAt;
  int? _courseId;
  List<int> _remind = const [1440, 60];

  static const List<int> kExamRemindPresets = [2880, 1440, 180, 60, 30, 0];

  @override
  void initState() {
    super.initState();
    final e = widget.exam;
    _name = TextEditingController(text: e?.name ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _seat = TextEditingController(text: e?.seat ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _links = TextEditingController(text: e?.links ?? '');
    _startAt = e?.startAt;
    _endAt = e?.endAt;
    _courseId = e?.courseId;
    _remind = List<int>.from(e?.remindList ?? const [1440, 60]);
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _seat.dispose();
    _note.dispose();
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final isEdit = widget.exam != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑考试' : '添加考试'),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: '考试名称，比如：大学英语(1) 期末考试'),
          ),
          const SizedBox(height: 14),
          // 关联课程（选填）：选了之后 courseName 自动带上
          DropdownButtonFormField<int?>(
            value: _courseId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '关联课程（选填）'),
            items: [
              const DropdownMenuItem(value: null, child: Text('不关联课程', style: TextStyle(fontSize: 13))),
              for (final c in s.courses)
                DropdownMenuItem(
                  value: c.id,
                  child: Text('${c.name}（周${'一二三四五六日'[c.weekday - 1]}）',
                      style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _courseId = v),
          ),
          const SizedBox(height: 14),
          _TimeRow(
            label: '考试时间',
            icon: Icons.schedule,
            value: _startAt,
            onPick: () async {
              final v = await pickDateTime(context, _startAt);
              if (v != null) setState(() => _startAt = v);
            },
            onClear: null,
          ),
          const SizedBox(height: 8),
          _TimeRow(
            label: '结束时间（选填）',
            icon: Icons.flag_outlined,
            value: _endAt,
            onPick: () async {
              final v = await pickDateTime(context, _endAt ?? _startAt);
              if (v != null) setState(() => _endAt = v);
            },
            onClear: () => setState(() => _endAt = null),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _location,
            decoration: const InputDecoration(hintText: '考试地点，比如：5-102 教学楼'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _seat,
            decoration: const InputDecoration(hintText: '座位号（选填），比如：12 号 / 3 排 5 座'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          const _Label('提前提醒（可多选）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in kExamRemindPresets)
                FilterChip(
                  label: Text(offsetLabel(p),
                      style: TextStyle(
                          fontSize: 12,
                          color: _remind.contains(p) ? Colors.white : context.sub)),
                  selected: _remind.contains(p),
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: context.card,
                  showCheckmark: false,
                  onSelected: (on) => setState(() {
                    on ? _remind.add(p) : _remind.remove(p);
                    _remind.sort((a, b) => b.compareTo(a));
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const _Label('备注'),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '要带的东西、准考证号、注意事项…'),
          ),
          const SizedBox(height: 14),
          LinksField(controller: _links, label: '相关链接（每行一个，比如：考场安排查询）'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(isEdit ? '保存修改' : '添加考试'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先填考试名称')));
      return;
    }
    if (_startAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('选一下考试时间')));
      return;
    }
    final s = context.read<AppState>();
    final course = s.courseById(_courseId);
    final old = widget.exam;
    await s.saveExam(Exam(
      id: old?.id,
      name: name,
      courseId: _courseId,
      courseName: course?.name ?? old?.courseName ?? '',
      startAt: _startAt!,
      endAt: _endAt,
      location: _location.text.trim(),
      seat: _seat.text.trim(),
      note: _note.text.trim(),
      remind: _remind.isEmpty ? '0' : _remind.join(','),
      links: _links.text.trim(),
      createdAt: old?.createdAt ?? DateTime.now(),
    ));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这场考试？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().deleteExam(widget.exam!.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(text, style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600)),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final IconData icon;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: context.faint),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Flexible(
                child: Text(
                  value == null ? '未设置' : '${fmtDateTime(value)} ${friendlyDay(value!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: value == null ? context.faint : context.text,
                    fontWeight: value == null ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
              ),
              if (value != null && onClear != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 16, color: context.faint),
                  onPressed: onClear,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
