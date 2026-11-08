import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/tokens.dart';

/// 链接工具的公共实现：各板块（课程 / 作业 / 笔记 / 灵感 / 资源）都用它，
/// 保证「存进去的格式一致、点开的体验一致」。
///
/// 数据库里统一存换行分隔的字符串，这里负责和 List 互转。

List<String> parseLinks(String raw) =>
    raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

String joinLinks(Iterable<String> links) => links.map((e) => e.trim()).where((e) => e.isNotEmpty).join('\n');

/// 展示用短标签：去掉协议头，太长截断
String linkLabel(String link) {
  var s = link.trim();
  s = s.replaceFirst(RegExp(r'^https?://'), '');
  if (s.length > 60) s = '${s.substring(0, 60)}…';
  return s;
}

/// 用系统浏览器（或对应 App）打开链接，没写协议头自动补 https
Future<void> openLink(BuildContext context, String link) async {
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

/// 编辑页里的「链接」输入框：一行一个，空行自动忽略
class LinksField extends StatelessWidget {
  const LinksField({
    super.key,
    required this.controller,
    this.label = '相关链接（每行一个，点开直接跳转）',
    this.hint = '例如：\nhttps://www.bilibili.com/video/xxx\nhttps://pan.baidu.com/s/xxxx',
    this.minLines = 2,
    this.maxLines = 4,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(label,
              style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600)),
        ),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

/// 只读展示的链接列表：每条一行，点击用浏览器打开
class LinkList extends StatelessWidget {
  const LinkList({super.key, required this.links, this.dense = false});

  final List<String> links;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final link in links)
          Padding(
            padding: EdgeInsets.only(bottom: dense ? 3 : 5),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => openLink(context, link),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 4 : 6),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link, size: dense ? 12 : 14, color: primary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        linkLabel(link),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? 11 : 12,
                          color: primary,
                          decoration: TextDecoration.underline,
                          decorationColor: primary.withOpacity(0.4),
                        ),
                      ),
                    ),
                    Icon(Icons.open_in_new, size: dense ? 11 : 13, color: context.faint),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
