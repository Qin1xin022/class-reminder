import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import 'notice_edit_screen.dart';
import '../theme/tokens.dart';

class NoticeListScreen extends StatefulWidget {
  const NoticeListScreen({super.key});

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  String _source = '全部';
  bool _onlyUrgent = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.notices.where((n) {
      if (_source != '全部' && n.source != _source) return false;
      if (_onlyUrgent && n.importance < 2) return false;
      return true;
    }).toList();

    // 置顶优先 → 重要程度 → 快截止的在前 → 时间
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (a.importance != b.importance) return b.importance.compareTo(a.importance);
      final ad = a.deadlineAt;
      final bd = b.deadlineAt;
      if (ad != null || bd != null) {
        if (ad == null) return 1;
        if (bd == null) return -1;
        final c = ad.compareTo(bd);
        if (c != 0) return c;
      }
      return b.createdAt.compareTo(a.createdAt);
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('通知'),
            if (s.unreadNoticeCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFD6336C), borderRadius: BorderRadius.circular(9)),
                  child: Text('${s.unreadNoticeCount} 未读',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NoticeEditScreen()),
        ),
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('粘贴通知'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('全部'),
                for (final src in kNoticeSources) _chip(src),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('只看重要/紧急', style: TextStyle(fontSize: 12)),
                selected: _onlyUrgent,
                onSelected: (v) => setState(() => _onlyUrgent = v),
              ),
              const Spacer(),
              Text('共 ${list.length} 条', style: TextStyle(fontSize: 11, color: context.faint)),
            ],
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const EmptyHint(
              text: '把班群、年级群里的通知原文粘进来，自动帮你提炼截止时间、地点、链接',
              icon: Icons.campaign_outlined,
            ),
          ...list.map((n) => _NoticeCard(notice: n)),
        ],
      ),
    );
  }

  Widget _chip(String value) {
    final selected = _source == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(value, style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
        selected: selected,
        selectedColor: Theme.of(context).colorScheme.primary,
        backgroundColor: context.card,
        showCheckmark: false,
        onSelected: (_) => setState(() => _source = value),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final NoticeItem notice;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final imp = importanceFromCode(notice.importance);
    final files = state.attachmentsOf('notice', notice.id);
    final points = notice.keyPointList;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            if (!notice.read) await state.markNoticeRead(notice.id!, true);
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => NoticeEditScreen(notice: notice)),
            );
          },
          onLongPress: () async {
            final action = await showModalBottomSheet<String>(
              context: context,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(notice.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                      title: Text(notice.pinned ? '取消置顶' : '置顶'),
                      onTap: () => Navigator.of(ctx).pop('pin'),
                    ),
                    ListTile(
                      leading: Icon(notice.read ? Icons.mark_email_unread_outlined : Icons.drafts_outlined),
                      title: Text(notice.read ? '标记为未读' : '标记为已读'),
                      onTap: () => Navigator.of(ctx).pop('read'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline, color: Color(0xFFD6336C)),
                      title: const Text('删除'),
                      onTap: () => Navigator.of(ctx).pop('delete'),
                    ),
                  ],
                ),
              ),
            );
            if (action == 'pin') await state.toggleNoticePin(notice);
            if (action == 'read') await state.markNoticeRead(notice.id!, !notice.read);
            if (action == 'delete') await state.deleteNotice(notice.id!);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(notice.source,
                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                    Icon(imp.icon, size: 14, color: imp.color),
                    const SizedBox(width: 2),
                    Text(imp.label, style: TextStyle(fontSize: 10, color: imp.color)),
                    if (notice.pinned) const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.push_pin, size: 13, color: Color(0xFFE8590C)),
                    ),
                    const Spacer(),
                    if (!notice.read)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: Color(0xFFD6336C), shape: BoxShape.circle),
                      ),
                    const SizedBox(width: 6),
                    Text(fmtMd(notice.createdAt), style: TextStyle(fontSize: 10, color: context.faint)),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  notice.title.isEmpty ? '（无标题通知）' : notice.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35),
                ),
                if (notice.deadlineAt != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        notice.isOverdue ? Icons.alarm_off : Icons.alarm,
                        size: 13,
                        color: notice.isOverdue ? const Color(0xFFD6336C) : Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '截止 ${fmtDateTime(notice.deadlineAt)} · ${leftText(notice.deadlineAt!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: notice.isOverdue ? const Color(0xFFD6336C) : context.sub,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        notice.remindList.map(offsetLabel).join('/'),
                        style: TextStyle(fontSize: 10, color: context.faint),
                      ),
                    ],
                  ),
                ],
                if (points.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final p in points.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '· $p',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: context.sub, height: 1.5),
                            ),
                          ),
                        if (points.length > 3)
                          Text('还有 ${points.length - 3} 条重点…',
                              style: TextStyle(fontSize: 10, color: context.faint)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (notice.linkList.isNotEmpty) ...[
                      Icon(Icons.link, size: 13, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 3),
                      Text('${notice.linkList.length} 个链接',
                          style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(width: 10),
                    ],
                    if (files.isNotEmpty) ...[
                      const Icon(Icons.attach_file, size: 13, color: Color(0xFF2B8A3E)),
                      const SizedBox(width: 3),
                      Text('${files.length} 个文件',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF2B8A3E))),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
