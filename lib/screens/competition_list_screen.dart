import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import 'competition_edit_screen.dart';
import '../theme/tokens.dart';

class CompetitionListScreen extends StatefulWidget {
  const CompetitionListScreen({super.key});

  @override
  State<CompetitionListScreen> createState() => _CompetitionListScreenState();
}

class _CompetitionListScreenState extends State<CompetitionListScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    final list = s.competitions.where((c) {
      switch (_filter) {
        case 'todo':
          return !c.isPast && !c.running;
        case 'doing':
          return !c.isPast && c.running;
        case 'past':
          return c.isPast;
        case 'award':
          return c.awarded;
        default:
          return true;
      }
    }).toList();

    list.sort((a, b) {
      if (a.isPast || b.isPast) {
        final ad = (a.resultAt ?? a.endAt ?? a.startAt)?.millisecondsSinceEpoch ?? 0;
        final bd = (b.resultAt ?? b.endAt ?? b.startAt)?.millisecondsSinceEpoch ?? 0;
        return bd.compareTo(ad);
      }
      final ad = (a.startAt ?? a.signupDeadline)?.millisecondsSinceEpoch ?? (1 << 62);
      final bd = (b.startAt ?? b.signupDeadline)?.millisecondsSinceEpoch ?? (1 << 62);
      return ad.compareTo(bd);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('比赛'),
        actions: [
          IconButton(
            tooltip: '补录参加过的比赛',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CompetitionEditScreen(startAsPast: true)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CompetitionEditScreen()),
        ),
        icon: const Icon(Icons.emoji_events_outlined),
        label: const Text('新建比赛'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('all', '全部'),
                _chip('todo', '未开始'),
                _chip('doing', '进行中'),
                _chip('past', '参加过的'),
                _chip('award', '获奖'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (s.pastCompCount > 0) ...[
            _StatsCard(state: s),
            const SizedBox(height: 10),
          ],
          if (list.isEmpty) ...[
            EmptyHint(
              text: _filter == 'past' || _filter == 'award'
                  ? '还没有参加过的比赛。点右上角「时钟」图标，可以把往年参加过的比赛和结果补录进来'
                  : '把要参加的比赛记进来：报名截止、初赛/复赛时间、准备事项都会提醒你',
              icon: Icons.emoji_events_outlined,
            ),
            const SizedBox(height: 6),
            if (s.upcomingCompetitions.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('提示：点右下角新建，可以设多个赛段（初赛 / 复赛 / 决赛）',
                    style: TextStyle(fontSize: 11, color: context.faint)),
              ),
          ] else
            ...list.map((c) => _CompCard(comp: c)),
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

/// 参赛战绩：参加 N 场 · 获奖 M 场 + 各奖项条数
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final stats = state.compResultStats;
    final order = ['first', 'second', 'third', 'honor', 'finalist'];
    final shown = order.where((k) => (stats[k] ?? 0) > 0).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.military_tech_outlined, size: 17, color: Color(0xFFC77D00)),
              const SizedBox(width: 6),
              Text(
                '参赛战绩',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '参加 ${state.pastCompCount} 场 · 获奖 ${state.awardedCount} 场',
                style: TextStyle(fontSize: 11, color: context.sub),
              ),
            ],
          ),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in shown)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: compResultColor(k).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${compResultLabel(k)} ${stats[k]}',
                      style: TextStyle(fontSize: 10.5, color: compResultColor(k), fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CompCard extends StatelessWidget {
  const _CompCard({required this.comp});

  final Competition comp;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final prep = state.prepTasksOf(comp.id ?? -1);
    final done = prep.where((t) => t.done).length;
    final imp = importanceFromCode(comp.importance);
    final anchor = comp.startAt ?? comp.signupDeadline;
    final rc = compResultColor(comp.resultRank);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CompetitionEditScreen(comp: comp)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _tag(comp.statusLabel, comp.statusColor),
                    const SizedBox(width: 6),
                    _tag(comp.stage, Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(comp.level, style: TextStyle(fontSize: 10, color: context.faint)),
                    const Spacer(),
                    if (comp.resultRank != 'pending')
                      _tag(comp.resultLabel, rc, icon: compResultIcon(comp.resultRank))
                    else
                      Icon(imp.icon, size: 15, color: imp.color),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  comp.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: comp.isPast ? context.sub : context.text,
                  ),
                ),
                const SizedBox(height: 6),
                if (comp.signupDeadline != null && !comp.isPast)
                  _line(context, Icons.how_to_reg_outlined, '报名截止 ${fmtDateTime(comp.signupDeadline)}',
                      warn: comp.signupDeadline!.isAfter(DateTime.now())),
                if (comp.startAt != null) _line(context, Icons.play_circle_outline, '开始 ${fmtDateTime(comp.startAt)}'),
                if (comp.endAt != null) _line(context, Icons.flag_outlined, '结束 ${fmtDateTime(comp.endAt)}'),
                if (comp.location.isNotEmpty) _line(context, Icons.place_outlined, comp.location),
                if (comp.resultNote.isNotEmpty)
                  _line(context, Icons.workspace_premium_outlined, comp.resultNote,
                      color: rc, iconColor: rc),
                if (comp.resultAt != null)
                  _line(context, Icons.event_available_outlined, '出结果 ${fmtDate(comp.resultAt!)}'),
                if (comp.summary.isNotEmpty)
                  _line(context, Icons.sticky_note_2_outlined, comp.summary, color: context.sub),
                if (comp.resultMissing)
                  _line(context, Icons.edit_note, '还没填结果，点进去补一下', warn: true),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.checklist, size: 13, color: context.faint),
                    const SizedBox(width: 4),
                    Text('准备 ${done}/${prep.length}', style: TextStyle(fontSize: 11, color: context.sub)),
                    const Spacer(),
                    if (anchor != null && !comp.isPast)
                      Text(
                        leftText(anchor),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF2B8A3E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text, {bool warn = false, Color? color, Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: iconColor ?? (warn ? const Color(0xFFE8590C) : context.faint)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: color ?? (warn ? const Color(0xFFE8590C) : context.sub),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
