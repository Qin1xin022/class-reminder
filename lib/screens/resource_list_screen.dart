import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import 'resource_edit_screen.dart';

/// 资源库：来源 → 方面 → 科目 逐级筛选，条目记录谁给的、用来做什么。
class ResourceListScreen extends StatefulWidget {
  const ResourceListScreen({super.key});

  @override
  State<ResourceListScreen> createState() => _ResourceListScreenState();
}

class _ResourceListScreenState extends State<ResourceListScreen> {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text('资源库（${s.resources.length}）')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ResourceEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('收进来'),
      ),
      body: const ResourcePane(),
    );
  }
}

/// 资源库主体（「记录」页的第三个标签也用它）
class ResourcePane extends StatefulWidget {
  const ResourcePane({super.key});

  @override
  State<ResourcePane> createState() => _ResourcePaneState();
}

class _ResourcePaneState extends State<ResourcePane> {
  ResourceSource? _source;
  ResourceDomain? _domain;
  String? _subject;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final subjects = s.resourceSubjects(source: _source, domain: _domain);
    // 手选的科目不在当前可选集合里时自动清掉，避免筛出空列表还不知道为啥
    if (_subject != null && !subjects.contains(_subject)) {
      _subject = null;
    }
    final list = s.resourcesFiltered(
      source: _source,
      domain: _domain,
      subject: _subject,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        Row(
          children: [
            Expanded(child: _levelTitle('① 来源', s.resources.length)),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ResourceEditScreen()),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('收进来', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _sourceChip(null, '全部'),
                for (final v in ResourceSource.values) _sourceChip(v, v.label),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _levelTitle('② 方面', null),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _domainChip(null, '全部'),
                for (final v in ResourceDomain.values) _domainChip(v, v.label),
              ],
            ),
          ),
          if (subjects.isNotEmpty) ...[
            const SizedBox(height: 10),
            _levelTitle('③ 科目 / 类别', null),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _subjectChip(null, '全部'),
                  for (final sub in subjects) _subjectChip(sub, sub),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyHint(text: '这一类下还没有资源，点右下角「收进来」记一条'),
            ),
          for (final r in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ResourceCard(item: r),
            ),
        ],
      );
  }

  Widget _levelTitle(String text, int? count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        count == null ? text : '$text（共 $count 条）',
        style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _sourceChip(ResourceSource? v, String label) {
    final selected = _source == v;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: v == null ? null : Icon(v.icon, size: 15, color: selected ? Colors.white : v.color),
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
        selected: selected,
        selectedColor: v?.color ?? Theme.of(context).colorScheme.primary,
        backgroundColor: context.card,
        showCheckmark: false,
        onSelected: (_) => setState(() {
          _source = v;
          _subject = null; // 来源变了，科目级联清空
        }),
      ),
    );
  }

  Widget _domainChip(ResourceDomain? v, String label) {
    final selected = _domain == v;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: v == null ? null : Icon(v.icon, size: 15, color: selected ? Colors.white : context.sub),
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
        selected: selected,
        selectedColor: Theme.of(context).colorScheme.primary,
        backgroundColor: context.card,
        showCheckmark: false,
        onSelected: (_) => setState(() {
          _domain = v;
          _subject = null;
        }),
      ),
    );
  }

  Widget _subjectChip(String? v, String label) {
    final selected = _subject == v;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : context.sub)),
        selected: selected,
        selectedColor: Theme.of(context).colorScheme.primary,
        backgroundColor: context.card,
        showCheckmark: false,
        onSelected: (_) => setState(() => _subject = v),
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.item});

  final ResourceItem item;

  /// 展示用的短标签：去掉协议头，只留主体
  static String _linkLabel(String link) {
    var s = link.trim();
    s = s.replaceFirst(RegExp(r'^https?://'), '');
    if (s.length > 60) s = '${s.substring(0, 60)}…';
    return s;
  }

  static Future<void> _openLink(BuildContext context, String link) async {
    var s = link.trim();
    if (s.isEmpty) return;
    if (!s.startsWith(RegExp(r'https?://'))) s = 'https://$s';
    final uri = Uri.tryParse(s);
    if (uri == null) return;
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打不开这个链接：$s')));
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final atts = state.attachmentsOf('resource', item.id);
    final photos = atts.where((e) => e.isImage).toList();

    return Material(
      color: context.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ResourceEditScreen(item: item)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: item.source.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item.source.icon, size: 12, color: item.source.color),
                        const SizedBox(width: 3),
                        Text(item.source.label,
                            style: TextStyle(fontSize: 10, color: item.source.color, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(item.domain.label,
                        style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (item.subject.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(item.subject, style: TextStyle(fontSize: 11, color: context.sub)),
                  ],
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 18, color: context.faint),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (item.giverText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 13, color: context.faint),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(item.giverText,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: context.sub)),
                    ),
                  ],
                ),
              ],
              if (item.purpose.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag_outlined, size: 13, color: context.faint),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text('用来：${item.purpose}',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: context.sub)),
                    ),
                  ],
                ),
              ],
              if (item.links.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final link in item.links)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _openLink(context, link),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.link, size: 14, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                _linkLabel(link),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                                ),
                              ),
                            ),
                            Icon(Icons.open_in_new, size: 13, color: context.faint),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      for (final p in photos.take(4))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(p.path),
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 52,
                                height: 52,
                                color: context.divider,
                                child: Icon(Icons.broken_image_outlined, size: 16, color: context.faint),
                              ),
                            ),
                          ),
                        ),
                      if (photos.length > 4)
                        Text('等 ${photos.length} 张', style: TextStyle(fontSize: 11, color: context.faint)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '收录于 ${fmtDate(item.createdAt)}${atts.length > 0 ? ' · ${atts.length} 个附件' : ''}',
                style: TextStyle(fontSize: 10.5, color: context.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
