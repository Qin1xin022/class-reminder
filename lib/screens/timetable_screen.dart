import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import 'course_edit_screen.dart';

/// 一整屏 = 一整周：行是每节课，列是周一到周日，左右滑动换周
/// 每节课的上下课时间可在「我的 → 课程时间设置」里改（AppState.periods）。
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> with WidgetsBindingObserver {
  static const int _center = 24;
  late final PageController _pc = PageController(initialPage: _center);
  int _page = _center;

  int get _weekDelta => _page - _center;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧后校正：初始定位偶发被启动动画/首帧尺寸变化带偏一页，拉回本周。
    WidgetsBinding.instance.addPostFrameCallback((_) => _snapCenter());
  }

  @override
  void didChangeMetrics() => _snapCenter();

  void _snapCenter() {
    if (!mounted || !_pc.hasClients) return;
    final p = _pc.page ?? _center;
    if (p.round() != _center && _page == _center) {
      _pc.jumpToPage(_center);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pc.dispose();
    super.dispose();
  }

  void _goCenter() {
    if (!_pc.hasClients) return;
    _pc.animateToPage(_center, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final week = s.currentWeek + _weekDelta;
    final periods = s.periods;

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程表'),
        actions: [
          IconButton(
            tooltip: '导入课表',
            onPressed: _showImportDialog,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: '新增课程',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CourseEditScreen()),
            ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          _weekBar(context, s, week),
          _headRow(context, s, week),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, cons) {
                final rowH = (cons.maxHeight / periods.length).clamp(24.0, 78.0);
                return PageView.builder(
                  controller: _pc,
                  itemCount: _center * 2 + 1,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: _WeekGrid(
                      week: s.currentWeek + (i - _center),
                      currentWeek: s.currentWeek,
                      courses: s.courses,
                      periods: periods,
                      rowH: rowH,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekBar(BuildContext context, AppState s, int week) {
    final now = DateTime.now();
    final monday = dateOnly(now).subtract(Duration(days: now.weekday - 1)).add(Duration(days: _weekDelta * 7));
    final sunday = monday.add(const Duration(days: 6));
    final range = '${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 2),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _weekDelta > -_center ? () => _pc.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut) : null,
            icon: const Icon(Icons.chevron_left, size: 22),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '第 $week 周',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Text(range, style: TextStyle(fontSize: 10.5, color: context.faint)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _weekDelta < _center ? () => _pc.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut) : null,
            icon: const Icon(Icons.chevron_right, size: 22),
          ),
          if (_weekDelta != 0)
            TextButton(
              onPressed: _goCenter,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('本周', style: TextStyle(fontSize: 12)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('本周', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _headRow(BuildContext context, AppState s, int week) {
    const gutter = 34.0;
    final now = DateTime.now();
    final monday = dateOnly(now).subtract(Duration(days: now.weekday - 1)).add(Duration(days: (week - s.currentWeek) * 7));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: LayoutBuilder(builder: (ctx, cons) {
        final colW = (cons.maxWidth - gutter) / 7;
        return Row(
          children: [
            const SizedBox(width: gutter),
            for (var i = 1; i <= 7; i++)
              SizedBox(
                width: colW,
                child: Column(
                  children: [
                    Text(
                      weekdayLabel(i),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: i == now.weekday && week == s.currentWeek ? FontWeight.w800 : FontWeight.w600,
                        color: i == now.weekday && week == s.currentWeek
                            ? Theme.of(context).colorScheme.primary
                            : context.sub,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${monday.add(Duration(days: i - 1)).day}',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: i == now.weekday && week == s.currentWeek
                            ? Theme.of(context).colorScheme.primary
                            : context.faint,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }

  /// 从内置种子导入课表（解析自用户的 课程表.xlsx）
  Future<void> _showImportDialog() async {
    String raw;
    try {
      raw = await rootBundle.loadString('assets/timetable_seed.json');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('内置课表数据缺失，请手动添加课程')));
      return;
    }
    List<dynamic> seed;
    try {
      seed = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('内置课表数据格式错误')));
      return;
    }
    final wdn = '一二三四五六日';
    final preview = seed.take(6).map((c) {
      final m = c as Map;
      return '周${wdn[((m['weekday'] as num).toInt()) - 1]} ${m['name']}'
          ' 第${m['weekStart']}-${m['weekEnd']}周';
    }).join('\n');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('导入本学期课表（共 ${seed.length} 条时段）？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview, style: const TextStyle(fontSize: 12, height: 1.6)),
            const SizedBox(height: 8),
            const Text('解析自你的《课程表.xlsx》。同名同星期的已有课程不会重复导入；'
                '节次时间如与学校实际有出入，导入后点课程卡片可改。',
                style: TextStyle(fontSize: 11, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('导入')),
        ],
      ),
    );
    if (confirmed != true) return;
    final r = await context.read<AppState>().importSeedCourses(seed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.added == 0 ? '没有新增课程（都已存在）' : '导入完成：新增 ${r.added} 条，跳过重复 ${r.skipped} 条'),
    ));
  }
}

/// 一周的节次网格
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.week,
    required this.currentWeek,
    required this.courses,
    required this.periods,
    required this.rowH,
  });

  final int week;
  final int currentWeek;
  final List<Course> courses;
  final List<(int, int)> periods;
  final double rowH;

  static const double gutter = 34;

  bool _exists((int, int) p) => p.$1 > 0 || p.$2 > 0; // (0,0) = 这一节「无」

  /// 课程时间 → 覆盖的节次行区间 [first, last]（跳过「无」的行）
  (int, int) _span(int startMin, int endMin) {
    final idx = [
      for (var i = 0; i < periods.length; i++)
        if (_exists(periods[i])) i
    ];
    if (idx.isEmpty) return (0, 0);
    var first = idx.first;
    for (final i in idx) {
      if (startMin < periods[i].$2) {
        first = i;
        break;
      }
    }
    var last = idx.last;
    for (var i = idx.length - 1; i >= 0; i--) {
      if (endMin > periods[idx[i]].$1) {
        last = idx[i];
        break;
      }
    }
    if (last < first) last = first;
    return (first, last);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isThisWeek = week == currentWeek;
    final monday = dateOnly(now)
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: (week - currentWeek) * 7));
    final gridH = rowH * periods.length;

    return LayoutBuilder(builder: (ctx, cons) {
      final colW = (cons.maxWidth - gutter) / 7;
      final todayIdx = now.weekday;

      // 本周的课
      final list = courses.where((c) => week >= c.weekStart && week <= c.weekEnd).toList();

      // 简单的分栏算法：同一天时间重叠的课并排放
      final lanes = <int, List<int>>{}; // courseIndex -> [lane, laneCount]
      for (final c in list) {
        final sameDay = list.where((o) =>
            o.weekday == c.weekday && o.startMin < c.endMin && c.startMin < o.endMin).toList();
        final idx = sameDay.indexOf(c);
        final n = sameDay.length;
        lanes[list.indexOf(c)] = [idx < 0 ? 0 : idx, n < 1 ? 1 : n];
      }

      return SizedBox(
        height: gridH,
        child: Stack(
          children: [
            // 今天整列高亮
            if (isThisWeek)
              Positioned(
                left: gutter + (todayIdx - 1) * colW + 1,
                width: colW - 2,
                top: 0,
                height: gridH,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            // 横线（每节之间）
            for (var i = 0; i <= periods.length; i++)
              Positioned(
                left: gutter,
                right: 0,
                top: i * rowH,
                child: Container(height: 0.6, color: context.divider),
              ),
            // 竖线
            for (var i = 1; i <= 7; i++)
              Positioned(
                left: gutter + i * colW,
                top: 0,
                height: gridH,
                child: Container(width: 0.6, color: context.divider),
              ),
            // 左侧节次刻度
            for (var i = 0; i < periods.length; i++)
              Positioned(
                left: 0,
                width: gutter - 4,
                top: i * rowH,
                height: rowH,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${i + 1}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.sub, height: 1.1),
                    ),
                    if (rowH >= 44 && _exists(periods[i]))
                      Text(
                        hhmm(periods[i].$1),
                        style: TextStyle(fontSize: 7.5, color: context.faint, height: 1.2),
                      ),
                  ],
                ),
              ),
            // 课程块
            for (var i = 0; i < list.length; i++) _courseBlock(context, list[i], i, lanes, colW, monday, isThisWeek, now),
          ],
        ),
      );
    });
  }

  Widget _courseBlock(
    BuildContext context,
    Course c,
    int idx,
    Map<int, List<int>> lanes,
    double colW,
    DateTime monday,
    bool isThisWeek,
    DateTime now,
  ) {
    final (first, last) = _span(c.startMin, c.endMin);    final lane = lanes[idx]!;
    final laneCount = lane[1];
    final laneW = colW / laneCount;
    final top = first * rowH;
    final height = (last - first + 1) * rowH - 3;

    final courseEnd = monday.add(Duration(days: c.weekday - 1, minutes: c.endMin));
    final isPast = isThisWeek && courseEnd.isBefore(now);
    final color = Color(c.color);
    final dense = height < 54;

    return Positioned(
      left: gutter + (c.weekday - 1) * colW + lane[0] * laneW + 1.5,
      top: top + 1.5,
      width: laneW - 3,
      height: height,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CourseEditScreen(course: c)),
        ),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: laneW < 46 ? 3 : 5, vertical: 3),
          decoration: BoxDecoration(
            color: isPast
                ? (context.isDark ? const Color(0xFF4A4F5C) : const Color(0xFFC3C8D3))
                : color,
            borderRadius: BorderRadius.circular(7),
          ),
          child: ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  maxLines: dense ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: laneW < 46 ? 9 : 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.18,
                    decoration: isPast ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white70,
                  ),
                ),
                if (!dense) const SizedBox(height: 1),
                if (!dense)
                  Text(
                    c.location.isEmpty ? '${hhmm(c.startMin)}' : c.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 8.5, height: 1.2),
                  ),
                if (!dense && height > 96)
                  Text(
                    '${hhmm(c.startMin)}-${hhmm(c.endMin)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 8, height: 1.2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
