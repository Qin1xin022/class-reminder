import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../theme/tokens.dart';

/// 今日待办卡片（今日页 / 待办页共用）
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, required this.onTap, required this.onToggle});

  final TaskItem task;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final overdue = !task.done && isOverdueAt(task.dueAt);
    final course = context.read<AppState>().courseById(task.courseId);
    final sub = <String>[
      if (task.type != TaskType.homework || course != null) task.type.label,
      if (course != null) course.name,
      if (task.dueAt != null) '${friendlyDay(task.dueAt!)} ${hhmmOf(task.dueAt!)}',
    ].join(' · ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: task.type.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(task.type.icon, size: 20, color: task.type.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: task.done ? TextDecoration.lineThrough : null,
                        color: task.done ? context.faint : context.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub.isEmpty ? '未设置时间' : sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.sub),
                    ),
                    if (task.dueAt != null && !task.done)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          leftText(task.dueAt!),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: overdue ? const Color(0xFFD6336C) : const Color(0xFF2B8A3E),
                          ),
                        ),
                      ),
                    if (task.hasEvaluation || task.hasSummary || task.hasSubmitMethod || task.linkList.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            if (task.hasEvaluation)
                              _badge(
                                Icons.grade_outlined,
                                task.score.isEmpty ? '已评价' : task.score,
                                task.reviewer,
                                const Color(0xFFC77D00),
                              ),
                            if (task.hasSummary)
                              _badge(Icons.sticky_note_2_outlined, '有总结', '', Theme.of(context).colorScheme.primary),
                            if (task.hasSubmitMethod)
                              _badge(
                                Icons.send_outlined,
                                _short(task.submitMethod, 14),
                                '',
                                const Color(0xFF2B8A3E),
                              ),
                            if (task.linkList.isNotEmpty)
                              _badge(
                                Icons.link,
                                '${task.linkList.length} 个链接',
                                '',
                                Theme.of(context).colorScheme.primary,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Checkbox(
                value: task.done,
                shape: const CircleBorder(),
                onChanged: (_) => onToggle(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _short(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }

  Widget _badge(IconData icon, String text, String tail, Color color) {    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          tail.isEmpty ? text : '$text · $tail',
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.text, this.icon = Icons.wb_sunny_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: context.faint, size: 26),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: context.sub)),
        ],
      ),
    );
  }
}

/// 日期 + 时间选择（先选日，再选时分）
Future<DateTime?> pickDateTime(BuildContext context, DateTime? initial, {bool withTime = true}) async {
  final now = DateTime.now();
  final base = initial ?? now.add(const Duration(hours: 1));
  final picked = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5),
  );
  if (picked == null) return null;
  if (!withTime) return DateTime(picked.year, picked.month, picked.day);
  if (!context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
  );
  if (time == null) return null;
  return DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
}
