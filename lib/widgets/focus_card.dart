import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../screens/focus_screen.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../theme/tokens.dart';

/// 专注计时卡片：选类型 → 点开始 → 点结束保存。
class FocusCard extends StatefulWidget {
  const FocusCard({super.key});

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  Timer? _ticker;
  TaskType _type = TaskType.study;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(bool running) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final running = s.runningFocus;
    _syncTicker(running != null);

    final elapsed = running?.seconds ?? 0;
    final todayMin = s.todayFocusSeconds ~/ 60;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              const Text('专注计时', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                '今日 $todayMin 分钟',
                style: TextStyle(fontSize: 12, color: context.sub),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FocusScreen()),
                ),
                icon: Icon(Icons.chevron_right, size: 20, color: context.faint),
                tooltip: '查看记录',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: TaskType.values.map((t) {
              final selected = (running?.type ?? _type) == t;
              return ChoiceChip(
                label: Text(
                  t.label,
                  style: TextStyle(fontSize: 12, color: selected ? Colors.white : Theme.of(context).brightness == Brightness.dark ? const Color(0xFFA8ADB8) : context.sub),
                ),
                selected: selected,
                selectedColor: t.color,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF111318)
                    : const Color(0xFFF5F6FA),
                showCheckmark: false,
                onSelected: running != null ? null : (_) => setState(() => _type = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fmtClock(elapsed),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: running == null ? context.text : (running.type.color),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      running == null
                          ? '点「开始专注」，结束后自动记一次'
                          : '${hhmmOf(running.startAt)} 开始 · ${running.type.label}',
                      style: TextStyle(fontSize: 11, color: context.faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 104,
                height: 44,
                child: FilledButton(
                  onPressed: () => _toggle(context, running),
                  style: FilledButton.styleFrom(
                    backgroundColor: running == null ? _type.color : const Color(0xFF343A40),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    running == null ? '开始' : '结束',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, FocusSession? running) async {
    final s = context.read<AppState>();
    if (running == null) {
      await s.startFocus(_type);
    } else {
      final mins = running.seconds ~/ 60;
      await s.stopFocus();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(running.seconds < 60
              ? '不足 1 分钟，本次不计入记录'
              : '已记录 ${running.type.label} $mins 分钟'),
        ),
      );
    }
  }
}

String _fmtClock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final sec = seconds % 60;
  return '${two(h)}:${two(m)}:${two(sec)}';
}

String fmtDuration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) return '$m 分钟';
  return '$h 小时 $m 分';
}
