import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import '../widgets/rating.dart';
import 'competition_edit_screen.dart';
import 'idea_edit_screen.dart';
import 'note_edit_screen.dart';
import 'task_detail_screen.dart';
import 'task_edit_screen.dart';
import '../theme/tokens.dart';

/// 一条汇总记录：来自作业/工作/自习/比赛/笔记/灵感
class _Entry {
  _Entry({
    required this.kind,
    required this.title,
    required this.text,
    required this.at,
    this.stars = 0,
    this.score = '',
    this.reviewer = '',
    this.resultRank = '',
    this.task,
    this.comp,
    this.note,
    this.idea,
  });

  final String kind; // homework / work / study / comp / note / idea
  final String title;
  final String text;
  final DateTime at;
  final int stars;
  final String score;
  final String reviewer;
  final String resultRank;
  final TaskItem? task;
  final Competition? comp;
  final NoteItem? note;
  final IdeaItem? idea;
}

class _Meta {
  const _Meta(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

const Map<String, _Meta> _kMeta = {
  'homework': _Meta('作业', Icons.menu_book_outlined, Color(0xFFE8590C)),
  'work': _Meta('工作', Icons.work_outline, Color(0xFF1971C2)),
  'study': _Meta('自习', Icons.self_improvement, Color(0xFF2B8A3E)),
  'comp': _Meta('比赛', Icons.emoji_events_outlined, Color(0xFFC77D00)),
  'note': _Meta('笔记', Icons.notes, Color(0xFF4C6FFF)),
  'idea': _Meta('灵感', Icons.lightbulb_outline, Color(0xFF7048E8)),
};

class ReviewHubScreen extends StatefulWidget {
  const ReviewHubScreen({super.key});

  @override
  State<ReviewHubScreen> createState() => _ReviewHubScreenState();
}

class _ReviewHubScreenState extends State<ReviewHubScreen> {
  String _kind = 'all';
  int _days = 0; // 0 = 全部
  bool _searching = false;
  final TextEditingController _kw = TextEditingController();

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  List<_Entry> _collect(AppState s) {
    final out = <_Entry>[];
    for (final t in s.tasks) {
      if (!t.hasSummary) continue;
      out.add(_Entry(
        kind: t.type.code,
        title: t.title,
        text: t.summary,
        at: t.evaluatedAt ?? t.dueAt ?? t.createdAt,
        score: t.score,
        reviewer: t.reviewer,
        task: t,
      ));
    }
    for (final c in s.competitions) {
      if (c.summary.trim().isEmpty) continue;
      out.add(_Entry(
        kind: 'comp',
        title: c.name,
        text: c.summary,
        at: c.resultAt ?? c.endAt ?? c.startAt ?? c.createdAt,
        resultRank: c.resultRank,
        comp: c,
      ));
    }
    for (final n in s.notes) {
      if (!n.hasReview) continue;
      out.add(_Entry(
        kind: 'note',
        title: n.title,
        text: n.review,
        at: n.updatedAt,
        stars: n.rating,
        note: n,
      ));
    }
    for (final i in s.ideas) {
      if (!i.hasReview) continue;
      out.add(_Entry(
        kind: 'idea',
        title: i.title,
        text: i.review,
        at: i.updatedAt,
        stars: i.rating,
        idea: i,
      ));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final all = _collect(s);
    final kw = _kw.text.trim().toLowerCase();

    final list = all.where((e) {
      if (_kind != 'all' && e.kind != _kind) return false;
      if (_days > 0 && e.at.isBefore(DateTime.now().subtract(Duration(days: _days)))) return false;
      if (kw.isEmpty) return true;
      return e.title.toLowerCase().contains(kw) || e.text.toLowerCase().contains(kw);
    }).toList();

    final rated = all.where((e) => e.stars > 0).toList();
    final avgStar = rated.isEmpty
        ? 0.0
        : rated.map((e) => e.stars).reduce((a, b) => a + b) / rated.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('总结汇总'),
        actions: [
          IconButton(
            tooltip: _searching ? '关闭搜索' : '搜索',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _kw.clear();
            }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _kw,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '搜总结里的关键词，比如「错题」「评委」',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
              ),
            ),
          _StatsCard(all: all, avgStar: avgStar, ratedCount: rated.length, pasts: s.pastCompetitions),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip('all', '全部'),
                for (final k in _kMeta.keys) _chip(k, _kMeta[k]!.label),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _rangeChip(0, '全部时间'),
                _rangeChip(7, '近 7 天'),
                _rangeChip(30, '近 30 天'),
                _rangeChip(90, '近 90 天'),
                _rangeChip(365, '近一年'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: EmptyHint(
                text: all.isEmpty
                    ? '还没有写过总结。\n做完作业、比完赛、读完笔记后回去补一句，就会出现在这里。'
                    : '当前筛选下没有内容，换个分类或时间看看',
                icon: Icons.auto_stories_outlined,
              ),
            )
          else
            ...list.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReviewCard(entry: e, onTap: () => _open(e)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String key, String label) {
    final selected = _kind == key;
    final color = key == 'all' ? Theme.of(context).colorScheme.primary : _kMeta[key]!.color;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub),
        ),
        selected: selected,
        selectedColor: color,
        backgroundColor: context.card,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _kind = key),
      ),
    );
  }

  Widget _rangeChip(int days, String label) {
    final selected = _days == days;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _days = days),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : context.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : context.divider,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: selected ? Theme.of(context).colorScheme.primary : context.sub,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(_Entry e) async {
    Widget page;
    if (e.task != null) {
      page = TaskDetailScreen(taskId: e.task!.id!);
    } else if (e.comp != null) {
      page = CompetitionEditScreen(comp: e.comp);
    } else if (e.note != null) {
      page = NoteEditScreen(note: e.note);
    } else {
      page = IdeaEditScreen(idea: e.idea);
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.all,
    required this.avgStar,
    required this.ratedCount,
    required this.pasts,
  });

  final List<_Entry> all;
  final double avgStar;
  final int ratedCount;
  final List<Competition> pasts;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final e in all) {
      counts[e.kind] = (counts[e.kind] ?? 0) + 1;
    }
    final awards = pasts
        .where((c) => c.resultRank != 'pending' && c.resultRank != 'join' && c.resultRank != 'fail')
        .length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '共 ${all.length} 条总结',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          if (all.isEmpty)
            const Text(
              '作业、工作、自习、比赛、笔记、灵感的总结都会汇总到这里',
              style: TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.6),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: _kMeta.entries
                  .where((kv) => (counts[kv.key] ?? 0) > 0)
                  .map((kv) => Text(
                        '${kv.value.label} ${counts[kv.key]}',
                        style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (ratedCount > 0) ...[
                const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFD43B)),
                const SizedBox(width: 3),
                Text(
                  '平均自评 ${avgStar.toStringAsFixed(1)} 星',
                  style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
              ],
              Text(
                '参加 ${pasts.length} 场 · 获奖 $awards 场',
                style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.entry, required this.onTap});

  final _Entry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = _kMeta[entry.kind]!;
    final e = entry;

    return Material(
      color: context.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: meta.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(meta.icon, size: 12, color: meta.color),
                        const SizedBox(width: 3),
                        Text(
                          meta.label,
                          style: TextStyle(fontSize: 10.5, color: meta.color, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  if (e.kind == 'comp') ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: compResultColor(e.resultRank).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        compResultLabel(e.resultRank),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: compResultColor(e.resultRank),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    fmtDate(e.at),
                    style: TextStyle(fontSize: 10.5, color: context.faint),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                e.title.isEmpty ? '（无标题）' : e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3),
              ),
              const SizedBox(height: 4),
              Text(
                e.text.isEmpty ? '只打了分，还没写感受' : e.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: e.text.isEmpty ? context.faint : Colors.black.withValues(alpha: 0.62),
                ),
              ),
              if (e.stars > 0 || e.score.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (e.stars > 0) StarRow(value: e.stars),
                    if (e.stars > 0 && e.score.isNotEmpty) const SizedBox(width: 10),
                    if (e.score.isNotEmpty) ...[
                      const Icon(Icons.grade_outlined, size: 13, color: Color(0xFFC77D00)),
                      const SizedBox(width: 3),
                      Text(
                        e.reviewer.isEmpty ? e.score : '${e.score} · ${e.reviewer}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFC77D00),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
