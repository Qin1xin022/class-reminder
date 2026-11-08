import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart';
import '../theme/tokens.dart';

class CompetitionEditScreen extends StatefulWidget {
  const CompetitionEditScreen({super.key, this.comp, this.startAsPast = false});

  final Competition? comp;

  /// 从「补录参加过的比赛」进来，默认标记为已参加
  final bool startAsPast;

  @override
  State<CompetitionEditScreen> createState() => _CompetitionEditScreenState();
}

class _CompetitionEditScreenState extends State<CompetitionEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final TextEditingController _link;
  late final TextEditingController _note;
  late final TextEditingController _resultNote;
  late final TextEditingController _summary;
  late String _stage;
  late String _level;
  late int _importance;
  DateTime? _signup;
  DateTime? _startAt;
  DateTime? _endAt;
  DateTime? _resultAt;
  late String _resultRank;
  late bool _attended;
  final List<AttachmentItem> _pending = [];

  bool get _isEdit => widget.comp != null;

  @override
  void initState() {
    super.initState();
    final c = widget.comp;
    _name = TextEditingController(text: c?.name ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _link = TextEditingController(text: c?.link ?? '');
    _note = TextEditingController(text: c?.note ?? '');
    _resultNote = TextEditingController(text: c?.resultNote ?? '');
    _summary = TextEditingController(text: c?.summary ?? '');
    _stage = c?.stage ?? '初赛';
    _level = c?.level ?? '校级';
    _importance = c?.importance ?? 1;
    _signup = c?.signupDeadline;
    _startAt = c?.startAt;
    _endAt = c?.endAt;
    _resultAt = c?.resultAt;
    _resultRank = c?.resultRank ?? 'pending';
    _attended = c?.attended ?? widget.startAsPast;
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _link.dispose();
    _note.dispose();
    _resultNote.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final prep = _isEdit ? s.prepTasksOf(widget.comp!.id!) : const <TaskItem>[];
    final prepDone = prep.where((t) => t.done).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑比赛' : '新建比赛'),
        actions: [
          if (_isEdit)
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
            decoration: const InputDecoration(hintText: '比赛名称，例如：全国大学生数学建模竞赛'),
          ),
          const SizedBox(height: 14),
          const _Label('赛段'),
          Wrap(
            spacing: 8,
            children: kCompStages.map((v) {
              final selected = _stage == v;
              return ChoiceChip(
                label: Text(v, style: TextStyle(fontSize: 13, color: selected ? Colors.white : context.sub)),
                selected: selected,
                selectedColor: Theme.of(context).colorScheme.primary,
                backgroundColor: context.card,
                showCheckmark: false,
                onSelected: (_) => setState(() => _stage = v),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const _Label('级别'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kCompLevels.map((v) {
              final selected = _level == v;
              return ChoiceChip(
                label: Text(v, style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
                selected: selected,
                selectedColor: const Color(0xFF2B8A3E),
                backgroundColor: context.card,
                showCheckmark: false,
                onSelected: (_) => setState(() => _level = v),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const _Label('重要程度'),
          Wrap(
            spacing: 8,
            children: Importance.values.map((v) {
              final selected = _importance == v.index;
              return ChoiceChip(
                avatar: Icon(v.icon, size: 15, color: selected ? Colors.white : v.color),
                label: Text(v.label, style: TextStyle(fontSize: 13, color: selected ? Colors.white : context.sub)),
                selected: selected,
                selectedColor: v.color,
                backgroundColor: context.card,
                showCheckmark: false,
                onSelected: (_) => setState(() => _importance = v.index),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const _Label('关键时间'),
          _TimeRow(
            label: '报名截止',
            icon: Icons.how_to_reg_outlined,
            value: _signup,
            onPick: () async {
              final v = await pickDateTime(context, _signup ?? _startAt);
              if (v != null) setState(() => _signup = v);
            },
            onClear: () => setState(() => _signup = null),
          ),
          const SizedBox(height: 8),
          _TimeRow(
            label: '开始时间',
            icon: Icons.play_circle_outline,
            value: _startAt,
            onPick: () async {
              final v = await pickDateTime(context, _startAt ?? _signup);
              if (v != null) setState(() => _startAt = v);
            },
            onClear: () => setState(() => _startAt = null),
          ),
          const SizedBox(height: 8),
          _TimeRow(
            label: '结束时间',
            icon: Icons.flag_outlined,
            value: _endAt,
            onPick: () async {
              final v = await pickDateTime(context, _endAt ?? _startAt);
              if (v != null) setState(() => _endAt = v);
            },
            onClear: () => setState(() => _endAt = null),
          ),
          const SizedBox(height: 16),
          const _Label('参赛结果'),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _attended,
                  title: const Text('我参加过这个比赛', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '补录往年比赛时打开：不再提醒，只统计成绩',
                    style: TextStyle(fontSize: 10.5, color: context.sub),
                  ),
                  onChanged: (v) => setState(() => _attended = v),
                ),
                Divider(height: 1, color: context.divider),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('结果', style: TextStyle(fontSize: 11.5, color: Colors.black.withOpacity(0.45))),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kCompResultCodes.map((code) {
                    final selected = _resultRank == code;
                    final c = compResultColor(code);
                    return ChoiceChip(
                      avatar: Icon(compResultIcon(code), size: 14, color: selected ? Colors.white : c),
                      label: Text(
                        compResultLabel(code),
                        style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub),
                      ),
                      selected: selected,
                      selectedColor: c,
                      backgroundColor: context.card,
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        _resultRank = code;
                        if (code != 'pending') _attended = true;
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _resultNote,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '结果说明，例如：省赛二等奖 · 队长 · 作品《…》',
                  ),
                ),
                const SizedBox(height: 10),
                _TimeRow(
                  label: '出结果时间',
                  icon: Icons.event_available_outlined,
                  value: _resultAt,
                  onPick: () async {
                    final v = await pickDateTime(context, _resultAt ?? DateTime.now(), withTime: false);
                    if (v != null) setState(() {
                      _resultAt = v;
                      _attended = true;
                    });
                  },
                  onClear: () => setState(() => _resultAt = null),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _Label('地点 / 形式'),
          TextField(
            controller: _location,
            decoration: const InputDecoration(hintText: '例如：实训楼 A305 / 线上腾讯会议'),
          ),
          const SizedBox(height: 14),
          const _Label('比赛链接（可选）'),
          TextField(
            controller: _link,
            decoration: InputDecoration(
              hintText: '报名页 / 通知页 / 群文件链接',
              suffixIcon: IconButton(
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: () async {
                  final url = _link.text.trim();
                  if (url.isEmpty) return;
                  final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            prep.isEmpty ? '关联的备赛任务（0）' : '关联的备赛任务（$prepDone/${prep.length}）',
            style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600),
          ),
          Container(
            decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
            child: prep.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    child: Text(
                      '这里只显示你在「任务」板块亲自添加并关联了这个比赛的任务，比赛不会自动生成任务。',
                      style: TextStyle(fontSize: 11, color: context.faint, height: 1.5),
                    ),
                  )
                : Column(
                    children: [
                      for (final t in prep)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: t.done,
                          title: Text(
                            t.title,
                            style: TextStyle(
                              fontSize: 13,
                              decoration: t.done ? TextDecoration.lineThrough : null,
                              color: t.done ? context.faint : context.text,
                            ),
                          ),
                          subtitle: t.dueAt == null
                              ? null
                              : Text('截止 ${fmtDateTime(t.dueAt)}', style: const TextStyle(fontSize: 10)),
                          onChanged: (_) => context.read<AppState>().toggleTask(t),
                          secondary: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.close, size: 15, color: context.faint),
                            onPressed: () => context.read<AppState>().deleteTask(t.id!),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          const _Label('备注'),
          TextField(
            controller: _note,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '比赛规则、评分标准、队友分工、注意事项…'),
          ),
          const SizedBox(height: 16),
          const _Label('比赛总结 / 复盘'),
          TextField(
            controller: _summary,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: '这次比赛：准备了什么、现场发挥如何、评委/老师的意见、下次怎么改进…',
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 6, left: 2),
            child: Text(
              '赛后写两句比拿奖更值钱：哪一步最花时间、哪个环节掉了链子、下次提前做什么。',
              style: TextStyle(fontSize: 10.5, color: context.faint, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          AttachmentSection(
            ownerType: 'comp',
            ownerId: widget.comp?.id,
            pending: _pending,
            title: '资料附件',
            hint: '竞赛章程、真题、模板、报名表（Word / PDF / PPT / Excel）',
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
            child: Text(_isEdit ? '保存修改' : '保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先写个比赛名称吧')));
      return;
    }
    if (_startAt != null && _endAt != null && _endAt!.isBefore(_startAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('结束时间不能早于开始时间')));
      return;
    }
    final state = context.read<AppState>();
    final item = Competition(
      id: widget.comp?.id,
      name: name,
      stage: _stage,
      level: _level,
      signupDeadline: _signup,
      startAt: _startAt,
      endAt: _endAt,
      location: _location.text.trim(),
      link: _link.text.trim(),
      note: _note.text.trim(),
      importance: _importance,
      createdAt: widget.comp?.createdAt ?? DateTime.now(),
    );
    final id = await state.saveCompetition(item);
    if (_pending.isNotEmpty) {
      await state.attachPending('comp', id, _pending);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个比赛？'),
        content: const Text('关联的任务不受影响，其他内容会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().deleteCompetition(widget.comp!.id!);
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
  final VoidCallback onClear;

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
