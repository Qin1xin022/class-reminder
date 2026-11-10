import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';

/// 课程时间设置：照自己学校的作息改每节课的上下课时间。
/// - 每节课时长 / 课间休息：一键重排全部节次
/// - 课程总节数：加减号增减
/// - 每一节都可以单独改时间；学校没有的节设为「无」
class PeriodSettingsScreen extends StatelessWidget {
  const PeriodSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final periods = s.periods;
    final lessonLen = _firstLen(periods) ?? 45;
    final breakLen = _firstGap(periods) ?? 5;

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程时间设置'),
        actions: [
          IconButton(
            tooltip: '恢复广工默认作息',
            onPressed: () => context.read<AppState>().setPeriods(AppState.kDefaultPeriods),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('每节课时长'),
                  trailing: _chev('$lessonLen 分钟'),
                  onTap: () => _pickLen(context, lessonLen),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: const Text('课间休息时长'),
                  trailing: _chev('$breakLen 分钟'),
                  onTap: () => _pickGap(context, breakLen),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('课程总节数'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: periods.length <= 1
                        ? null
                        : () => context.read<AppState>().setPeriods(periods.sublist(0, periods.length - 1)),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text('${periods.length}', textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: periods.length >= 16 ? null : () => _addPeriod(context, periods),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < periods.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  ListTile(
                    title: Text('第${i + 1}节课'),
                    trailing: _chev(_rowLabel(periods[i])),
                    onTap: () => _editPeriod(context, i),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '改动立即生效，课表会按这里的上下课时间自动对齐。\n'
              '如果你们学校某一节不存在，点它选「设为无」；想整体调整就先改上面的时长，再微调单节。',
              style: TextStyle(fontSize: 11.5, height: 1.6, color: context.faint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chev(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600)),
        const SizedBox(width: 2),
        Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
      ],
    );
  }

  String _rowLabel((int, int) p) {
    if (p.$1 <= 0 && p.$2 <= 0) return '无';
    return '${hhmm(p.$1)}-${hhmm(p.$2)}';
  }

  int? _firstLen(List<(int, int)> periods) {
    for (final p in periods) {
      if (p.$2 > p.$1) return p.$2 - p.$1;
    }
    return null;
  }

  int? _firstGap(List<(int, int)> periods) {
    for (var i = 1; i < periods.length; i++) {
      final prev = periods[i - 1];
      final cur = periods[i];
      if (prev.$2 > prev.$1 && cur.$1 >= prev.$2) return cur.$1 - prev.$2;
    }
    return null;
  }

  // ------------------------------------------------------------ 交互

  Future<int?> _pickMinutes(BuildContext context, String title, int current, List<int> options) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 260,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final v in options)
                ChoiceChip(
                  label: Text('$v 分钟'),
                  selected: v == current,
                  onSelected: (_) => Navigator.of(ctx).pop(v),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消'))],
      ),
    );
  }

  Future<void> _pickLen(BuildContext context, int current) async {
    final v = await _pickMinutes(context, '每节课时长', current, [30, 35, 40, 45, 50, 55, 60, 90]);
    if (v == null || v == current) return;
    if (!context.mounted) return;
    final gap = _firstGap(context.read<AppState>().periods) ?? 5;
    _regenerate(context, v, gap);
  }

  Future<void> _pickGap(BuildContext context, int current) async {
    final v = await _pickMinutes(context, '课间休息时长', current, [0, 5, 10, 15, 20]);
    if (v == null || v == current) return;
    if (!context.mounted) return;
    final len = _firstLen(context.read<AppState>().periods) ?? 45;
    _regenerate(context, len, v);
  }

  /// 从第一节开始时间起，按「每节 len 分钟 + 课间 gap 分钟」重排所有节
  Future<void> _regenerate(BuildContext context, int len, int gap) async {
    final s = context.read<AppState>();
    final first = s.periods.firstWhere((p) => p.$2 > p.$1, orElse: () => (510, 555));
    final out = <(int, int)>[];
    var cur = first.$1;
    for (var i = 0; i < s.periods.length; i++) {
      final end = cur + len;
      if (end > 1440) break;
      out.add((cur, end));
      cur = end + gap;
    }
    while (out.length < s.periods.length) {
      out.add((0, 0)); // 排不下的算「无」
    }
    await s.setPeriods(out);
  }

  Future<void> _addPeriod(BuildContext context, List<(int, int)> periods) async {
    // 找最后一节「有课」的节，接在它后面
    var last = periods.last;
    for (final p in periods.reversed) {
      if (p.$2 > p.$1) {
        last = p;
        break;
      }
    }
    final start = last.$2 > last.$1 ? last.$2 + 5 : 510;
    final end = start + (firstLenOf(periods) ?? 45);
    if (end > 1440) return;
    await context.read<AppState>().setPeriods([...periods, (start, end)]);
  }

  int? firstLenOf(List<(int, int)> periods) {
    for (final p in periods) {
      if (p.$2 > p.$1) return p.$2 - p.$1;
    }
    return null;
  }

  Future<void> _editPeriod(BuildContext context, int index) async {
    final s = context.read<AppState>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('设置上下课时间'),
              onTap: () => Navigator.of(ctx).pop('time'),
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('设为无（这一节不存在）'),
              onTap: () => Navigator.of(ctx).pop('none'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('恢复这一节为有课'),
              onTap: () => Navigator.of(ctx).pop('restore'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final periods = List<(int, int)>.from(s.periods);
    if (action == 'none') {
      periods[index] = (0, 0);
      await s.setPeriods(periods);
      return;
    }
    if (action == 'restore') {
      periods[index] = (510 + index * 50, 555 + index * 50);
      await s.setPeriods(periods);
      return;
    }

    // 设置时间：先选上课，再选下课
    final cur = periods[index];
    final start = await showTimePicker(
      context: context,
      initialTime: _td(cur.$1 > 0 ? cur.$1 : 510),
      helpText: '第${index + 1}节 上课时间',
      cancelText: '取消',
      confirmText: '下一步',
    );
    if (start == null || !context.mounted) return;
    final startMin = start.hour * 60 + start.minute;
    final end = await showTimePicker(
      context: context,
      initialTime: _td(startMin + 45 <= 1440 ? startMin + 45 : 1440),
      helpText: '第${index + 1}节 下课时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (end == null || !context.mounted) return;
    final endMin = end.hour * 60 + end.minute;
    if (endMin <= startMin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下课时间要比上课时间晚')));
      return;
    }
    periods[index] = (startMin, endMin);
    await s.setPeriods(periods);
  }

  TimeOfDay _td(int minutes) {
    final m = minutes.clamp(0, 1439);
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }
}
