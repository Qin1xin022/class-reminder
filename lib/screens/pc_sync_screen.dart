import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/lan_sync.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../theme/tokens.dart';

/// 同步到电脑：手机开一个局域网网页，电脑浏览器访问
class PcSyncScreen extends StatefulWidget {
  const PcSyncScreen({super.key});

  @override
  State<PcSyncScreen> createState() => _PcSyncScreenState();
}

class _PcSyncScreenState extends State<PcSyncScreen> {
  bool _starting = false;
  bool _requireCode = true;
  String? _error;

  @override
  void dispose() {
    // 离开页面就关掉服务，避免一直开着
    LanSyncServer.I.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = LanSyncServer.I;
    final running = server.running;

    return Scaffold(
      appBar: AppBar(title: const Text('同步到电脑')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2B8A3E).withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              '不用装任何电脑软件，也不用注册账号：手机上点「开始」，电脑浏览器输入一个地址，'
              '就能看课程、待办、比赛、灵感、笔记、总结，还能导出 CSV / 下载整份备份，'
              '或者把电脑上的备份传回手机。\n'
              '默认要输 4 位访问码，同一个 Wi-Fi 下的其他人没码打不开；数据只在局域网内传输，不经过任何服务器。',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF23543A), height: 1.7),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: running ? const Color(0xFF2B8A3E) : context.faint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        running ? '正在共享（保持这个页面开着）' : '未开始',
                        style: TextStyle(fontSize: 12, color: context.sub, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (running) ...[
                    SelectableText(
                      server.url,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1971C2),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '在电脑浏览器地址栏里输入上面这行（要带 http://），回车后输入下面的访问码。',
                      style: TextStyle(fontSize: 11.5, color: context.sub, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            server.needsCode ? Icons.lock_outline : Icons.lock_open,
                            size: 17,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  server.needsCode ? '访问码（电脑上要输这 4 位）' : '访问码已关闭（同 Wi-Fi 的人都能打开）',
                                  style: TextStyle(fontSize: 10.5, color: context.sub),
                                ),
                                if (server.needsCode)
                                  SelectableText(
                                    server.accessCode,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 6,
                                      color: Color(0xFF1971C2),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (server.needsCode)
                            TextButton(
                              onPressed: () {
                                LanSyncServer.I.rotateCode();
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已换新访问码，电脑需要重新输入'), duration: Duration(seconds: 2)),
                                );
                              },
                              child: const Text('换一个', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    if (server.otherIps.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '打不开就试试：${server.otherIps.map((e) => 'http://$e:${server.port}').join(' 或 ')}',
                          style: TextStyle(fontSize: 11, color: context.faint, height: 1.6),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: server.url));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('地址已复制，去电脑上粘贴'), duration: Duration(seconds: 2)),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('复制地址'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await LanSyncServer.I.stop();
                              setState(() {});
                            },
                            icon: const Icon(Icons.stop_circle_outlined, size: 16),
                            label: const Text('停止共享'),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: _starting ? null : _start,
                      icon: _starting
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(_starting ? '正在启动…' : '开始共享（把手机变成网页）'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 16, color: context.sub),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('需要访问码才能打开', style: TextStyle(fontSize: 12.5)),
                            Text(
                              '关掉后同一个 Wi-Fi 里的人都能直接看；宿舍/教室建议保持开启',
                              style: TextStyle(fontSize: 10.5, color: context.faint, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _requireCode,
                        onChanged: (v) {
                          setState(() => _requireCode = v);
                          if (running) LanSyncServer.I.setRequireCode(v);
                        },
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFD6336C), height: 1.6),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SectionTitle(title: '操作步骤'),
          const Card(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Step('1', '手机和电脑连同一个 Wi-Fi；没有 Wi-Fi 就用手机开热点，让电脑连手机热点。'),
                  _Step('2', '在这页点「开始共享」，记下显示的 http:// 地址。'),
                  _Step('3', '电脑打开 Chrome / Edge，输入这个地址回车，再输入手机上的 4 位访问码。'),
                  _Step('4', '网页里可以按板块看内容、点顶部按钮导出 CSV、或下载整份备份；「打印 / 存 PDF」可以把整页存成 PDF。'),
                  _Step('5', '要用完时点「停止共享」，或者直接退出这个页面。'),
                ],
              ),
            ),
          ),
          const SectionTitle(title: '常见问题'),
          const _Faq(
            q: '电脑上打不开这个地址',
            a: '① 确认在同一个 Wi-Fi（校园网常常把设备隔离，打不开就换手机热点）；'
                '② 确认 APP 这页还开着、显示「正在共享」；'
                '③ 电脑上关掉代理/VPN 再试；④ 学校 Wi-Fi 屏蔽设备互访时，用手机热点最稳。',
          ),
          const _Faq(
            q: '电脑上提示要输访问码 / 输错了',
            a: '访问码显示在手机这一页（4 位数字），每次点「开始共享」都会重新生成；'
                '输错三次刷新页面重来即可。点「换一个」会立刻作废旧的码。'
                '觉得麻烦可以把「需要访问码才能打开」关掉——只在你自己家的 Wi-Fi 下建议这样做。',
          ),
          const _Faq(
            q: '导出的 CSV 打开是乱码',
            a: '文件自带 UTF-8 BOM，用 Excel 直接双击打开就是正常中文；'
                '如果还是乱码，用「数据 → 自文本导入」并选 UTF-8。也可以只把 CSV 拖进 WPS / Numbers。',
          ),
          const _Faq(
            q: '手机上提示「没找到局域网地址」',
            a: '先打开 Wi-Fi 或手机热点，再点一次开始。飞行模式下是拿不到地址的。',
          ),
          const _Faq(
            q: '会不会把数据传到网上',
            a: '不会。网页由你手机自己提供，只在你当前的 Wi-Fi 内可访问，关掉共享就消失。'
                '唯一的风险是同一个 Wi-Fi 下别人也知道地址，所以在宿舍/教室用完记得点停止。',
          ),
          const _Faq(
            q: '下载到电脑的备份怎么用',
            a: '换手机或重装时：在电脑上打开备份文件 → 全选复制 → 发到新手机 → '
                '在 App 的「我的 → 从剪贴板导入」粘贴即可。也可以在电脑网页里直接上传 .json 恢复。',
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await LanSyncServer.I.start(context.read<AppState>(), requireCode: _requireCode);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}

class _Step extends StatelessWidget {
  const _Step(this.no, this.text);

  final String no;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF2B8A3E).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              no,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2B8A3E)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.65, color: context.text)),
          ),
        ],
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.q, required this.a});

  final String q;
  final String a;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.help_outline, size: 15, color: Color(0xFF2B8A3E)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(q, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(a, style: TextStyle(fontSize: 11.5, color: context.sub, height: 1.65)),
          ],
        ),
      ),
    );
  }
}
