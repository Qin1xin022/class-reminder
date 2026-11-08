import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// 新建 / 重命名文件夹的输入框
Future<String?> showFolderNameDialog(BuildContext context, {String? initial, String title = '新建文件夹'}) async {
  final controller = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '例如：高数 / 英语四级 / 班级通知'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.isEmpty) return null;
  return result;
}

/// 面包屑：全部 / 一级 / 二级 …
class FolderBreadcrumb extends StatelessWidget {
  const FolderBreadcrumb({super.key, required this.path, required this.onJump});

  final List<Folder> path;
  final ValueChanged<int> onJump; // -1 表示「全部」

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          _crumb(context, '全部', active: path.isEmpty, onTap: () => onJump(-1)),
          for (var i = 0; i < path.length; i++) ...[
            Icon(Icons.chevron_right, size: 16, color: context.faint),
            _crumb(context, path[i].name, active: i == path.length - 1, onTap: () => onJump(i)),
          ],
        ],
      ),
    );
  }

  Widget _crumb(BuildContext context, String text, {required bool active, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Theme.of(context).colorScheme.primary : context.sub,
          ),
        ),
      ),
    );
  }
}

/// 一个子文件夹卡片（点击进入，长按/右侧菜单重命名、删除）
class SubfolderTile extends StatelessWidget {
  const SubfolderTile({super.key, required this.folder, required this.onOpen});

  final Folder folder;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final count = state.folderItemCount(folder);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        onLongPress: () => _showMenu(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC300).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.folder_rounded, size: 21, color: Color(0xFFE8A200)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text('$count 项', style: TextStyle(fontSize: 11, color: context.faint)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _showMenu(context),
                icon: Icon(Icons.more_horiz, size: 18, color: context.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final state = context.read<AppState>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFD6336C)),
              title: const Text('删除文件夹（里面的内容会移到上一级）', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'rename') {
      final name = await showFolderNameDialog(context, initial: folder.name, title: '重命名文件夹');
      if (name != null) await state.renameFolder(folder.id!, name);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('删除「${folder.name}」？'),
          content: const Text('文件夹里的笔记/待办会移动到上一级，不会被删除。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
          ],
        ),
      );
      if (ok == true) await state.deleteFolder(folder.id!);
    }
  }
}

/// 编辑页里的「所在文件夹」一行，点开选文件夹
class FolderRow extends StatelessWidget {
  const FolderRow({super.key, required this.folderName, required this.onTap});

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

/// 选择文件夹（编辑条目时用），返回 folderId，null 表示根目录
Future<int?> pickFolder(BuildContext context, String scope, int? current) async {
  final state = context.read<AppState>();
  final path = <Folder>[];
  Folder? chosen;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final currentId = path.isEmpty ? null : path.last.id;
        final subs = state.foldersOf(scope, currentId);
        return SafeArea(
          child: SizedBox(
            height: 440,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(
                    children: [
                      FolderBreadcrumb(
                        path: path,
                        onJump: (i) => setSheetState(() {
                          if (i < 0) {
                            path.clear();
                          } else {
                            path.removeRange(i + 1, path.length);
                          }
                        }),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('取消'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        leading: Icon(Icons.folder_open, color: Theme.of(context).colorScheme.primary),
                        title: Text(currentId == null ? '放在根目录（当前）' : '放到这里（根目录）'),
                        trailing: currentId == null ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                        onTap: () => Navigator.of(ctx).pop(),
                      ),
                      for (final f in subs)
                        ListTile(
                          leading: const Icon(Icons.folder_rounded, color: Color(0xFFE8A200)),
                          title: Text(f.name),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => setSheetState(() => path.add(f)),
                        ),
                      if (subs.isEmpty)
                        Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('这里还没有子文件夹', style: TextStyle(fontSize: 12, color: context.faint)),
                        ),
                    ],
                  ),
                ),
                if (path.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      onPressed: () {
                        chosen = path.last;
                        Navigator.of(ctx).pop();
                      },
                      child: Text('放到「${path.last.name}」'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
  final picked = chosen;
  if (picked != null) return picked.id;
  return current;
}
