import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../utils/extract.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart' show pickDateTime;
import '../theme/tokens.dart';

class NoticeEditScreen extends StatefulWidget {
  const NoticeEditScreen({super.key, this.notice});

  final NoticeItem? notice;

  @override
  State<NoticeEditScreen> createState() => _NoticeEditScreenState();
}

class _NoticeEditScreenState extends State<NoticeEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _points;
  late final TextEditingController _links;
  late String _source;
  late int _importance;
  late bool _pinned;
  DateTime? _deadline;
  late Set<int> _offsets;
  bool _offsetsTouched = false;
  final List<AttachmentItem> _pending = [];

  bool get _isEdit => widget.notice != null;

  @override
  void initState() {
    super.initState();
    final n = widget.notice;
    _title = TextEditingController(text: n?.title ?? '');
    _content = TextEditingController(text: n?.content ?? '');
    _points = TextEditingController(text: n?.keyPoints ?? '');
    _links = TextEditingController(text: n?.links ?? '');
    _source = n?.source ?? '班群';
    _importance = n?.importance ?? 1;
    _pinned = n?.pinned ?? false;
    _deadline = n?.deadlineAt;
    _offsets = {...(n?.remindList ?? kNoticeRemindDefaults[_importance.clamp(0, 2)])};
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _points.dispose();
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '通知详情' : '粘贴通知'),
        actions: [
          IconButton(
            tooltip: _pinned ? '取消置顶' : '置顶',
            onPressed: () => setState(() => _pinned = !_pinned),
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
          ),
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Label('来源'),
          Wrap(
            spacing: 8,
            children: kNoticeSources.map((v) {
              final selected = _source == v;
              return ChoiceChip(
                label: Text(v, style: TextStyle(fontSize: 13, color: selected ? Colors.white : context.sub)),
                selected: selected,
                selectedColor: Theme.of(context).colorScheme.primary,
                backgroundColor: context.card,
                showCheckmark: false,
                onSelected: (_) => setState(() => _source = v),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const _Label('标题'),
          TextField(
            controller: _title,
            decoration: const InputDecoration(hintText: '例如：关于数学建模竞赛报名的通知'),
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
                onSelected: (_) => setState(() {
                  _importance = v.index;
                  if (!_offsetsTouched) _offsets = {...kNoticeRemindDefaults[_importance.clamp(0, 2)]};
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const _Label('截止时间（选填，设了才会在截止前提醒）'),
          _DeadlineRow(
            value: _deadline,
            onPick: () async {
              final v = await pickDateTime(context, _deadline);
              if (v == null) return;
              setState(() => _deadline = v);
            },
            onClear: () => setState(() => _deadline = null),
          ),
          if (_deadline != null) ...[
            const SizedBox(height: 12),
            const _Label('截止前提醒'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kNoticeRemindPresets.map((m) {
                final selected = _offsets.contains(m);
                return FilterChip(
                  label: Text(offsetLabel(m), style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
                  selected: selected,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: context.card,
                  showCheckmark: false,
                  onSelected: (v) => setState(() {
                    _offsetsTouched = true;
                    if (v) {
                      _offsets.add(m);
                      return;
                    }
                    // 至少留一档，避免"设了截止却完全不提醒"
                    if (_offsets.length <= 1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('至少留一档提醒；不想提醒可以不设截止时间'), duration: Duration(seconds: 2)),
                      );
                      return;
                    }
                    _offsets.remove(m);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text(
              '会在 ${_offsets.map(offsetLabel).join(' / ')} 各推一条通知（重要/紧急默认档更多）',
              style: TextStyle(fontSize: 11, color: context.faint, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const _Label('通知原文'),
              const Spacer(),
              TextButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste, size: 15),
                label: const Text('从剪贴板粘贴', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          TextField(
            controller: _content,
            maxLines: 10,
            minLines: 6,
            style: const TextStyle(fontSize: 13, height: 1.6),
            decoration: const InputDecoration(
              hintText: '把班群 / 年级群里的通知整段粘进来，然后点下面的「提炼重点」',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _runExtract,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('提炼重点'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                '重点信息${_points.text.trim().isEmpty ? '' : '（可手动改）'}',
                style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text('一行一条', style: TextStyle(fontSize: 10, color: context.faint)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _points,
            maxLines: 8,
            minLines: 3,
            style: const TextStyle(fontSize: 13, height: 1.6),
            decoration: const InputDecoration(hintText: '截止时间、地点、要交的材料…（提炼后自动填，也可手写）'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                '链接${_links.text.trim().isEmpty ? '' : '（${_linkList.length}）'}',
                style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _extractLinks,
                icon: const Icon(Icons.link, size: 15),
                label: const Text('从正文提取', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_linkList.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
              child: Text(
                '正文里出现的网盘、腾讯文档、报名表链接会自动放到这里，点一下就能打开',
                style: TextStyle(fontSize: 11, color: context.faint, height: 1.5),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  for (var i = 0; i < _linkList.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 44, color: context.divider),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.open_in_new, size: 17, color: Theme.of(context).colorScheme.primary),
                      title: Text(
                        _linkList[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1971C2)),
                      ),
                      trailing: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.copy, size: 15, color: context.faint),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _linkList[i]));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
                        },
                      ),
                      onTap: () async {
                        final uri = Uri.tryParse(_linkList[i]);
                        if (uri == null) return;
                        if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('打不开这个链接，可以先复制到浏览器')));
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 18),
          AttachmentSection(
            ownerType: 'notice',
            ownerId: widget.notice?.id,
            pending: _pending,
            title: '文件',
            hint: '通知里的报名表、附件、PPT 可以在这里存一份，不会被群文件清理掉',
            onPendingChanged: (v) => setState(() {
              _pending
                ..clear()
                ..addAll(v);
            }),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 18),
            Text(
              '发布于 ${fmtDateTime(widget.notice!.createdAt)}',
              style: TextStyle(fontSize: 11, color: context.faint),
            ),
          ],
        ],
      ),
    );
  }

  List<String> get _linkList =>
      _links.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('剪贴板里没有文字')));
      }
      return;
    }
    setState(() {
      final old = _content.text.trim();
      _content.text = old.isEmpty ? text : '$old\n$text';
      if (_title.text.trim().isEmpty) _title.text = suggestTitle(text);
    });
    await _runExtract(silentTitle: true);
  }

  Future<void> _runExtract({bool silentTitle = false}) async {
    final text = _content.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先把通知原文粘进来')));
      return;
    }
    final r = extractNotice(text);
    setState(() {
      if (r.keyPoints.isNotEmpty) _points.text = r.keyPoints.join('\n');
      if (r.links.isNotEmpty) _links.text = r.links.join('\n');
      if (!silentTitle && _title.text.trim().isEmpty) _title.text = suggestTitle(text);
    });
    if (!mounted) return;
    final msg = r.isEmpty
        ? '这段文字里没找到明显的时间/要求，可以手动写重点'
        : '已提炼 ${r.keyPoints.length} 条重点${r.links.isEmpty ? '' : '、${r.links.length} 个链接'}'
            '${r.deadlines.isEmpty ? '' : '，其中 ${r.deadlines.length} 条像截止时间'}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _extractLinks() async {
    final r = extractNotice(_content.text);
    if (r.links.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正文里没找到链接')));
      return;
    }
    setState(() => _links.text = r.links.join('\n'));
  }

  Future<void> _save() async {
    final content = _content.text.trim();
    final title = _title.text.trim();
    if (title.isEmpty && content.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final state = context.read<AppState>();
    final id = await state.saveNotice(
      NoticeItem(
        id: widget.notice?.id,
        source: _source,
        title: title.isEmpty ? suggestTitle(content) : title,
        content: content,
        keyPoints: _points.text.trim(),
        links: _links.text.trim(),
        importance: _importance,
        read: widget.notice?.read ?? true,
        pinned: _pinned,
        createdAt: widget.notice?.createdAt ?? DateTime.now(),
        deadlineAt: _deadline,
        remind: _offsets.isEmpty ? '0' : _offsets.join(','),
      ),
    );
    if (_pending.isNotEmpty) {
      await state.attachPending('notice', id, _pending);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条通知？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().deleteNotice(widget.notice!.id!);
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

class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.value, required this.onPick, required this.onClear});

  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final overdue = value != null && DateTime.now().isAfter(value!.add(const Duration(seconds: 1)));
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
              Icon(Icons.event_available_outlined, size: 18, color: context.faint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value == null ? '不设截止时间' : fmtDateTime(value),
                  style: TextStyle(
                    fontSize: 13,
                    color: value == null ? context.faint : (overdue ? const Color(0xFFD6336C) : context.text),
                    fontWeight: value == null ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
              ),
              if (value != null) ...[
                Text(
                  leftText(value!),
                  style: TextStyle(fontSize: 11.5, color: overdue ? const Color(0xFFD6336C) : context.sub),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 16, color: context.faint),
                  onPressed: onClear,
                ),
              ] else
                Icon(Icons.chevron_right, size: 18, color: context.faint),
            ],
          ),
        ),
      ),
    );
  }
}
