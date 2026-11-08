import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../widgets/attachments.dart';
import '../widgets/folder_ui.dart';
import '../widgets/links.dart';
import '../widgets/rich_editor.dart';
import '../widgets/rating.dart';
import '../theme/tokens.dart';

class IdeaEditScreen extends StatefulWidget {
  const IdeaEditScreen({super.key, this.idea, this.presetKind, this.presetFolderId});

  final IdeaItem? idea;
  final IdeaKind? presetKind;
  final int? presetFolderId;

  @override
  State<IdeaEditScreen> createState() => _IdeaEditScreenState();
}

class _IdeaEditScreenState extends State<IdeaEditScreen> {
  final GlobalKey<RichEditorState> _editorKey = GlobalKey();

  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _review;
  late final TextEditingController _links;
  int _rating = 0;
  late IdeaKind _kind;
  late bool _pinned;
  int? _folderId;
  final List<AttachmentItem> _pending = [];

  bool get _isEdit => widget.idea != null;

  @override
  void initState() {
    super.initState();
    final i = widget.idea;
    _title = TextEditingController(text: i?.title ?? '');
    _tags = TextEditingController(text: i?.tags ?? '');
    _review = TextEditingController(text: i?.review ?? '');
    _links = TextEditingController(text: i?.links ?? '');
    _rating = i?.rating ?? 0;
    _kind = i?.kind ?? widget.presetKind ?? IdeaKind.idea;
    _pinned = i?.pinned ?? false;
    _folderId = i?.folderId ?? widget.presetFolderId;
  }

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _review.dispose();
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final folderName = state.folderById(_folderId)?.name ?? '根目录';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑${_kind.label}' : '收集${_kind.label}'),
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
          Wrap(
            spacing: 8,
            children: IdeaKind.values.map((v) {
              final selected = _kind == v;
              return ChoiceChip(
                avatar: Icon(v.icon, size: 15, color: selected ? Colors.white : v.color),
                label: Text(v.label, style: TextStyle(fontSize: 13, color: selected ? Colors.white : context.sub)),
                selected: selected,
                selectedColor: v.color,
                backgroundColor: context.card,
                showCheckmark: false,
                onSelected: (_) => setState(() => _kind = v),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            _kind.hint,
            style: TextStyle(fontSize: 11, color: context.faint, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: InputDecoration(hintText: _kind == IdeaKind.pain ? '一句话说清这个痛点' : '一句话标题'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(hintText: '标签，用空格或逗号分隔：校园 效率 副业'),
          ),
          const SizedBox(height: 10),
          FolderRow(
            folderName: folderName,
            onTap: () async {
              final picked = await pickFolder(context, 'idea', _folderId);
              setState(() => _folderId = picked);
            },
          ),
          const SizedBox(height: 10),
          RichEditor(
            key: _editorKey,
            initialContent: widget.idea?.content,
            hint: _kind == IdeaKind.pain
                ? '谁在什么场景下不舒服？现在他们怎么凑合解决的？为什么现有方案不行？'
                : '把脑子里的东西倒出来：背景、想法、能怎么做、还缺什么…',
          ),
          const SizedBox(height: 16),
          LinksField(controller: _links, label: '参考链接（每行一个：文章、竞品、视频…）'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '跟进 / 自评',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.sub),
                    ),
                    const Spacer(),
                    StarRating(value: _rating, onChanged: (v) => setState(() => _rating = v)),
                  ],
                ),
                const SizedBox(height: 2),
                TextField(
                  controller: _review,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '后来怎么样了：验证过吗、谁真的需要、下一步做什么…',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AttachmentSection(
            ownerType: 'idea',
            ownerId: widget.idea?.id,
            pending: _pending,
            title: '图片 / 文件',
            hint: '截图、照片、参考文档、竞品截图都可以放这里，随时点开看',
            onPendingChanged: (v) => setState(() {
              _pending
                ..clear()
                ..addAll(v);
            }),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 18),
            Text(
              '创建于 ${fmtDateTime(widget.idea!.createdAt)} · 更新于 ${fmtDateTime(widget.idea!.updatedAt)}',
              style: TextStyle(fontSize: 11, color: context.faint),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final content = _editorKey.currentState?.export() ?? '';
    if (title.isEmpty && content.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final now = DateTime.now();
    final old = widget.idea;
    final state = context.read<AppState>();
    final firstLine = content.split('\n').first;
    final autoTitle = firstLine.length > 30 ? '${firstLine.substring(0, 30)}…' : firstLine;
    final id = await state.saveIdea(
      IdeaItem(
        id: old?.id,
        kind: _kind,
        title: title.isEmpty ? autoTitle : title,
        content: content,
        tags: _tags.text.trim(),
        folderId: _folderId,
        pinned: _pinned,
        rating: _rating,
        review: _review.text.trim(),
        links: _links.text.trim(),
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    if (_pending.isNotEmpty) {
      await state.attachPending('idea', id, _pending);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这一条？'),
        content: const Text('里面的图片和文件也会一起删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().deleteIdea(widget.idea!.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
