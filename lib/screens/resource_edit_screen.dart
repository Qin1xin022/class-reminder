import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/attachments.dart';

/// 收一条资源 / 编辑一条资源
class ResourceEditScreen extends StatefulWidget {
  const ResourceEditScreen({super.key, this.item});

  final ResourceItem? item;

  @override
  State<ResourceEditScreen> createState() => _ResourceEditScreenState();
}

class _ResourceEditScreenState extends State<ResourceEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _subject;
  late final TextEditingController _giver;
  late final TextEditingController _purpose;
  late final TextEditingController _note;
  late final TextEditingController _links;
  late ResourceSource _source;
  late ResourceDomain _domain;
  late ResourceRelation _relation;
  final List<AttachmentItem> _pending = [];

  @override
  void initState() {
    super.initState();
    final r = widget.item;
    _title = TextEditingController(text: r?.title ?? '');
    _subject = TextEditingController(text: r?.subject ?? '');
    _giver = TextEditingController(text: r?.giver ?? '');
    _purpose = TextEditingController(text: r?.purpose ?? '');
    _note = TextEditingController(text: r?.note ?? '');
    _links = TextEditingController(text: r?.links.join('\n'));
    _source = r?.source ?? ResourceSource.other;
    _domain = r?.domain ?? ResourceDomain.study;
    _relation = r?.relation ?? ResourceRelation.other;
  }

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _giver.dispose();
    _purpose.dispose();
    _note.dispose();
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑资源' : '收一条资源'),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(hintText: '这是份什么资源？例如：高数复习资料'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const _Label('① 来源'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in ResourceSource.values)
                ChoiceChip(
                  avatar: Icon(v.icon, size: 15, color: _source == v ? Colors.white : v.color),
                  label: Text(v.label,
                      style: TextStyle(fontSize: 13, color: _source == v ? Colors.white : context.sub)),
                  selected: _source == v,
                  selectedColor: v.color,
                  backgroundColor: context.card,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _source = v),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const _Label('② 方面'),
          Wrap(
            spacing: 8,
            children: [
              for (final v in ResourceDomain.values)
                ChoiceChip(
                  avatar: Icon(v.icon, size: 15, color: _domain == v ? Colors.white : context.sub),
                  label: Text(v.label,
                      style: TextStyle(fontSize: 13, color: _domain == v ? Colors.white : context.sub)),
                  selected: _domain == v,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: context.card,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _domain = v),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const _Label('③ 科目 / 类别（自己填，比如：高数、英语、报销流程）'),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(hintText: '选填'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const _Label('④ 谁给的'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in ResourceRelation.values)
                ChoiceChip(
                  label: Text(v.label,
                      style: TextStyle(fontSize: 13, color: _relation == v ? Colors.white : context.sub)),
                  selected: _relation == v,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: context.card,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _relation = v),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _giver,
            decoration: InputDecoration(
              hintText: _relation == ResourceRelation.other ? '具体是谁？选填' : '具体是谁？比如：张阿姨、李老师',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const _Label('⑤ 用来做什么'),
          TextField(
            controller: _purpose,
            decoration: const InputDecoration(hintText: '选填，比如：期末复习 / 找实习用'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const _Label('备注'),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '想补充点什么都可以'),
          ),
          const SizedBox(height: 16),
          const _Label('相关链接（每行一个，点卡片上的链接可以直接打开）'),
          TextField(
            controller: _links,
            maxLines: 3,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: '例如：\nhttps://pan.baidu.com/s/xxxx\nhttps://github.com/xxx/xxx'),
          ),
          const SizedBox(height: 16),
          AttachmentSection(
            ownerType: 'resource',
            ownerId: widget.item?.id,
            pending: _pending,
            onPendingChanged: (v) => setState(() {
              _pending
                ..clear()
                ..addAll(v);
            }),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(isEdit ? '保存修改' : '收进来'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先写写这是份什么资源吧')));
      return;
    }
    final old = widget.item;
    final item = ResourceItem(
      id: old?.id,
      title: title,
      source: _source,
      domain: _domain,
      subject: _subject.text.trim(),
      giver: _giver.text.trim(),
      relation: _relation,
      purpose: _purpose.text.trim(),
      note: _note.text.trim(),
      links: _links.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      createdAt: old?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final state = context.read<AppState>();
    final id = await state.saveResource(item);
    if (_pending.isNotEmpty) {
      await state.attachPending('resource', id, _pending);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条资源？'),
        content: const Text('附件也会一起删掉，删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().deleteResource(widget.item!.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(text, style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600)),
    );
  }
}
