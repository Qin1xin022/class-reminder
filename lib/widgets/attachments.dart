import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// 选一个文件 → 复制进 App 私有目录。返回可直接入库（或暂存）的附件。
Future<AttachmentItem?> pickAttachmentFile(BuildContext context, String ownerType) async {
  final state = context.read<AppState>();
  try {
    final f = await FilePicker.pickFile(dialogTitle: '选择要添加的文件');
    if (f == null) return null;
    final path = f.path;
    if (path == null) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个文件读不到本地路径，换一个试试（比如从「文件管理」里选）')),
      );
      return null;
    }
    final item = await state.stageAttachment(ownerType, path, f.name);
    if (item == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件复制失败，可能空间不足')));
    }
    return item;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择文件失败：$e')));
    }
    return null;
  }
}

/// 选一张图片 → 复制进 App 私有目录。
Future<AttachmentItem?> pickAttachmentImage(BuildContext context, String ownerType) async {
  final state = context.read<AppState>();
  try {
    final f = await FilePicker.pickFile(dialogTitle: '选择图片', type: FileType.image);
    if (f == null) return null;
    final path = f.path;
    if (path == null) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这张图读不到本地路径，换一张试试')),
      );
      return null;
    }
    final item = await state.stageAttachment(ownerType, path, f.name.isEmpty ? '图片.jpg' : f.name);
    if (item == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片复制失败，可能空间不足')));
    }
    return item;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择图片失败：$e')));
    }
    return null;
  }
}

Future<void> openAttachment(BuildContext context, AttachmentItem a) async {
  final file = File(a.path);
  if (!await file.exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件已不在手机上，可能被清理了')));
    }
    return;
  }
  final r = await OpenFilex.open(a.path);
  if (r.type != ResultType.done && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('没有能打开 .${a.ext} 的应用，可以先装个 WPS 再试（${r.message}）')),
    );
  }
}

/// 附件区块：显示列表 + 添加按钮
class AttachmentSection extends StatelessWidget {
  const AttachmentSection({
    super.key,
    required this.ownerType,
    this.ownerId,
    required this.pending,
    this.onPendingChanged,
    this.title = '附件',
    this.hint = '支持 Word / PDF / PPT / Excel / 图片 / 压缩包',
  });

  final String ownerType;
  final int? ownerId;
  final List<AttachmentItem> pending;
  final ValueChanged<List<AttachmentItem>>? onPendingChanged;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = state.attachmentsOf(ownerType, ownerId);
    final items = <AttachmentItem>[...saved, ...pending];
    final images = items.where((e) => e.isImage).toList();
    final files = items.where((e) => !e.isImage).toList();

    Future<void> add(bool image) async {
      final item = image ? await pickAttachmentImage(context, ownerType) : await pickAttachmentFile(context, ownerType);
      if (item == null) return;
      if (ownerId == null) {
        onPendingChanged?.call([...pending, item]);
      } else {
        await context.read<AppState>().attachPending(ownerType, ownerId!, [item]);
      }
    }

    Future<void> remove(AttachmentItem item) async {
      if (item.id == null) {
        onPendingChanged?.call(pending.where((e) => e != item).toList());
        try {
          final f = File(item.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        return;
      }
      await context.read<AppState>().deleteAttachment(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$title${items.isEmpty ? '' : '（${items.length}）'}',
              style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => add(true),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: const Text('图片', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            TextButton.icon(
              onPressed: () => add(false),
              icon: const Icon(Icons.attach_file, size: 16),
              label: const Text('文件', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        if (images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final img in images)
                  _ImageThumb(
                    item: img,
                    onTap: () => openAttachment(context, img),
                    onDelete: () => remove(img),
                  ),
              ],
            ),
          ),
        if (files.isEmpty && images.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
            child: Text(hint, style: TextStyle(fontSize: 11, color: context.faint, height: 1.5)),
          )
        else if (files.isNotEmpty)
          Container(
            decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                for (var i = 0; i < files.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 52, color: context.divider),
                  _AttachmentTile(
                    item: files[i],
                    onTap: () => openAttachment(context, files[i]),
                    onDelete: () => remove(files[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 图片缩略图（点开看大图，右上角删除）
class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.item, required this.onTap, required this.onDelete});

  final AttachmentItem item;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onTap,
                child: Image.file(
                  File(item.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF2C313C)
                        : context.divider,
                    child: Icon(Icons.broken_image_outlined, size: 20, color: context.faint),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: const Color(0x8A000000), borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.item, required this.onTap, required this.onDelete});

  final AttachmentItem item;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: item.color.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
              child: Icon(item.icon, size: 18, color: item.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  if (item.sizeText.isNotEmpty)
                    Text(item.sizeText, style: TextStyle(fontSize: 10, color: context.faint)),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, size: 17, color: context.faint),
            ),
          ],
        ),
      ),
    );
  }
}
