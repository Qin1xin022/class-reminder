import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// 把各板块内容写进桌面小组件。
/// 所有小组件共用 layout/widget_text.xml，只是读不同的 key：
///   course_*  CourseWidgetProvider
///   task_*    TaskWidgetProvider
///   overview_* OverviewWidgetProvider
///   comp_*    CompWidgetProvider
///   idea_*    IdeaWidgetProvider
///   focus_*   FocusWidgetProvider
class WidgetService {
  static const String androidPackage = 'com.mystudy.class_reminder';

  /// 全部已注册的桌面小组件（新增板块时同步加到这里 + AndroidManifest）
  static const List<String> providers = [
    'CourseWidgetProvider',
    'TaskWidgetProvider',
    'OverviewWidgetProvider',
    'CompWidgetProvider',
    'IdeaWidgetProvider',
    'FocusWidgetProvider',
  ];

  /// [data] 是给引导页预览用的现成文本；[payload] 是给原生现算倒计时用的 JSON
  static Future<void> update(Map<String, String> data, String payload) async {
    if (!Platform.isAndroid) return;
    try {
      await HomeWidget.saveWidgetData<String>('widget_json', payload);
      for (final e in data.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      for (final name in providers) {
        await HomeWidget.updateWidget(
          androidName: name,
          qualifiedAndroidName: '$androidPackage.$name',
        );
      }
    } catch (e) {
      debugPrint('WidgetService.update failed: $e');
    }
  }
}
