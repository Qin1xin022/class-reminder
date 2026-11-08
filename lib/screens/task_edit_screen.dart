import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart';
import '../widgets/folder_ui.dart';
import '../widgets/links.dart';
import '../theme/tokens.dart';

const List<int> kRemindPresets = [0, 10, 30, 60, 120, 1440, 2880];

/// 常见提交方式，点一下直接填进输入框（再点取消）
const List<String> kSubmitPresets = [
  '学习通 / 雨课堂上传',
  '发到班级群',
  '发邮件给老师',
  '纸质交给课代表',
  '公司系统提交',
  '当面交付',
];

class TaskEditScreen extends StatefulWidget {
  const TaskEditScreen({super.key, this.task, this.presetType, this.presetFolderId, this.presetCompId});

  final TaskItem? task;
  final TaskType? presetType;
  final int? presetFolderId;
  final int? presetCompId;

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _score;
  late final TextEditingController _reviewNote;
  late final TextEditingController _summary;
  late final TextEditingController _submitMethod;
  late final TextEditingController _links;
  late TaskType _type;
  int? _courseId;
  DateTime? _startAt;
  DateTime? _endAt;
  DateTime? _dueAt;
  late Set<int> _offsets;
  List<DateTime> _customAt = [];
  int? _folderId;
  int? _compId;
  late String _reviewer;
  DateTime? _evaluatedAt;
  final List<AttachmentItem> _pending = [];

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _note = TextEditingController(text: t?.note ?? '');
    _score = TextEditingController(text: t?.score ?? '');
    _reviewNote = TextEditingController(text: t?.reviewNote ?? '');
    _summary = TextEditingController(text: t?.summary ?? '');
    _submitMethod = TextEditingController(text: t?.submitMethod ?? '');
    _links = TextEditingController(text: t?.links ?? '');
    _reviewer = t?.reviewer ?? '';
    _evaluatedAt = t?.evaluatedAt;
    _type = t?.type ?? widget.presetType ?? TaskType.homework;
    _courseId = t?.courseId;
    _startAt = t?.startAt;
    _endAt = t?.endAt;
    _dueAt = t?.dueAt;
    _offsets = {...(t?.remindList ?? const [0, 60, 1440])};
    _customAt = [...(t?.customRemindList ?? const <DateTime>[])];
    _folderId = t?.folderId ?? widget.presetFolderId;
    _compId = t?.compId ?? widget.presetCompId;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _score.dispose();
    _reviewNote.dispose();
    _summary.dispose();
    _submitMethod.dispose();
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final isEdit = widget.task != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑待办' : '新建待办'),
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
            controller: _title,
            decoration: const InputDecoration(hintText: '要做什么？例如：高数第三章习题'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          const _Label('类型'),
          Wrap(
            spacing: 8,
            children: TaskType.values.map((t) {
              final selected = _type == t;
              return ChoiceChip(
                avatar: Icon(t.icon, size: 16, color: selected ? Colors.white : t.color),
                label: Text(t.label, style: TextStyle(fontSize: 13, color: selected ? Colors.white : context.sub)),
                selected: selected,
                selectedColor: t.color,
                backgroundColor: context.card,
                showCheckmark: false,
                onSelected: (_) => setState(() => _type = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          // 工作类任务与课程无关，不显示关联课程
          if (_type != TaskType.work) ...[
            const _Label('关联课程（可选）'),
            DropdownButtonFormField<int>(
              value: _courseId ?? 0,
              items: [
                const DropdownMenuItem<int>(value: 0, child: Text('不关联课程')),
                ...s.courses.map(
                  (c) => DropdownMenuItem<int>(
                    value: c.id ?? 0,
                    child: Text('${c.name}（${weekdayLabel(c.weekday)}）', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _courseId = (v == null || v == 0) ? null : v),
            ),
          ],
          const SizedBox(height: 14),
          const _Label('所在文件夹'),
          _FolderRow(
            folderName: s.folderById(_folderId)?.name ?? '根目录',
            onTap: () async {
              final picked = await pickFolder(context, 'task', _folderId);
              setState(() => _folderId = picked);
            },
          ),
          if (s.competitions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _Label('关联比赛（可选）'),
            DropdownButtonFormField<int>(
              value: _compId ?? 0,
              items: [
                const DropdownMenuItem<int>(value: 0, child: Text('不关联比赛')),
                ...s.competitions.map(
                  (c) => DropdownMenuItem<int>(
                    value: c.id ?? 0,
                    child: Text('${c.name}（${c.stage}）', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _compId = (v == null || v == 0) ? null : v),
            ),
          ],
          const SizedBox(height: 14),
          const _Label('时间'),
          _TimeRow(
            label: '开始时间',
            value: _startAt,
            onPick: () async {
              final v = await pickDateTime(context, _startAt ?? _dueAt);
              if (v != null) setState(() => _startAt = v);
            },
            onClear: () => setState(() => _startAt = null),
          ),
          const SizedBox(height: 8),
          _TimeRow(
            label: '结束时间',
            value: _endAt,
            onPick: () async {
              final v = await pickDateTime(context, _endAt ?? _startAt ?? _dueAt);
              if (v != null) setState(() => _endAt = v);
            },
            onClear: () => setState(() => _endAt = null),
          ),
          const SizedBox(height: 8),
          _TimeRow(
            label: '截止时间',
            value: _dueAt,
            highlight: true,
            onPick: () async {
              final v = await pickDateTime(context, _dueAt ?? _startAt);
              if (v != null) setState(() => _dueAt = v);
            },
            onClear: () => setState(() => _dueAt = null),
          ),
          const SizedBox(height: 16),
          const _Label('提前提醒（可多选）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kRemindPresets.map((m) {
              final selected = _offsets.contains(m);
              return FilterChip(
                label: Text(offsetLabel(m), style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (v) => setState(() {
                  if (v) {
                    _offsets.add(m);
                  } else {
                    _offsets.remove(m);
                  }
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const _Label('定时提醒（指定具体时间点，可选）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _customAt.length; i++)
                InputChip(
                  avatar: Icon(Icons.alarm, size: 15, color: Theme.of(context).colorScheme.primary),
                  label: Text(fmtDateTime(_customAt[i]), style: const TextStyle(fontSize: 12)),
                  onDeleted: () => setState(() => _customAt.removeAt(i)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_alarm, size: 16),
                label: const Text('加一个时间', style: TextStyle(fontSize: 12)),
                onPressed: () async {
                  final v = await pickDateTime(context, _customAt.isEmpty ? _dueAt : _customAt.last);
                  if (v == null) return;
                  setState(() {
                    _customAt.add(v);
                    _customAt.sort();
                  });
                },
              ),
            ],
          ),
          if (_customAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '到点就会提醒你，共 ${_customAt.length} 个时间点',
                style: TextStyle(fontSize: 11, color: context.faint),
              ),
            ),
          const SizedBox(height: 16),
          const _Label('备注'),
          TextField(
            controller: _note,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '老师要求、参考页码…'),
          ),
          const SizedBox(height: 16),
          const _Label('提交方式（怎么交这份作业 / 工作）'),
          TextField(
            controller: _submitMethod,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '比如：学习通上传 PDF，文件名写学号+姓名'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSubmitPresets.map((preset) {
              final active = _submitMethod.text.trim() == preset;
              return ActionChip(
                label: Text(preset,
                    style: TextStyle(fontSize: 11.5, color: active ? Colors.white : context.sub)),
                backgroundColor: active ? Theme.of(context).colorScheme.primary : context.card,
                side: BorderSide(color: context.divider),
                onPressed: () => setState(() {
                  _submitMethod.text = active ? '' : preset;
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          LinksField(controller: _links, label: '提交入口 / 相关链接（每行一个）'),
          const SizedBox(height: 18),
          const _Label('评价（老师评分 / 领导评语）'),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _score,
                        decoration: const InputDecoration(
                          hintText: '95 / A / 优',
                          labelText: '评分',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '分数、等级都行，留空表示还没评价',
                        style: TextStyle(fontSize: 10.5, color: Colors.black.withOpacity(0.35), height: 1.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kReviewers.map((r) {
                    final selected = _reviewer == r;
                    return ChoiceChip(
                      label: Text(r, style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
                      selected: selected,
                      selectedColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: context.card,
                      showCheckmark: false,
                      onSelected: (v) => setState(() => _reviewer = v ? r : ''),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reviewNote,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '评语 / 反馈：哪里做得好，哪里被扣分…',
                  ),
                ),
                const SizedBox(height: 8),
                _TimeRow(
                  label: '评价时间',
                  value: _evaluatedAt,
                  onPick: () async {
                    final v = await pickDateTime(context, _evaluatedAt ?? DateTime.now(), withTime: false);
                    if (v != null) setState(() => _evaluatedAt = v);
                  },
                  onClear: () => setState(() => _evaluatedAt = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _Label('总结 / 复盘'),
          TextField(
            controller: _summary,
            maxLines: 5,
            decoration: InputDecoration(hintText: _summaryHint(_type)),
          ),
          Padding(
            padding: EdgeInsets.only(top: 6, left: 2),
            child: Text(
              '做完之后回来补一句：这次怎么做成的、哪里走了弯路、下次怎么更快。',
              style: TextStyle(fontSize: 10.5, color: context.faint, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          AttachmentSection(
            ownerType: 'task',
            ownerId: widget.task?.id,
            pending: _pending,
            onPendingChanged: (v) => setState(() {
              _pending
                ..clear()
                ..addAll(v);
            }),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(isEdit ? '保存修改' : '保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先写个标题吧')));
      return;
    }
    final offsets = _offsets.toList()..sort((a, b) => b.compareTo(a));
    final customParts = _customAt.map((d) => 'a${d.millisecondsSinceEpoch}').toList()..sort();
    final remindParts = [...offsets.map((e) => '$e'), ...customParts];
    final old = widget.task;
    final item = TaskItem(
      id: old?.id,
      title: title,
      type: _type,
      courseId: _courseId,
      folderId: _folderId,
      compId: _compId,
      startAt: _startAt,
      endAt: _endAt,
      dueAt: _dueAt,
      remind: remindParts.isEmpty ? '0' : remindParts.join(','),
      done: old?.done ?? false,
      note: _note.text.trim(),
      createdAt: old?.createdAt ?? DateTime.now(),
      score: _score.text.trim(),
      reviewer: _reviewer,
      reviewNote: _reviewNote.text.trim(),
      evaluatedAt: _evaluatedAt,
      summary: _summary.text.trim(),
      submitMethod: _submitMethod.text.trim(),
      links: _links.text.trim(),
    );
    final state = context.read<AppState>();
    final id = await state.saveTask(item);
    if (_pending.isNotEmpty) {
      await state.attachPending('task', id, _pending);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条待办？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().deleteTask(widget.task!.id!);
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
    required this.value,
    required this.onPick,
    required this.onClear,
    this.highlight = false,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final bool highlight;

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
              Icon(
                highlight ? Icons.alarm : Icons.schedule,
                size: 18,
                color: highlight ? const Color(0xFFE8590C) : context.faint,
              ),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 13)),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    value == null ? '未设置' : '${fmtDateTime(value)} ${friendlyDay(value!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      color: value == null ? context.faint : context.text,
                      fontWeight: value == null ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (value != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: Icon(Icons.close, size: 16, color: context.faint),
                )
              else
                Icon(Icons.chevron_right, size: 18, color: context.faint),
            ],
          ),
        ),
      ),
    );
  }
}


class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folderName, required this.onTap});

  final String folderName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 18, color: Color(0xFFE8A200)),
              const SizedBox(width: 10),
              const Spacer(),
              Flexible(
                child: Text(
                  folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: context.faint),
            ],
          ),
        ),
      ),
    );
  }
}

String _summaryHint(TaskType t) {
  switch (t) {
    case TaskType.homework:
      return '这次作业：哪里卡住了、错在哪、老师怎么说的、下次怎么改…';
    case TaskType.work:
      return '这件事：目标达成了吗、哪里耗时最多、下次怎么更快、需要谁配合…';
    case TaskType.study:
      return '这段自习：学了什么、效率如何、哪些还没弄懂…';
  }
}
