import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../widgets/attachments.dart';
import '../widgets/links.dart';
import 'task_edit_screen.dart';

/// 作业 / 工作（也含自习）的详情页：
/// 看内容、传作业文件照片、翻历史、记老师和领导的点评。
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final int taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  String _role = 'teacher';
  final _personCtl = TextEditingController();
  final _contentCtl = TextEditingController();

  @override
  void dispose() {
    _personCtl.dispose();
    _contentCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final matches = s.tasks.where((t) => t.id == widget.taskId).toList();
    final task = matches.isEmpty ? null : matches.first;
    if (task == null) {
      return const Scaffold(body: Center(child: Text('这条待办已被删除')));
    }
    final course = task.courseId == null ? null : s.courseById(task.courseId);
    final comments = s.commentsOf(task.id!);

    return Scaffold(
      appBar: AppBar(
        title: Text('${task.type.label}详情'),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TaskEditScreen(task: task)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── 基本信息 ──
          Material(
            color: context.card,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: task.type.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          task.type.label,
                          style: TextStyle(
                              fontSize: 10, color: task.type.color, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (task.done)
                        const Icon(Icons.check_circle, size: 16, color: Color(0xFF2B8A3E)),
                      if (task.hasEvaluation) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.star, size: 15, color: Colors.amber.shade700),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    task.title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4),
                  ),
                  if (course != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.menu_book_outlined, size: 13, color: context.faint),
                        const SizedBox(width: 4),
                        Text('关联课程：${course.name}',
                            style: TextStyle(fontSize: 12, color: context.sub)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  _factRow('添加于', fmtDateTime(task.createdAt)),
                  if (task.dueAt != null) _factRow('截止', '${fmtDateTime(task.dueAt)} ${friendlyDay(task.dueAt!)}'),
                  _factRow('状态', task.done ? '已完成 ✅' : '进行中'),
                  if (task.hasSubmitMethod) _factRow('提交方式', task.submitMethod),
                ],
              ),
            ),
          ),
          // ── 说明 / 备注 ──
          if (task.note.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(
              context,
              icon: Icons.notes_outlined,
              title: '要求 / 备注',
              child: Text(task.note, style: const TextStyle(fontSize: 13.5, height: 1.6)),
            ),
          ],
          // ── 提交入口 / 相关链接 ──
          if (task.linkList.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(
              context,
              icon: Icons.link,
              title: '提交入口 / 相关链接',
              child: LinkList(links: task.linkList),
            ),
          ],
          // ── 我的作业：上传文件 / 照片 ──
          const SizedBox(height: 12),
          AttachmentSection(
            ownerType: 'task',
            ownerId: task.id,
            pending: const [],
            title: '我的作业（文件 / 照片）',
            hint: '拍照上传作业、传 Word / PDF 都行',
          ),
          // ── 历史记录 ──
          const SizedBox(height: 12),
          _card(
            context,
            icon: Icons.history,
            title: '历史',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _historyLine('添加了这条${task.type.label}', task.createdAt),
                if (task.done) _historyLine('已完成', null, done: true),
                if (task.hasEvaluation)
                  _historyLine(
                      '收到评价：${task.evaluationText}${task.reviewNote.isEmpty ? '' : ' · ${task.reviewNote}'}',
                      task.evaluatedAt),
                if (comments.isNotEmpty)
                  for (final c in comments) _historyLine('${c.roleLabel}点评（见下方）', c.createdAt),
              ],
            ),
          ),
          // ── 点评 ──
          const SizedBox(height: 12),
          _card(
            context,
            icon: Icons.forum_outlined,
            title: '点评（老师 / 领导 / 自己）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (comments.isEmpty)
                  Text('还没有点评。老师批改完、领导反馈后，记在这里。',
                      style: TextStyle(fontSize: 12, color: context.faint, height: 1.5)),
                for (final c in comments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(c.roleIcon, size: 16, color: c.roleColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    c.person.isEmpty ? c.roleLabel : '${c.person} · ${c.roleLabel}',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.roleColor),
                                  ),
                                  const Spacer(),
                                  Text(fmtDate(c.createdAt), style: TextStyle(fontSize: 10, color: context.faint)),
                                  const SizedBox(width: 2),
                                  InkWell(
                                    onTap: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('删除这条点评？'),
                                          actions: [
                                            TextButton(
                                                onPressed: () => Navigator.of(ctx).pop(false),
                                                child: const Text('取消')),
                                            FilledButton(
                                                onPressed: () => Navigator.of(ctx).pop(true),
                                                child: const Text('删除')),
                                          ],
                                        ),
                                      );
                                      if (ok == true && context.mounted) {
                                        await context.read<AppState>().deleteTaskComment(c.id!);
                                      }
                                    },
                                    child: Icon(Icons.close, size: 13, color: context.faint),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              SelectableText(c.content,
                                  style: const TextStyle(fontSize: 13, height: 1.55)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                // 添加点评
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (code, label) in const [('teacher', '老师'), ('leader', '领导'), ('self', '自己')])
                      ChoiceChip(
                        label: Text(label,
                            style: TextStyle(fontSize: 12, color: _role == code ? Colors.white : context.sub)),
                        selected: _role == code,
                        selectedColor: Theme.of(context).colorScheme.primary,
                        backgroundColor: context.card,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _role = code),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _personCtl,
                  decoration: const InputDecoration(hintText: '具体是谁？比如：李老师（选填）'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _contentCtl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: _role == 'teacher'
                        ? '老师说了什么？比如：第三题思路不对，重做'
                        : _role == 'leader'
                            ? '领导反馈了什么？'
                            : '自己总结一句',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final content = _contentCtl.text.trim();
                      if (content.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('先写点点评内容')));
                        return;
                      }
                      await context.read<AppState>().saveTaskComment(
                            TaskComment(
                              taskId: task.id!,
                              role: _role,
                              person: _personCtl.text.trim(),
                              content: content,
                              createdAt: DateTime.now(),
                            ),
                          );
                      _personCtl.clear();
                      _contentCtl.clear();
                    },
                    child: const Text('记下这条点评'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, {required IconData icon, required String title, required Widget child}) {
    return Material(
      color: context.card,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _factRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: TextStyle(fontSize: 12, color: context.faint)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 12, color: context.sub)),
          ),
        ],
      ),
    );
  }

  Widget _historyLine(String text, DateTime? at, {bool done = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? const Color(0xFF2B8A3E) : context.faint,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              at == null ? text : '$text · ${fmtDateTime(at)}',
              style: TextStyle(fontSize: 12, color: context.sub, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
