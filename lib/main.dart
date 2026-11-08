import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/competition_list_screen.dart';
import 'screens/home_screen.dart';
import 'screens/knowledge_screen.dart';
import 'screens/notice_list_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/task_list_screen.dart';
import 'screens/timetable_screen.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';
import 'theme/tokens.dart';
import 'widgets/tab_switch.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  final state = AppState();
  try {
    await state.load();
  } catch (e) {
    debugPrint('数据库初始化失败: $e');
  }
  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const ClassReminderApp(),
    ),
  );
}

class ClassReminderApp extends StatelessWidget {
  const ClassReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dark = app.darkMode;
    final seed = Color(app.themeSeed);

    // 从主题色自动派生一整套配色（按钮、选中态、浅色底……）
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    final bg = dark ? const Color(0xFF111318) : const Color(0xFFF5F6FA);
    final card = dark ? const Color(0xFF1D2027) : Colors.white;

    return MaterialApp(
      title: '课表 · 待办',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: bg,
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: dark ? const Color(0xFFE8EAF0) : context.text,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: card,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        dialogTheme: DialogThemeData(backgroundColor: card),
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        dividerTheme: DividerThemeData(
          color: dark ? const Color(0xFF2C313C) : const Color(0xFFE8EAF0),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: card,
          indicatorColor: seed.withOpacity(0.15),
          labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 11)),
        ),
      ),
      // 全局字号缩放：设置里选小/标准/大
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: TextScaler.linear(app.fontScale),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  static const MethodChannel _launch = MethodChannel('class_reminder/launch');

  int _index = 0;
  Timer? _widgetTick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _launch.setMethodCallHandler((call) async {
      if (call.method == 'openTab') {
        _goTab(call.arguments is int ? call.arguments as int : null);
      }
      return null;
    });
    _readLaunchTab();
    _startTick();
  }

  @override
  void dispose() {
    _widgetTick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从桌面小组件点进来时，直接落到对应板块
  Future<void> _readLaunchTab() async {
    try {
      final tab = await _launch.invokeMethod<int>('getLaunchTab');
      _goTab(tab);
    } catch (_) {}
  }

  void _goTab(int? tab) {
    if (tab == null || tab < 0 || tab > 6 || !mounted) return;
    setState(() => _index = tab);
  }

  /// App 在前台时每分钟刷一次小组件，让「还剩多少分钟」跟着走
  void _startTick() {
    _widgetTick?.cancel();
    _widgetTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      context.read<AppState>().refreshWidgets().catchError((Object _) {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().refreshWidgets().catchError((Object _) {});
      _startTick();
    } else {
      _widgetTick?.cancel();
      _widgetTick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TabSwitch(
        go: (i) => setState(() => _index = i),
        child: IndexedStack(
          index: _index,
          children: const [
            HomeScreen(),
            TimetableScreen(),
            TaskListScreen(),
            KnowledgeScreen(),
            CompetitionListScreen(),
            NoticeListScreen(),
            SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: '今日'),
          NavigationDestination(icon: Icon(Icons.calendar_view_week_outlined), selectedIcon: Icon(Icons.calendar_view_week), label: '课表'),
          NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: '任务'),
          NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book), label: '记录'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: '比赛'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: '通知'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
