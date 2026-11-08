import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../utils/rich_doc.dart';
import '../widgets/common.dart';
import '../widgets/folder_ui.dart';
import '../widgets/links.dart';
import '../widgets/rating.dart';
import 'note_edit_screen.dart';
import '../theme/tokens.dart';

/// 独立笔记页（保留给单独 push 的场景）
class NoteListScreen extends StatelessWidget {
  const NoteListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: NotePane()),
    );
  }
}

/// 笔记列表本体（可嵌进 TabBarView）
class NotePane extends StatefulWidget {
  const NotePane({super.key});

  @override
  State<NotePane> createState() => _NotePaneState();
}

class _NotePaneState extends State<NotePane> {
  final TextEditingController _q = TextEditingController();
  String _keyword = '';
  int? _folderId;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final searching = _keyword.isNotEmpty;
    final path = s.folderPath(_folderId);
    final subs = s.foldersOf('note', _folderId);

    // 搜索时跨文件夹找，平时只看当前文件夹
    final list = s.notes.where((n) {
      if (!searching && n.folderId != _folderId) return false;
      if (!searching) return true;
      final k = _keyword.toLowerCase();
      return n.title.toLowerCase().contains(k) ||
          n.content.toLowerCase().contains(k) ||
          n.tags.toLowerCase().contains(k);
    }).toList();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
          children: [
            TextField(
              controller: _q,
              onChanged: (v) => setState(() => _keyword = v.trim()),
              decoration: InputDecoration(
                hintText: '搜索全部笔记（标题 / 正文 / 标签）',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _q.clear();
                          setState(() => _keyword = '');
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            if (!searching) ...[
              Row(
                children: [
                  Expanded(
                    child: FolderBreadcrumb(
                      path: path,
                      onJump: (i) => setState(() => _folderId = i < 0 ? null : path[i].id),
                    ),
                  ),
                  IconButton(
                    tooltip: '新建文件夹',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.create_new_folder_outlined, size: 19, color: context.faint),
                    onPressed: () async {
                      final name = await showFolderNameDialog(context);
                      if (name == null) return;
                      await context.read<AppState>().createFolder(name, 'note', _folderId);
                    },
                  ),
                ],
              ),
              for (final f in subs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SubfolderTile(folder: f, onOpen: () => setState(() => _folderId = f.id)),
                ),
            ],
            if (list.isEmpty && subs.isEmpty)
              EmptyHint(
                text: searching ? '没找到相关笔记' : '把课堂内容、错题思路、灵感都丢进来，也可以先建个文件夹分类',
                icon: Icons.auto_stories_outlined,
              ),
            ...list.map((n) => _noteCard(context, n)),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => NoteEditScreen(presetFolderId: _folderId)),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('写笔记'),
          ),
        ),
      ],
    );
  }

  Widget _noteCard(BuildContext context, NoteItem n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NoteEditScreen(note: n)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (n.pinned)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.push_pin, size: 14, color: Color(0xFFE8590C)),
                      ),
                    Expanded(
                      child: Text(
                        n.title.isEmpty ? '（无标题）' : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (n.rating > 0) ...[
                      StarRow(value: n.rating, size: 12),
                      const SizedBox(width: 6),
                    ],
                    Text(fmtMd(n.updatedAt), style: TextStyle(fontSize: 11, color: context.faint)),
                  ],
                ),
                if (n.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      richDocPreview(n.content, max: 80),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.sub, height: 1.5),
                    ),
                  ),
                if (n.linkList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinkList(links: n.linkList.take(2).toList(), dense: true),
                  ),
                if (n.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      children: n.tags
                          .split(RegExp(r'[,，\s]+'))
                          .where((e) => e.isNotEmpty)
                          .map(
                            (t) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('#$t', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary)),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
