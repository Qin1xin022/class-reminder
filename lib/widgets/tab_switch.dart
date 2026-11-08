import 'package:flutter/material.dart';

/// 让页面内部（比如首页的「看整周」）能切换底部 tab
class TabSwitch extends InheritedWidget {
  const TabSwitch({super.key, required this.go, required super.child});

  final void Function(int index) go;

  static void to(BuildContext context, int index) {
    context.dependOnInheritedWidgetOfExactType<TabSwitch>()?.go(index);
  }

  @override
  bool updateShouldNotify(TabSwitch oldWidget) => false;
}
