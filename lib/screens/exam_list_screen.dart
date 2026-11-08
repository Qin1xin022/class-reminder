import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import '../widgets/links.dart';
import 'exam_edit_screen.dart';

/// 考试板块：考试安排 + 课程成绩/绩点
class ExamListScreen extends StatelessWidget {
  const ExamListScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab == 1 ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('考试 · 成绩'),
          bottom: const TabBar(
            labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            unselectedLabelStyle: TextStyle(fontSize: 14),
            tabs: [Tab(text: '考试安排'), Tab(text: '成绩绩点')],
          ),
        ),
        body: const TabBarView(children: [_ExamPane(), _GradePane()]),
      ),
    );
  }
}

class _ExamPane extends StatelessWidget {
  const _ExamPane();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final upcoming = s.upcomingExams;
    final past = s.exams.where((e) => e.isOver).toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (upcoming.isEmpty && past.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: EmptyHint(
                  text: '还没有考试安排，点右下角添加一场\n（会按设置提前提醒你）',
                  icon: Icons.event_available_outlined,
                ),
              ),
            if (upcoming.isNotEmpty) ...[
              _sectionTitle('接下来（${upcoming.length} 场）'),
              for (final e in upcoming)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ExamCard(exam: e),
                ),
            ],
            if (past.isNotEmpty) ...[
              _sectionTitle('已结束（${past.length} 场）'),
              for (final e in past)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ExamCard(exam: e, over: true),
                ),
            ],
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExamEditScreen()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('添加考试'),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Builder(builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 0, 8),
        child: Text(text, style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600)),
      );
    });
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, this.over = false});

  final Exam exam;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final now = DateTime.now();
    String countdown;
    Color cdColor;
    if (over) {
      countdown = '已结束';
      cdColor = context.faint;
    } else if (now.isBefore(exam.startAt)) {
      final diff = exam.startAt.difference(now);
      countdown = diff.inDays >= 1
          ? '还有 ${diff.inDays} 天'
          : diff.inHours >= 1
              ? '还有 ${diff.inHours} 小时'
              : '马上开考';
      cdColor = diff.inDays >= 1 ? const Color(0xFF2B8A3E) : const Color(0xFFD6336C);
    } else {
      countdown = '进行中';
      cdColor = const Color(0xFFD6336C);
    }

    return Material(
      color: context.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExamEditScreen(exam: exam)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      exam.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: over ? context.faint : context.text,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cdColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(countdown,
                        style: TextStyle(fontSize: 11, color: cdColor, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              if (exam.courseName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('课程：${exam.courseName}', style: TextStyle(fontSize: 12, color: context.sub)),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.schedule, size: 13, color: context.faint),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${fmtDateTime(exam.startAt)} ${friendlyDay(exam.startAt)}'
                      '${exam.endAt != null ? ' — ${hhmmOf(exam.endAt!)}' : ''}',
                      style: TextStyle(fontSize: 12, color: context.sub),
                    ),
                  ),
                ],
              ),
              if (exam.location.isNotEmpty || exam.seat.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined, size: 13, color: context.faint),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            if (exam.location.isNotEmpty) exam.location,
                            if (exam.seat.isNotEmpty) '座位 ${exam.seat}',
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: context.sub),
                        ),
                      ),
                    ],
                  ),
                ),
              if (exam.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    exam.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.sub, height: 1.5),
                  ),
                ),
              if (exam.linkList.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinkList(links: exam.linkList.take(2).toList(), dense: true),
                ),
              if (!over)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active_outlined, size: 12, color: primary),
                      const SizedBox(width: 4),
                      Text(
                        '提醒：${exam.remindList.map(offsetLabel).join(' / ')}',
                        style: TextStyle(fontSize: 11, color: primary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradePane extends StatelessWidget {
  const _GradePane();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = s.gpaStats;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: context.brandGradient,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              _gpaStat('平均绩点', st.gpa == null ? '—' : st.gpa!.toStringAsFixed(2)),
              _gpaStat('加权平均分', st.avgScore == null ? '—' : st.avgScore!.toStringAsFixed(1)),
              _gpaStat('已修学分', st.credits == 0 ? '—' : st.credits.toStringAsFixed(1)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 0, 8),
          child: Row(
            children: [
              Text('课程成绩（${s.grades.length} 门）',
                  style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _editGrade(context, null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加成绩', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        if (s.grades.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 30),
            child: EmptyHint(text: '出分后把成绩记在这里，绩点自动算', icon: Icons.school_outlined),
          ),
        for (final g in s.grades)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: context.card,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _editGrade(context, g),
                onLongPress: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('删除这条成绩？'),
                      content: Text(g.courseName),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
                      ],
                    ),
                  );
                  if (ok == true && g.id != null) {
                    // ignore: use_build_context_synchronously
                    await context.read<AppState>().deleteGrade(g.id!);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.courseName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(
                              '${g.credit.toStringAsFixed(1)} 学分'
                              '${g.score != null ? ' · ${_scoreText(g.score!)}分' : ''}'
                              '${g.note.isNotEmpty ? ' · ${g.note}' : ''}',
                              style: TextStyle(fontSize: 11.5, color: context.sub),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            g.gpaValue == null ? '—' : g.gpaValue!.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: (g.gpaValue ?? 0) >= 3.5
                                  ? const Color(0xFF2B8A3E)
                                  : (g.gpaValue ?? 0) >= 2.0
                                      ? Theme.of(context).colorScheme.primary
                                      : const Color(0xFFD6336C),
                            ),
                          ),
                          Text(g.gpaIsAuto ? '按分数换算' : '手动填写',
                              style: TextStyle(fontSize: 10, color: context.faint)),
                        ],
                      ),
                      Icon(Icons.chevron_right, size: 18, color: context.faint),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _scoreText(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Widget _gpaStat(String label, String value) {
    return Builder(builder: (context) {
      return Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85))),
          ],
        ),
      );
    });
  }

  Future<void> _editGrade(BuildContext context, Grade? g) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _GradeEditScreen(grade: g)),
    );
  }
}

class _GradeEditScreen extends StatefulWidget {
  const _GradeEditScreen({this.grade});

  final Grade? grade;

  @override
  State<_GradeEditScreen> createState() => _GradeEditScreenState();
}

class _GradeEditScreenState extends State<_GradeEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _credit;
  late final TextEditingController _score;
  late final TextEditingController _gpa;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final g = widget.grade;
    _name = TextEditingController(text: g?.courseName ?? '');
    _credit = TextEditingController(text: g == null ? '' : g.credit.toStringAsFixed(1));
    _score = TextEditingController(text: g?.score == null ? '' : _num(g!.score!));
    _gpa = TextEditingController(text: g?.gpa == null ? '' : _num(g!.gpa!));
    _note = TextEditingController(text: g?.note ?? '');
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  void dispose() {
    _name.dispose();
    _credit.dispose();
    _score.dispose();
    _gpa.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.grade != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑成绩' : '添加课程成绩'),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除这条成绩？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
                    ],
                  ),
                );
                if (ok == true) {
                  await context.read<AppState>().deleteGrade(widget.grade!.id!);
                  if (!mounted) return;
                  Navigator.of(context).pop();
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: '课程名，比如：大学英语(1)'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _credit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '学分', hintText: '如 3'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _score,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '成绩（百分制）', hintText: '如 92'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _gpa,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '绩点（选填）', hintText: '自动算'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('绩点留空时按常见 4.0 制自动换算：90+→4.0，85+→3.7，82+→3.3，78+→3.0，75+→2.7，72+→2.3，68+→2.0，64+→1.5，60+→1.0，不及格→0',
              style: TextStyle(fontSize: 11, color: context.faint, height: 1.5)),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            decoration: const InputDecoration(hintText: '备注（选填），比如：期末 60% + 平时 40%'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(isEdit ? '保存修改' : '添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先填课程名')));
      return;
    }
    final old = widget.grade;
    await context.read<AppState>().saveGrade(Grade(
          id: old?.id,
          courseId: old?.courseId,
          courseName: name,
          credit: double.tryParse(_credit.text.trim()) ?? 0,
          score: double.tryParse(_score.text.trim()),
          gpa: double.tryParse(_gpa.text.trim()),
          note: _note.text.trim(),
          createdAt: old?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        ));
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
