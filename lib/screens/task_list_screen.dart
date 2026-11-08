import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import '../widgets/folder_ui.dart';
import 'task_detail_screen.dart';
import 'task_edit_screen.dart';
import '../theme/tokens.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  String _filter = 'all';
  int? _folderId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final path = s.folderPath(_folderId);
    final subs = s.foldersOf('task', _folderId);

    var list = s.tasks.where((t) {
      if (t.folderId != _folderId) return false;
      if (_filter == 'done') return t.done;
      if (t.done) return false;
      if (_filter == 'all') return true;
      return t.type.code == _filter;
    }).toList();

    list = list
      ..sort((a, b) {
        final ad = a.dueAt?.millisecondsSinceEpoch ?? 1 << 62;
        final bd = b.dueAt?.millisecondsSinceEpoch ?? 1 << 62;
        return ad.compareTo(bd);
      });

    final today = dateOnly(DateTime.now());
    final now = DateTime.now();
    final groups = <String, List<TaskItem>>{};
    for (final t in list) {
      String key;
      if (_filter == 'done') {
        key = '已完成';
      } else if (t.dueAt == null) {
        key = '没设截止时间';
      } else if (isOverdueAt(t.dueAt, now: now)) {
        key = '已逾期';
      } else if (dateOnly(t.dueAt!) == today) {
        key = '今天';
      } else if (dateOnly(t.dueAt!) == today.add(const Duration(days: 1))) {
        key = '明天';
      } else {
        key = '之后';
      }
      groups.putIfAbsent(key, () => []).add(t);
    }
    const order = ['已逾期', '今天', '明天', '之后', '没设截止时间', '已完成'];
    final keys = order.where(groups.containsKey).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('任务 · 作业 / 自习 / 工作'),
        actions: [
          IconButton(
            tooltip: '新建文件夹',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () async {
              final name = await showFolderNameDialog(context);
              if (name == null) return;
              await context.read<AppState>().createFolder(name, 'task', _folderId);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TaskEditScreen(presetFolderId: _folderId)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('新建'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          FolderBreadcrumb(
            path: path,
            onJump: (i) => setState(() {
              _folderId = i < 0 ? null : path[i].id;
            }),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('all', '全部'),
                _chip('homework', '作业'),
                _chip('study', '自习'),
                _chip('work', '工作'),
                _chip('done', '已完成'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (subs.isNotEmpty) ...[
            SectionTitle(title: '文件夹（${subs.length}）'),
            for (final f in subs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SubfolderTile(
                  folder: f,
                  onOpen: () => setState(() => _folderId = f.id),
                ),
              ),
          ],
          if (keys.isEmpty && subs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyHint(text: '这里还空着，点右下角新建一条，或用右上角建个文件夹分类'),
            ),
          for (final k in keys) ...[
            SectionTitle(title: '$k（${groups[k]!.length}）'),
            ...groups[k]!.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TaskTile(
                  task: t,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id!)),
                  ),
                  onToggle: () => context.read<AppState>().toggleTask(t),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
        selected: selected,
        selectedColor: Theme.of(context).colorScheme.primary,
        backgroundColor: context.card,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }
}
