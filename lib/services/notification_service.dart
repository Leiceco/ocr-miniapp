import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../database/database_helper.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  // ---- 初始化 ----
  static Future<void> init() async {
    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // App 启动时重新调度每日提醒
    await _rescheduleDailyReminder();
  }

  // ---- 每日提醒 ----
  static Future<void> scheduleDailyReminder({int hour = 21, int minute = 0}) async {
    // 取消旧提醒
    await _notifications.cancel(100);

    final androidDetails = const AndroidNotificationDetails(
      'daily_reminder',
      '每日记账提醒',
      channelDescription: '提醒您每天记账',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    final details = NotificationDetails(android: androidDetails);

    // 使用 timezone 包调度每日定时通知
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      100,           // id
      '💰 记账提醒',
      '今天还没有记账哦，点击快速补录～',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    // 保存提醒时间
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminder_hour', hour);
    await prefs.setInt('reminder_minute', minute);
  }

  /// 智能调整提醒时间（基于用户活跃时段）
  static Future<void> adjustToActiveHours() async {
    final prefs = await SharedPreferences.getInstance();
    final activeData = prefs.getString('active_hours');
    if (activeData == null) return;

    final hours = (jsonDecode(activeData) as List<dynamic>)
        .map((e) => e as int)
        .toList();
    if (hours.isEmpty) return;

    // 取活跃时段的中间值作为提醒时间
    hours.sort();
    final median = hours[hours.length ~/ 2];
    final reminderHour = (median + 2).clamp(18, 22); // 限制在 18-22 点
    await scheduleDailyReminder(hour: reminderHour);
  }

  /// 检查今天是否有记录，没有则发通知
  static Future<void> checkAndRemind() async {
    final db = await DatabaseHelper.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final count = await db.rawQuery(
      '''SELECT COUNT(*) as cnt FROM transactions
         WHERE date >= ? AND date < ?''',
      ['${today}T00:00:00', '${today}T23:59:59'],
    );

    if ((count.first['cnt'] as int) == 0) {
      // 今天没记，立即发一条通知
      final androidDetails = const AndroidNotificationDetails(
        'daily_reminder',
        '每日记账提醒',
        channelDescription: '提醒您每天记账',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      final details = NotificationDetails(android: androidDetails);
      await _notifications.show(
        200,
        '💰 记账提醒',
        '今天还没有记账，点击快速补录！',
        details,
      );
    }
  }

  /// 记录用户活跃时间
  static Future<void> recordActiveTime() async {
    final now = DateTime.now();
    if (now.hour < 8 || now.hour > 23) return; // 仅记录 8-23 点

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('active_hours');
    List<int> hours;
    if (stored != null) {
      hours = (jsonDecode(stored) as List<dynamic>)
          .map((e) => e as int)
          .toList();
    } else {
      hours = [];
    }
    hours.add(now.hour);
    // 保留最近 30 条记录
    if (hours.length > 30) hours = hours.sublist(hours.length - 30);
    await prefs.setString('active_hours', jsonEncode(hours));
  }

  /// 发送周报/月报通知
  static Future<void> showReportNotification({
    required String title,
    required String body,
  }) async {
    final androidDetails = const AndroidNotificationDetails(
      'report',
      '消费报告',
      channelDescription: '周报/月报推送',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    final details = NotificationDetails(android: androidDetails);
    await _notifications.show(300, title, body, details);
  }

  // ---- 内部 ----
  static void _onNotificationTap(NotificationResponse response) {
    // 点击通知后的处理由 main.dart 中的全局监听处理
  }

  static Future<void> _rescheduleDailyReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt('reminder_hour') ?? 21;
    final minute = prefs.getInt('reminder_minute') ?? 0;
    await scheduleDailyReminder(hour: hour, minute: minute);
  }
}
