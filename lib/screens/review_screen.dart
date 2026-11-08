import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../theme/tokens.dart';

const List<String> kMoodLabels = ['很糟', '一般', '还行', '不错', '超棒'];

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.day});

  final DateTime day;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final TextEditingController _done;
  late final TextEditingController _blocker;
  late final TextEditingController _tomorrow;
  int _mood = 3;

  String get _key => fmtDate(widget.day);

  @override
  void initState() {
    super.initState();
    final existing = context.read<AppState>().reviewOf(_key);
    _done = TextEditingController(text: existing?.doneText ?? '');
    _blocker = TextEditingController(text: existing?.blockerText ?? '');
    _tomorrow = TextEditingController(text: existing?.tomorrowText ?? '');
    _mood = existing?.mood ?? 3;
  }

  @override
  void dispose() {
    _done.dispose();
    _blocker.dispose();
    _tomorrow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final dayCourses = s.coursesOfDay(widget.day.weekday, week: s.weekOf(widget.day));
    final pending = s.pending.length;
    final history = s.reviews.values.toList()
      ..sort((a, b) => b.dateKey.compareTo(a.dateKey));

    return Scaffold(
      appBar: AppBar(title: Text('复盘 · ${fmtDate(widget.day)}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              _stat('课程', '${dayCourses.length}'),
              const SizedBox(width: 10),
              _stat('未完成', '$pending'),
              const SizedBox(width: 10),
              _stat('心情', kMoodLabels[_mood - 1]),
            ],
          ),
          const SizedBox(height: 18),
          _label('今天完成了什么？'),
          _field(_done, '例如：补完高数第 3 章习题，背了 40 个单词'),
          const SizedBox(height: 14),
          _label('卡在哪里？（时间/理解/情绪）'),
          _field(_blocker, '例如：积分换元总漏系数，30 分钟才做一题'),
          const SizedBox(height: 14),
          _label('明天最重要的一件事'),
          _field(_tomorrow, '只写一件，明天先做它'),
          const SizedBox(height: 16),
          _label('今天的状态'),
          Wrap(
            spacing: 8,
            children: List.generate(5, (i) {
              final v = i + 1;
              final selected = _mood == v;
              return ChoiceChip(
                label: Text(kMoodLabels[i], style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
                selected: selected,
                selectedColor: Theme.of(context).colorScheme.primary,
                backgroundColor: context.card,
                showCheckmark: false,
                onSelected: (_) => setState(() => _mood = v),
              );
            }),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('保存复盘'),
          ),
          if (history.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 26, 2, 8),
              child: Text('以往复盘', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            ...history.take(10).map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text(r.dateKey, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          r.doneText.isEmpty ? '（没写完成情况）' : r.doneText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Text(kMoodLabels[(r.mood - 1).clamp(0, 4)],
                            style: TextStyle(fontSize: 11, color: context.faint)),
                        onTap: () {
                          final d = DateTime.tryParse(r.dateKey);
                          if (d != null) {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ReviewScreen(day: d)),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: context.sub)),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(text, style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600)),
    );
  }

  Widget _field(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      maxLines: 4,
      minLines: 2,
      style: const TextStyle(fontSize: 14, height: 1.6),
      decoration: InputDecoration(hintText: hint),
    );
  }

  Future<void> _save() async {
    await context.read<AppState>().saveReview(
          ReviewItem(
            dateKey: _key,
            doneText: _done.text.trim(),
            blockerText: _blocker.text.trim(),
            tomorrowText: _tomorrow.text.trim(),
            mood: _mood,
            createdAt: DateTime.now(),
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，晚安 🌙')));
    Navigator.of(context).pop();
  }
}
