import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import '../widgets/focus_card.dart';
import '../widgets/tab_switch.dart';
import 'course_edit_screen.dart';
import 'exam_list_screen.dart';
import 'focus_screen.dart';
import 'knowledge_screen.dart';
import 'notice_list_screen.dart';
import 'review_hub_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'task_detail_screen.dart';
import 'task_edit_screen.dart';
import 'competition_list_screen.dart';

/// 今日：一块概览 + 今天要上的课 + 今天要做的事 + 功能入口，尽量集中不散
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final now = DateTime.now();
    final todayCourses = s.coursesOfDay(now.weekday);
    final todayTasks = s.pendingForToday;
    final reviewed = s.reviewOf(fmtDate(now)) != null;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
          children: [
            _Header(
              now: now,
              week: s.currentWeek,
              courseCount: todayCourses.length,
              taskCount: todayTasks.length,
              overdue: s.overdueCount,
              reviewed: reviewed,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QuickAdd(
                    icon: Icons.menu_book_outlined,
                    label: '加作业',
                    color: TaskType.homework.color,
                    onTap: () => _openTask(context, TaskType.homework),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAdd(
                    icon: Icons.self_improvement,
                    label: '排自习',
                    color: TaskType.study.color,
                    onTap: () => _openTask(context, TaskType.study),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAdd(
                    icon: Icons.work_outline,
                    label: '记工作',
                    color: TaskType.work.color,
                    onTap: () => _openTask(context, TaskType.work),
                  ),
                ),
              ],
            ),
            SectionTitle(
              title: '今日课程',
              trailing: _TopLink(
                text: todayCourses.isEmpty ? '整周课表' : '整周课表',
                onTap: () => TabSwitch.to(context, 1),
              ),
            ),
            _TodayCourses(courses: todayCourses),
            SectionTitle(
              title: '今天要做',
              trailing: _TopLink(
                text: todayTasks.isEmpty ? '暂无' : '${todayTasks.length} 项 · 全部',
                onTap: () => TabSwitch.to(context, 2),
              ),
            ),
            _TodayTasks(tasks: todayTasks),
            const SectionTitle(title: '功能'),
            _EntryGrid(s: s),
            SectionTitle(
              title: '专注 · 计时',
              trailing: _TopLink(
                text: '记录',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FocusScreen()),
                ),
              ),
            ),
            const FocusCard(),
            SectionTitle(
              title: '今日复盘',
              trailing: reviewed
                  ? Text('已复盘', style: TextStyle(fontSize: 12, color: context.faint))
                  : null,
            ),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                leading: Icon(
                  reviewed ? Icons.task_alt : Icons.rate_review_outlined,
                  color: reviewed ? const Color(0xFF2B8A3E) : Theme.of(context).colorScheme.primary,
                ),
                title: Text(reviewed ? '今天已复盘，可继续修改' : '花 2 分钟回顾今天',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('完成了什么 / 卡在哪里 / 明天最重要的一件事',
                    style: TextStyle(fontSize: 11.5)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ReviewScreen(day: DateTime.now())),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTask(BuildContext context, TaskType type) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskEditScreen(presetType: type)),
    );
  }
}

/// 小标题右侧的文字按钮
class _TopLink extends StatelessWidget {
  const _TopLink({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            Text(text, style: TextStyle(fontSize: 12, color: context.sub)),
            Icon(Icons.chevron_right, size: 14, color: context.faint),
          ],
        ),
      ),
    );
  }
}

/// 今日课程：一张卡里紧凑排完
class _TodayCourses extends StatelessWidget {
  const _TodayCourses({required this.courses});

  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined, size: 18, color: context.faint),
            const SizedBox(width: 8),
            Text('今天没课，安排点自己的事吧', style: TextStyle(fontSize: 13, color: context.sub)),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    return Container(
      decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          for (var i = 0; i < courses.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: context.divider),
            _courseLine(context, courses[i], nowMin),
          ],
        ],
      ),
    );
  }

  Widget _courseLine(BuildContext context, Course c, int nowMin) {
    final color = Color(c.color);
    final done = nowMin >= c.endMin;
    final live = nowMin >= c.startMin && nowMin < c.endMin;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CourseEditScreen(course: c)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: done ? context.faint : color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 42,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hhmm(c.startMin),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: done ? context.faint : context.text,
                    ),
                  ),
                  Text(
                    hhmm(c.endMin),
                    style: TextStyle(fontSize: 9.5, color: context.faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: done ? context.sub : context.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: context.faint,
                    ),
                  ),
                  if (c.location.isNotEmpty || c.teacher.isNotEmpty)
                    Text(
                      [c.location, c.teacher].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: context.sub),
                    ),
                ],
              ),
            ),
            if (live)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('上课中',
                    style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w700)),
              ),
            Icon(Icons.chevron_right, size: 16, color: context.faint),
          ],
        ),
      ),
    );
  }
}

/// 今天要做：一张卡里最多 5 条，多的收纳到「全部」
class _TodayTasks extends StatelessWidget {
  const _TodayTasks({required this.tasks});

  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: context.faint),
            const SizedBox(width: 8),
            Text('今天没有到期任务，去预习或复盘一下吧', style: TextStyle(fontSize: 13, color: context.sub)),
          ],
        ),
      );
    }

    final shown = tasks.take(5).toList();
    final rest = tasks.length - shown.length;

    return Container(
      decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: context.divider),
            _taskLine(context, shown[i]),
          ],
          if (rest > 0)
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => TabSwitch.to(context, 2),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('还有 $rest 项 · 查看全部',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _taskLine(BuildContext context, TaskItem t) {
    final overdue = !t.done && isOverdueAt(t.dueAt);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id!)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        child: Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => context.read<AppState>().toggleTask(t),
              icon: Icon(
                t.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: t.done ? const Color(0xFF2B8A3E) : context.faint,
              ),
            ),
            const SizedBox(width: 2),
            Container(
              width: 3,
              height: 30,
              decoration: BoxDecoration(
                color: t.type.color.withOpacity(0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: t.done ? TextDecoration.lineThrough : null,
                      color: t.done ? context.faint : context.text,
                    ),
                  ),
                  Text(
                    [
                      t.type.label,
                      if (t.dueAt != null) '${friendlyDay(t.dueAt!)} ${hhmmOf(t.dueAt!)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: overdue ? const Color(0xFFE03131) : context.sub,
                      fontWeight: overdue ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: context.faint),
          ],
        ),
      ),
    );
  }
}

/// 功能入口：3 列 2 行，一屏收起
class _EntryGrid extends StatelessWidget {
  const _EntryGrid({required this.s});

  final AppState s;

  @override
  Widget build(BuildContext context) {
    final next = s.nextExam;
    final examSub = next == null
        ? (s.gpaStats.gpa != null ? '绩点 ${s.gpaStats.gpa!.toStringAsFixed(2)}' : '记考试 / 成绩')
        : (() {
            final days = next.startAt.difference(DateTime.now()).inDays;
            return days >= 1 ? '${next.name} · $days天' : '${next.name} · 马上';
          })();

    final items = <_GridItem>[
      _GridItem(
        icon: Icons.emoji_events_outlined,
        color: const Color(0xFFFFA94D),
        title: '比赛',
        sub: s.upcomingCompetitions.isEmpty ? '暂无进行中' : '${s.upcomingCompetitions.length} 场未结束',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CompetitionListScreen()),
        ),
      ),
      _GridItem(
        icon: Icons.campaign_outlined,
        color: const Color(0xFFD6336C),
        title: '通知',
        sub: s.notices.isEmpty
            ? '暂无收藏'
            : (s.nextDeadlineNotice?.deadlineAt != null
                ? '最近 ${fmtMd(s.nextDeadlineNotice!.deadlineAt!)} 截止'
                : '${s.unreadNoticeCount} 条未读'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NoticeListScreen()),
        ),
      ),
      _GridItem(
        icon: Icons.lightbulb_outline,
        color: const Color(0xFF7048E8),
        title: '灵感库',
        sub: s.ideaCount == 0 ? '记点子 / 痛点' : '${s.ideaCount} 条',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const KnowledgeScreen(initialTab: 1)),
        ),
      ),
      _GridItem(
        icon: Icons.grade_outlined,
        color: const Color(0xFF1971C2),
        title: '考试 · 成绩',
        sub: examSub,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ExamListScreen()),
        ),
      ),
      _GridItem(
        icon: Icons.auto_stories_outlined,
        color: const Color(0xFF0CA678),
        title: '总结汇总',
        sub: '考前翻一遍',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReviewHubScreen()),
        ),
      ),
      _GridItem(
        icon: Icons.person_outline,
        color: const Color(0xFF868E96),
        title: '我的',
        sub: '主题 / 备份',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 82,
      ),
      itemBuilder: (_, i) => _GridCell(item: items[i]),
    );
  }
}

class _GridItem {
  const _GridItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;
}

class _GridCell extends StatelessWidget {
  const _GridCell({required this.item});

  final _GridItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(item.icon, size: 17, color: item.color),
              ),
              const Spacer(),
              Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              Text(
                item.sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, color: context.sub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.now,
    required this.week,
    required this.courseCount,
    required this.taskCount,
    required this.overdue,
    required this.reviewed,
  });

  final DateTime now;
  final int week;
  final int courseCount;
  final int taskCount;
  final int overdue;
  final bool reviewed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: context.brandGradient,
      ),
      child: Stack(
        children: [
          const Positioned(
            right: 44,
            top: 26,
            width: 96,
            height: 86,
            child: IgnorePointer(child: CustomPaint(painter: _CatLinePainter())),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${now.month} 月 ${now.day} 日 · ${weekdayLabel(now.weekday)}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '第 $week 周 · ${reviewed ? '今日已复盘' : '别忘了睡前复盘'}',
                          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        ),
                        icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 20),
                        tooltip: '我的 / 设置',
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ReviewScreen(day: DateTime.now())),
                        ),
                        icon: const Icon(Icons.bolt, color: Colors.white, size: 22),
                        tooltip: '今日复盘',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Stat(label: '今日课程', value: '$courseCount'),
                  _Stat(label: '今日待办', value: '$taskCount'),
                  _Stat(label: '已逾期', value: '$overdue', warn: overdue > 0),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: warn ? const Color(0xFFFFD43B) : Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11)),
        ],
      ),
    );
  }
}

class _QuickAdd extends StatelessWidget {
  const _QuickAdd({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 简约线条小猫：白色半透明线稿，纯装饰
class _CatLinePainter extends CustomPainter {
  const _CatLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    final cx = w * 0.52;
    final headR = w * 0.34;
    final headC = Offset(cx, h * 0.52);

    canvas.drawOval(
      Rect.fromCenter(center: headC, width: headR * 2, height: headR * 1.82),
      paint,
    );
    final path = Path()
      ..moveTo(headC.dx - headR * 0.86, headC.dy - headR * 0.72)
      ..lineTo(headC.dx - headR * 1.02, headC.dy - headR * 1.52)
      ..lineTo(headC.dx - headR * 0.3, headC.dy - headR * 1.1);
    canvas.drawPath(path, paint);
    final path2 = Path()
      ..moveTo(headC.dx + headR * 0.86, headC.dy - headR * 0.72)
      ..lineTo(headC.dx + headR * 1.02, headC.dy - headR * 1.52)
      ..lineTo(headC.dx + headR * 0.3, headC.dy - headR * 1.1);
    canvas.drawPath(path2, paint);
    final eye1 = Path()
      ..moveTo(headC.dx - headR * 0.5, headC.dy - headR * 0.06)
      ..quadraticBezierTo(
          headC.dx - headR * 0.28, headC.dy - headR * 0.34, headC.dx - headR * 0.06, headC.dy - headR * 0.06);
    canvas.drawPath(eye1, paint);
    final eye2 = Path()
      ..moveTo(headC.dx + headR * 0.06, headC.dy - headR * 0.06)
      ..quadraticBezierTo(
          headC.dx + headR * 0.28, headC.dy - headR * 0.34, headC.dx + headR * 0.5, headC.dy - headR * 0.06);
    canvas.drawPath(eye2, paint);
    final mouth = Path()
      ..moveTo(headC.dx - headR * 0.26, headC.dy + headR * 0.3)
      ..quadraticBezierTo(
          headC.dx - headR * 0.13, headC.dy + headR * 0.5, headC.dx, headC.dy + headR * 0.3)
      ..quadraticBezierTo(
          headC.dx + headR * 0.13, headC.dy + headR * 0.5, headC.dx + headR * 0.26, headC.dy + headR * 0.3);
    canvas.drawPath(mouth, paint);
    for (final dy in [-0.16, 0.04, 0.24]) {
      final y = headC.dy + headR * dy;
      canvas.drawLine(Offset(headC.dx - headR * 0.62, y), Offset(headC.dx - headR * 1.34, y - headR * 0.1), paint);
      canvas.drawLine(Offset(headC.dx + headR * 0.62, y), Offset(headC.dx + headR * 1.34, y - headR * 0.1), paint);
    }
    final paw = Path()
      ..moveTo(headC.dx - headR * 0.5, h * 0.94)
      ..quadraticBezierTo(headC.dx - headR * 0.25, h * 1.04, headC.dx, h * 0.94);
    canvas.drawPath(paw, paint);
    final paw2 = Path()
      ..moveTo(headC.dx + headR * 0.1, h * 0.96)
      ..quadraticBezierTo(headC.dx + headR * 0.35, h * 1.06, headC.dx + headR * 0.6, h * 0.96);
    canvas.drawPath(paw2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
