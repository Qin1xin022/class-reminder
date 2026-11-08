import 'dart:io';

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
import 'idea_edit_screen.dart';
import '../theme/tokens.dart';

/// 独立的灵感页（从「记录」标签进入，也可单独 push）
class IdeaListScreen extends StatelessWidget {
  const IdeaListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: IdeaPane()),
    );
  }
}

/// 灵感 / 痛点 / 想法 列表本体（可嵌进 TabBarView）
class IdeaPane extends StatefulWidget {
  const IdeaPane({super.key});

  @override
  State<IdeaPane> createState() => _IdeaPaneState();
}

class _IdeaPaneState extends State<IdeaPane> {
  final TextEditingController _q = TextEditingController();
  String _keyword = '';
  IdeaKind? _kind;
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
    final subs = s.foldersOf('idea', _folderId);

    final list = s.ideas.where((e) {
      if (_kind != null && e.kind != _kind) return false;
      if (!searching && e.folderId != _folderId) return false;
      if (!searching) return true;
      final k = _keyword.toLowerCase();
      return e.title.toLowerCase().contains(k) ||
          e.content.toLowerCase().contains(k) ||
          e.tags.toLowerCase().contains(k);
    }).toList();

    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
          children: [
            TextField(
              controller: _q,
              onChanged: (v) => setState(() => _keyword = v.trim()),
              decoration: InputDecoration(
                hintText: '搜索灵感 / 痛点 / 想法',
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
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _kindChip(null, '全部', s.ideaCount),
                  for (final k in IdeaKind.values) _kindChip(k, k.label, s.ideaCountOf(k)),
                ],
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
                      await context.read<AppState>().createFolder(name, 'idea', _folderId);
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
                text: searching
                    ? '没找到相关内容'
                    : '把一闪而过的点子、身边看不惯的事、你的方案都记下来，\n可以配截图和文件，慢慢就长成自己的选题库',
                icon: Icons.lightbulb_outline,
              ),
            ...list.map((e) => _IdeaCard(idea: e)),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => IdeaEditScreen(presetKind: _kind, presetFolderId: _folderId),
              ),
            ),
            icon: const Icon(Icons.add),
            label: Text(_kind == null ? '记一条' : '记${_kind!.label}'),
          ),
        ),
      ],
    );
  }

  Widget _kindChip(IdeaKind? kind, String label, int count) {
    final selected = _kind == kind;
    final color = kind?.color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: kind == null
            ? null
            : Icon(kind.icon, size: 14, color: selected ? Colors.white : kind.color),
        label: Text(
          '$label $count',
          style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub),
        ),
        selected: selected,
        selectedColor: color,
        backgroundColor: context.card,
        showCheckmark: false,
        onSelected: (_) => setState(() => _kind = kind),
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.idea});

  final IdeaItem idea;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final files = state.attachmentsOf('idea', idea.id);
    final images = files.where((e) => e.isImage).toList();
    final docs = files.where((e) => !e.isImage).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => IdeaEditScreen(idea: idea)),
          ),
          onLongPress: () async {
            final action = await showModalBottomSheet<String>(
              context: context,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(idea.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                      title: Text(idea.pinned ? '取消置顶' : '置顶'),
                      onTap: () => Navigator.of(ctx).pop('pin'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline, color: Color(0xFFD6336C)),
                      title: const Text('删除'),
                      onTap: () => Navigator.of(ctx).pop('delete'),
                    ),
                  ],
                ),
              ),
            );
            if (action == 'pin') await state.toggleIdeaPin(idea);
            if (action == 'delete') await state.deleteIdea(idea.id!);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: idea.kind.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        children: [
                          Icon(idea.kind.icon, size: 11, color: idea.kind.color),
                          const SizedBox(width: 3),
                          Text(
                            idea.kind.label,
                            style: TextStyle(
                              fontSize: 10,
                              color: idea.kind.color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (idea.pinned)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.push_pin, size: 13, color: Color(0xFFE8590C)),
                      ),
                    const Spacer(),
                    if (idea.rating > 0) ...[
                      StarRow(value: idea.rating, size: 11),
                      const SizedBox(width: 6),
                    ],
                    Text(fmtMd(idea.updatedAt), style: TextStyle(fontSize: 10, color: context.faint)),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  idea.title.isEmpty ? '（无标题）' : idea.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35),
                ),
                if (idea.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      richDocPreview(idea.content, max: 80),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.sub, height: 1.55),
                    ),
                  ),
                if (images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final img in images.take(4))
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(img.path),
                              width: 58,
                              height: 58,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 58,
                                height: 58,
                                color: context.divider,
                                child: Icon(Icons.broken_image_outlined, size: 16, color: context.faint),
                              ),
                            ),
                          ),
                        if (images.length > 4)
                          Container(
                            width: 58,
                            height: 58,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: context.divider,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+${images.length - 4}',
                              style: TextStyle(fontSize: 12, color: context.sub),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (idea.linkList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinkList(links: idea.linkList.take(2).toList(), dense: true),
                  ),
                if (idea.tagList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      children: idea.tagList
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
                if (docs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file, size: 13, color: Color(0xFF2B8A3E)),
                        const SizedBox(width: 3),
                        Text(
                          '${docs.length} 个文件',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF2B8A3E)),
                        ),
                      ],
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
