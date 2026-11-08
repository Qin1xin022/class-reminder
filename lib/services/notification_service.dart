import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 全应用唯一的通知入口。
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const String _channelId = 'class_reminder_main';

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static Future<void> init() async {
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      // 中国时区固定为 Asia/Shanghai，无需额外原生插件查询系统时区
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
      _ready = true;
    } catch (e) {
      debugPrint('NotificationService.init failed: $e');
    }
  }

  /// 向系统申请通知权限（Android 12+ 还要精确闹钟权限）
  static Future<void> requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
        await android?.requestExactAlarmsPermission();
      } else if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('requestPermissions failed: $e');
    }
  }

  static bool get supportAndroid => Platform.isAndroid;

  static final NotificationDetails _details = const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      '课程与待办提醒',
      channelDescription: '上课提醒、作业截止提醒、自习与工作提醒',
      importance: Importance.max,
      priority: Priority.high,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
  );

  static Future<void> scheduleAt(
    DateTime when,
    String title,
    String body,
    int id, {
    String? payload,
  }) async {
    if (!_ready) return;
    final target = tz.TZDateTime.from(when, tz.local);
    if (!target.isAfter(tz.TZDateTime.now(tz.local))) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        target,
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      debugPrint('exact schedule failed ($e), fallback to inexact');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          target,
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
      } catch (err) {
        debugPrint('schedule failed: $err');
      }
    }
  }

  static Future<void> cancel(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id);
  }

  static Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }
}
