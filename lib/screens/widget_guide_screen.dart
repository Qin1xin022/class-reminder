import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';
import '../theme/tokens.dart';

/// 桌面小组件：怎么添加 + 内容预览 + 手动刷新 + 常见问题
class WidgetGuideScreen extends StatefulWidget {
  const WidgetGuideScreen({super.key});

  @override
  State<WidgetGuideScreen> createState() => _WidgetGuideScreenState();
}

class _WidgetGuideScreenState extends State<WidgetGuideScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // 进页面先刷新一次，保证预览和桌面一致
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().refreshWidgets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = s.widgetTexts;

    return Scaffold(
      appBar: AppBar(title: const Text('桌面小组件')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              '现在有 6 个桌面小组件可以挑：课程表、待办提醒、今日概览、比赛提醒、灵感记录、专注统计。\n'
              '每个都会自己算状态：正在上哪节课、还剩多少分钟、下一节还有多久，不打开 App 也会跟着变。\n'
              '点哪个小组件就直接进哪个板块（课表 / 任务 / 记录 / 比赛 / 今日）。',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF2C3E66), height: 1.7),
            ),
          ),
          const SectionTitle(title: '怎么加到桌面（vivo / OriginOS）'),
          const _Steps(),
          const SizedBox(height: 6),
          const SectionTitle(title: '现在桌面上会显示成这样'),
          for (final w in _widgets) ...[
            _WidgetBlock(
              name: w.name,
              icon: w.icon,
              hint: w.hint,
              title: t[w.titleKey] ?? '',
              body: t[w.bodyKey] ?? '',
              footer: t['widget_footer'] ?? '',
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: Text(_refreshing ? '正在刷新…' : '立即刷新小组件'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 8),
          Text(
            '如果桌面上的小组件没跟着变，点上面这个按钮；还是不动就重启一次手机。',
            style: TextStyle(fontSize: 11, color: context.faint, height: 1.6),
          ),
          const SectionTitle(title: '常见问题'),
          const _Faq(
            q: '在小组件列表里找不到「课表待办」',
            a: '1）确认是真的安装成功了（不是只编译没装）；2）长按桌面 → 添加 → 搜「课表」；'
                '3）部分系统要重启手机后才会刷新小组件列表；4）还是不行就把 App 卸载重装一次。',
          ),
          const _Faq(
            q: '小组件显示的是昨天的课 / 旧待办',
            a: '小组件每次显示时会自己按当前时间重算（比如「正在上 / 还剩 23 分钟」），但它读的是 App 最后一次同步的课表，'
                '所以**课表本身变了**（改课、加作业）还是要打开一次 App。'
                '系统每 30 分钟会让小组件重画一次，App 在前台时每分钟刷新一次。'
                '如果连日期都不对，说明系统把 App 彻底冻结了：去 vivo 设置里给本应用开「自启动」和「后台高耗电」白名单。',
          ),
          const _Faq(
            q: '点小组件没反应 / 没有跳到对应板块',
            a: '点一下应该会直接打开 App 并跳到对应板块（课程表→课表、待办→任务、灵感→记录、比赛→比赛）。'
                '如果只是打开首页，说明这个小组件是旧版留下的：删掉重新拖一个到桌面即可。'
                '完全没反应就把小组件删掉重加一次。',
          ),
          const _Faq(
            q: '能不能同时放好几个小组件？',
            a: '可以。长按桌面 → 添加 → 选不同的板块拖到桌面就行：比如上面放「今日概览」，下面并排「课程表」和「待办提醒」，'
                '右边再放「比赛提醒」。同一种也能重复添加（比如把课表放两页）。',
          ),
          const _Faq(
            q: '想换板块 / 换大小',
            a: '长按桌面上的小组件，会出现「移除」「编辑」；删掉后重新从列表里拖一个想要的就换了。'
                '拖边缘的圆点可以拉宽拉长，内容多的板块（课程表、待办）拉大之后能显示更多行。',
          ),
          const _Faq(
            q: '为什么倒计时是 30 分钟一跳',
            a: 'Android 规定桌面小组件最快 30 分钟才能被系统刷新一次，所以停在桌面不动时，'
                '「还剩多少分钟」最多会有半小时误差；一打开 App（或从后台切回来）就会立刻重算成准确值。'
                '要不要精确到分钟，取决于你更在意省电还是精确——现在这样是省电优先。',
          ),
          const _Faq(
            q: '提醒不响，但小组件正常',
            a: '这是两件事：小组件只负责显示，响铃要靠通知权限。去「我的 → 开启通知权限」，'
                '并在 vivo 设置里允许「自启动」「后台高耗电」，再把「精确闹钟」打开。',
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await context.read<AppState>().refreshWidgets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已把最新内容推给桌面小组件'), duration: Duration(seconds: 2)),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      '回到手机桌面，长按空白处（别按到图标上）',
      '点底部「添加」或「桌面设置 / 原子组件」',
      '在列表里找「课表待办」（也可能显示成 App 名），点进去能看到 6 个板块',
      '选你想显示的板块（课程表 / 待办 / 今日概览 / 比赛 / 灵感 / 专注），拖动到合适位置',
      '长按小组件边缘可以拉大拉小，显示更多条目',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: TextStyle(fontSize: 12.5, height: 1.6, color: context.text),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WidgetMeta {
  const _WidgetMeta(this.name, this.icon, this.hint, this.titleKey, this.bodyKey);
  final String name;
  final IconData icon;
  final String hint;
  final String titleKey;
  final String bodyKey;
}

const List<_WidgetMeta> _widgets = [
  _WidgetMeta('课程表', Icons.calendar_view_week, '今天几节课、几点上、在哪上', 'course_title', 'course_body'),
  _WidgetMeta('待办提醒', Icons.checklist, '最近 5 条没做完的事和截止时间', 'task_title', 'task_body'),
  _WidgetMeta('今日概览', Icons.today, '课程 + 待办 + 最近的比赛 + 专注时长', 'overview_title', 'overview_body'),
  _WidgetMeta('比赛提醒', Icons.emoji_events, '待参加的比赛和倒计时；没有时显示战绩', 'comp_title', 'comp_body'),
  _WidgetMeta('灵感记录', Icons.lightbulb_outline, '最近记下的灵感 / 痛点 / 想法', 'idea_title', 'idea_body'),
  _WidgetMeta('专注统计', Icons.timer_outlined, '今天和本周累计的专注时长', 'focus_title', 'focus_body'),
];

class _WidgetBlock extends StatelessWidget {
  const _WidgetBlock({
    required this.name,
    required this.icon,
    required this.hint,
    required this.title,
    required this.body,
    required this.footer,
  });

  final String name;
  final IconData icon;
  final String hint;
  final String title;
  final String body;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 5),
            Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text('4×2', style: TextStyle(fontSize: 10, color: Colors.black.withOpacity(0.3))),
            const Spacer(),
            Flexible(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: context.faint),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _WidgetPreview(title: title, body: body, footer: footer),
      ],
    );
  }
}

class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview({required this.title, required this.body, required this.footer});

  final String title;
  final String body;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: context.divider),
          ),
          Text(body, style: const TextStyle(fontSize: 12, color: Color(0xFF4A4F5C), height: 1.6)),
          const SizedBox(height: 6),
          Text(footer, style: const TextStyle(fontSize: 9.5, color: Color(0xFF9AA0AD))),
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
                Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.help_outline, size: 15, color: Theme.of(context).colorScheme.primary),
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
