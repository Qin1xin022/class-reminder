import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import 'pc_sync_screen.dart';
import 'review_hub_screen.dart';
import 'widget_guide_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final start = DateTime.tryParse(s.termStart);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.event_available, color: Theme.of(context).colorScheme.primary),
              title: Text('第 ${s.currentWeek} 周'),
              subtitle: Text('开学第一周周一：${s.termStart}（点这里修改）'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: start ?? DateTime.now(),
                  firstDate: DateTime(DateTime.now().year - 2),
                  lastDate: DateTime(DateTime.now().year + 3),
                );
                if (picked == null) return;
                final monday = picked.subtract(Duration(days: picked.weekday - 1));
                await context.read<AppState>().setTermStart(monday);
              },
            ),
          ),
          const SectionTitle(title: '外观'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('主题色', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  // 每个圆点就是一个可选的主题色，点了立刻全局生效
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      for (final (name, color) in kThemeSeeds)
                        Tooltip(
                          message: name,
                          child: GestureDetector(
                            onTap: () => context.read<AppState>().setThemeSeed(color),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: s.themeSeed == color.value
                                      ? (context.isDark ? Colors.white : context.text)
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: s.themeSeed == color.value
                                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 主题预览：告诉用户"选了之后全 App 都长这样"
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      gradient: context.brandGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          '主题预览',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '首页概览 · 头图 · 按钮 · 进度条 都跟随这个颜色',
                            maxLines: 2,
                            style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 11, height: 1.3),
                          ),
                        ),
                        const Icon(Icons.pets, color: Colors.white70, size: 18),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      s.darkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      color: const Color(0xFFF59F00),
                    ),
                    title: const Text('深色模式'),
                    subtitle: const Text('夜间看屏幕更舒服（实验版，个别页面可能还有亮块）'),
                    value: s.darkMode,
                    onChanged: (v) => context.read<AppState>().setDarkMode(v),
                  ),
                  const Divider(height: 24),
                  const Text('字号', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 0.85, label: Text('小')),
                      ButtonSegment(value: 1.0, label: Text('标准')),
                      ButtonSegment(value: 1.15, label: Text('大')),
                    ],
                    selected: {s.fontScale},
                    onSelectionChanged: (sel) =>
                        context.read<AppState>().setFontScale(sel.first),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle(title: '提醒'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('开启通知权限'),
                  subtitle: const Text('Android 13+ 需要授权；并允许「精确闹钟」'),
                  onTap: () async {
                    await context.read<AppState>().sendTestNotification();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已申请权限并在 5 秒后发一条测试提醒')));
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('重新安排全部提醒'),
                  subtitle: const Text('改完课程/待办后如果没响，点这里重排一次'),
                  onTap: () async {
                    await context.read<AppState>().rescheduleAll();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已重新安排未来 3 周的提醒')));
                  },
                ),
              ],
            ),
          ),
          const SectionTitle(title: '桌面与电脑'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.widgets_outlined, color: Color(0xFF7048E8)),
                  title: const Text('桌面小组件'),
                  subtitle: const Text('课程表 / 待办放桌面：添加步骤、内容预览、立即刷新'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WidgetGuideScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.computer_outlined, color: Color(0xFF2B8A3E)),
                  title: const Text('同步到电脑'),
                  subtitle: const Text('同一 Wi-Fi 下，电脑浏览器查看内容 / 下载备份 / 传回备份'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PcSyncScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle(title: '复盘'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: const Text('总结汇总'),
              subtitle: const Text('作业、工作、自习、比赛、笔记、灵感的总结都汇总到一页，可按分类和时间翻'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReviewHubScreen()),
              ),
            ),
          ),
          const SectionTitle(title: '数据'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.analytics_outlined),
                  title: const Text('内容统计'),
                  subtitle: Text(
                    '课程 ${s.courses.length} 门 · 待办 ${s.tasks.length} 条 · 笔记 ${s.notes.length} 篇 · '
                    '灵感 ${s.ideaCount} 条 · 复盘 ${s.reviews.length} 天',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: const Text('导出备份文件（换手机推荐）'),
                  subtitle: const Text('存成一个 .json 文件发给新手机，课表、开学日期、待办笔记一起带走；'
                      '新手机打开「从备份文件导入」即可'),
                  onTap: () => _exportBackupFile(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore_page_outlined),
                  title: const Text('从备份文件导入（会覆盖现有数据）'),
                  subtitle: const Text('选一台旧手机发来的 .json 备份，课表和开学周次原样恢复，不会错周'),
                  onTap: () => _importBackupFile(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('导出备份到剪贴板'),
                  subtitle: const Text('换手机：导出 → 发到微信文件传输助手 → 新手机粘贴导入；'
                      '想存到电脑就用上面的「同步到电脑」下载 .json'),
                  onTap: () async {
                    final text = await context.read<AppState>().exportBackup();
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已复制 ${text.length} 个字符的备份，去粘贴保存吧')),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('从剪贴板导入（会覆盖现有数据）'),
                  onTap: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text ?? '';
                    if (text.trim().isEmpty) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('剪贴板是空的，先复制备份内容')));
                      return;
                    }
                    if (!context.mounted) return;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('导入备份？'),
                        content: const Text('当前所有课程、待办、笔记、复盘都会被覆盖，建议先导出一次。'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('导入')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    try {
                      await context.read<AppState>().importBackup(text);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('导入完成')));
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('导入失败：$e')));
                    }
                  },
                ),
              ],
            ),
          ),
          const SectionTitle(title: '关于'),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '课表 · 待办  v1.10.2\n'
                'Flutter + SQLite + 本地通知 + 桌面小组件 + 局域网同步\n\n'
                '所有数据只存在你自己的手机上，不上传任何服务器。\n'
                'vivo 手机请把本应用加入「自启动」和「后台高耗电」白名单，否则提醒可能被系统拦截。',
                style: TextStyle(fontSize: 12, color: context.sub, height: 1.7),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '数据备份于 ${fmtDate(DateTime.now())}',
              style: TextStyle(fontSize: 11, color: context.faint),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 备份文件
/// 把整份数据导出成一个 .json 文件（走系统「保存到…」，可存到下载/文件管理）。
Future<void> _exportBackupFile(BuildContext context) async {
  final state = context.read<AppState>();
  try {
    final text = await state.exportBackup();
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = '课表待办备份-${d.year}${two(d.month)}${two(d.day)}.json';
    final uri = await FilePicker.saveFile(
      dialogTitle: '保存备份文件',
      fileName: name,
      bytes: Uint8List.fromList(utf8.encode(text)),
      mimeType: 'application/json',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(uri == null
            ? '已取消保存'
            : '备份已保存：$name\n把这个文件发给新手机，用「从备份文件导入」恢复'),
        duration: const Duration(seconds: 5),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('导出失败：$e')));
  }
}

/// 从 .json 备份文件恢复（会覆盖本机数据）。
Future<void> _importBackupFile(BuildContext context) async {
  PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(dialogTitle: '选择备份文件（.json）');
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('打开文件选择器失败：$e')));
    return;
  }
  if (picked == null) return;

  String text;
  try {
    final p = picked.path;
    text = p != null ? await File(p).readAsString() : await picked.xFile.readAsString();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('读不了这个文件：$e')));
    return;
  }

  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导入这份备份？'),
      content: Text('文件：${picked!.name}\n\n'
          '当前手机上的课程、待办、笔记、复盘都会被这份备份覆盖，'
          '开学第一周周一也会改成备份里的日期（这样周次不会错）。'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('覆盖导入')),
      ],
    ),
  );
  if (ok != true) return;

  try {
    await context.read<AppState>().importBackup(text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('导入完成，课表和记录都回来了')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('导入失败：$e')));
  }
}
