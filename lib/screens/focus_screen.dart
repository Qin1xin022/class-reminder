import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import '../widgets/focus_card.dart';
import '../theme/tokens.dart';

/// 专注记录：今日/本周统计 + 全部记录。
class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final sessions = s.focusSessions;
    final byType = s.todayFocusByType;

    return Scaffold(
      appBar: AppBar(title: const Text('专注记录')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const FocusCard(),
          SectionTitle(title: '统计'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      _Stat(label: '今日', value: fmtDuration(s.todayFocusSeconds)),
                      _Stat(label: '本周', value: fmtDuration(s.weekFocusSeconds)),
                    ],
                  ),
                  const Divider(height: 22),
                  Row(
                    children: TaskType.values.map((t) {
                      return Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.label,
                              style: TextStyle(fontSize: 11, color: t.color, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              fmtDuration(byType[t] ?? 0),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          SectionTitle(
            title: '全部记录',
            trailing: Text(
              '${sessions.length} 次',
              style: TextStyle(fontSize: 12, color: context.sub),
            ),
          ),
          if (sessions.isEmpty)
            const EmptyHint(text: '还没有专注记录，回首页点「开始」试试', icon: Icons.timer_outlined)
          else
            ...sessions.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FocusTile(session: f),
              ),
            ),
        ],
      ),
    );
  }
}

class _FocusTile extends StatelessWidget {
  const _FocusTile({required this.session});

  final FocusSession session;

  @override
  Widget build(BuildContext context) {
    final f = session;
    final end = f.endAt;
    final sub = end == null
        ? '进行中 · ${hhmmOf(f.startAt)} 开始'
        : '${friendlyDay(f.startAt)} ${hhmmOf(f.startAt)}-${hhmmOf(end)}';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: f.type.color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(f.type.icon, size: 20, color: f.type.color),
        ),
        title: Text(
          f.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(sub, style: TextStyle(fontSize: 12, color: context.sub)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              f.running ? '计时中' : fmtDuration(f.seconds),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: f.running ? f.type.color : context.sub,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, size: 18, color: context.faint),
              onPressed: () => _confirmDelete(context, f),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, FocusSession f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text('${f.type.label} · ${fmtDuration(f.seconds)}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    if (f.id == null) return;
    await context.read<AppState>().deleteFocus(f.id!);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: context.sub)),
        ],
      ),
    );
  }
}
