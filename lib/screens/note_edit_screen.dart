import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../widgets/attachments.dart';
import '../widgets/folder_ui.dart';
import '../widgets/links.dart';
import '../widgets/rating.dart';
import '../widgets/rich_editor.dart';
import '../theme/tokens.dart';

class NoteEditScreen extends StatefulWidget {
  const NoteEditScreen({super.key, this.note, this.presetCourseId, this.presetFolderId});

  final NoteItem? note;
  final int? presetCourseId;
  final int? presetFolderId;

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _review;
  late final TextEditingController _links;
  int _rating = 0;
  bool _pinned = false;
  final GlobalKey<RichEditorState> _editorKey = GlobalKey();
  int? _folderId;
  final List<AttachmentItem> _pending = [];

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _title = TextEditingController(text: n?.title ?? '');
    _tags = TextEditingController(text: n?.tags ?? '');
    _review = TextEditingController(text: n?.review ?? '');
    _links = TextEditingController(text: n?.links ?? '');
    _rating = n?.rating ?? 0;
    _pinned = n?.pinned ?? false;
    _folderId = n?.folderId ?? widget.presetFolderId;
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
    final isEdit = widget.note != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑笔记' : '新笔记'),
        actions: [
          IconButton(
            tooltip: _pinned ? '取消置顶' : '置顶',
            onPressed: () => setState(() => _pinned = !_pinned),
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
          ),
          if (isEdit)
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
          TextField(
            controller: _title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(hintText: '标题'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(hintText: '标签，用空格或逗号分隔：高数 错题'),
          ),
          const SizedBox(height: 10),
          _FolderRow(
            folderName: context.watch<AppState>().folderById(_folderId)?.name ?? '根目录',
            onTap: () async {
              final picked = await pickFolder(context, 'note', _folderId);
              setState(() => _folderId = picked);
            },
          ),
          const SizedBox(height: 10),
          RichEditor(
            key: _editorKey,
            initialContent: widget.note?.content,
            hint: '正文：课堂要点、公式推导、错因、待查资料…\n可加粗/高亮/编号列表/待办/插图，一行一个要点。',
          ),
          const SizedBox(height: 16),
          LinksField(controller: _links, label: '参考资料链接（每行一个）'),
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
                      '自评 / 收获',
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
                    hintText: '这条值几分？哪一句最有用、哪里还没看懂、之后要补什么…',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AttachmentSection(
            ownerType: 'note',
            ownerId: widget.note?.id,
            pending: _pending,
            onPendingChanged: (v) => setState(() {
              _pending
                ..clear()
                ..addAll(v);
            }),
          ),
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
    final old = widget.note;
    final state = context.read<AppState>();
    final id = await state.saveNote(
      NoteItem(
        id: old?.id,
        title: title.isEmpty ? content.split('\n').first : title,
        content: content,
        tags: _tags.text.trim(),
        courseId: old?.courseId ?? widget.presetCourseId,
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
      await state.attachPending('note', id, _pending);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条笔记？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().deleteNote(widget.note!.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
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
              const Text('所在文件夹', style: TextStyle(fontSize: 13)),
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
