import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import 'notification_service.dart';

class ReportService {
  /// 生成周报摘要
  static Future<ReportSummary> generateWeeklyReport({int? bookId}) async {
    final now = DateTime.now();
    // 本周一 00:00
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    // 上周一 00:00
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));

    return _generateReport(
      label: '本周',
      start: weekStart,
      end: now,
      compareStart: lastWeekStart,
      compareEnd: weekStart,
      bookId: bookId,
    );
  }

  /// 生成月报摘要
  static Future<ReportSummary> generateMonthlyReport({int? bookId}) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = monthStart;

    return _generateReport(
      label: '本月',
      start: monthStart,
      end: now,
      compareStart: lastMonthStart,
      compareEnd: lastMonthEnd,
      bookId: bookId,
    );
  }

  /// 检查并推送报告通知（周日晚推送周报，每月1号推送月报）
  static Future<void> checkAndPushReports() async {
    final now = DateTime.now();

    // 周日推送周报
    if (now.weekday == DateTime.sunday) {
      final weekly = await generateWeeklyReport();
      await NotificationService.showReportNotification(
        title: '📊 本周消费报告',
        body: weekly.notificationBody,
      );
    }

    // 每月1号推送月报
    if (now.day == 1) {
      final monthly = await generateMonthlyReport();
      await NotificationService.showReportNotification(
        title: '📈 本月消费报告',
        body: monthly.notificationBody,
      );
    }
  }

  static Future<ReportSummary> _generateReport({
    required String label,
    required DateTime start,
    required DateTime end,
    required DateTime compareStart,
    required DateTime compareEnd,
    int? bookId,
  }) async {
    final db = await DatabaseHelper.database;
    final fmt = NumberFormat('#,##0.00');

    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();
    final cmpStartStr = compareStart.toIso8601String();
    final cmpEndStr = compareEnd.toIso8601String();

    String bookFilter = '';
    List<Object?> args = [startStr, endStr];
    List<Object?> cmpArgs = [cmpStartStr, cmpEndStr];
    if (bookId != null) {
      bookFilter = ' AND book_id=?';
      args.add(bookId);
      cmpArgs.add(bookId);
    }

    // 当期总额
    final currTotal = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) as total FROM transactions
         WHERE type='expense' AND date>=? AND date<? $bookFilter''',
      args,
    );
    final currAmt = (currTotal.first['total'] as num).toDouble();

    // 上期总额
    final prevTotal = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) as total FROM transactions
         WHERE type='expense' AND date>=? AND date<? $bookFilter''',
      cmpArgs,
    );
    final prevAmt = (prevTotal.first['total'] as num).toDouble();

    // 分类排名
    final catRank = await db.rawQuery(
      '''SELECT c.name, SUM(t.amount) as total
         FROM transactions t JOIN categories c ON t.category_id=c.id
         WHERE t.type='expense' AND t.date>=? AND t.date<? $bookFilter
         GROUP BY t.category_id ORDER BY total DESC LIMIT 5''',
      args,
    );

    final topCats = catRank.map((c) {
      final amt = (c['total'] as num).toDouble();
      final pct = currAmt > 0 ? (amt / currAmt * 100).toStringAsFixed(0) : '0';
      return '  ${c['name']}: ¥${fmt.format(amt)} (占$pct%)';
    }).toList();

    // 变化百分比
    String trend;
    if (prevAmt > 0) {
      final delta = ((currAmt - prevAmt) / prevAmt * 100);
      if (delta.abs() < 1) {
        trend = '与上期基本持平';
      } else if (delta > 0) {
        trend = '较上期增加 ${delta.toStringAsFixed(0)}%';
      } else {
        trend = '较上期减少 ${delta.abs().toStringAsFixed(0)}%';
      }
    } else {
      trend = '上期无消费记录';
    }

    return ReportSummary(
      label: label,
      totalAmount: currAmt,
      trend: trend,
      topCategories: topCats,
      fmt: fmt,
    );
  }
}

class ReportSummary {
  final String label;
  final double totalAmount;
  final String trend;
  final List<String> topCategories;
  final NumberFormat fmt;

  ReportSummary({
    required this.label,
    required this.totalAmount,
    required this.trend,
    required this.topCategories,
    required this.fmt,
  });

  /// 通知推送用的简短摘要
  String get notificationBody {
    final parts = <String>[
      '$label总支出: ¥${fmt.format(totalAmount)}',
      trend,
    ];
    if (topCategories.isNotEmpty) {
      parts.add(topCategories.take(2).join(' | '));
    }
    return parts.join('，');
  }
}
