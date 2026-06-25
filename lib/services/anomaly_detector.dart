import '../database/database_helper.dart';

/// 异常检测结果
class AnomalyResult {
  final List<String> warnings;
  bool get hasWarning => warnings.isNotEmpty;
  AnomalyResult(this.warnings);
}

/// 本地规则引擎 —— 账单异常检测
/// 检查：金额突增、疑似重复、预算超支
class AnomalyDetector {
  /// 对即将保存的账单执行完整检查
  static Future<AnomalyResult> check({
    required int bookId,
    required int categoryId,
    required double amount,
    required String type,
    required String date,
    int? excludeTransactionId, // 更新时排除自身
  }) async {
    final warnings = <String>[];
    final db = await DatabaseHelper.database;

    // 1. 疑似重复记账（同一账本 + 同日期 + 同分类 + 同金额）
    final dups = await db.rawQuery(
      '''SELECT id FROM transactions
         WHERE book_id=? AND date=? AND category_id=? AND amount=?
         AND (? IS NULL OR id != ?)
         LIMIT 1''',
      [bookId, date, categoryId, amount, excludeTransactionId, excludeTransactionId ?? 0],
    );
    if (dups.isNotEmpty) {
      warnings.add('⚠️ 疑似重复记账：今天已有一笔相同分类、相同金额的记录了');
    }

    // 2. 金额突增（超出该分类近 30 天平均值的 3 倍）
    if (type == 'expense') {
      final thirtyDaysAgo = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String();
      final history = await db.rawQuery(
        '''SELECT AVG(amount) as avg_amt, COUNT(*) as cnt
           FROM transactions
           WHERE book_id=? AND category_id=? AND type='expense'
           AND date >= ?''',
        [bookId, categoryId, thirtyDaysAgo],
      );
      final avg = (history.first['avg_amt'] as num?)?.toDouble() ?? 0;
      final cnt = history.first['cnt'] as int;
      if (cnt >= 3 && avg > 0 && amount > avg * 3) {
        warnings.add(
          '📈 金额突增：这笔 ¥${amount.toStringAsFixed(2)} 远超该分类近 30 天均值 ¥${avg.toStringAsFixed(2)}');
      }
    }

    // 3. 预算超支检查
    final monthStart = DateTime(
      DateTime.now().year, DateTime.now().month, 1).toIso8601String();
    final nextMonth = DateTime(
      DateTime.now().year, DateTime.now().month + 1, 1).toIso8601String();

    final budgets = await db.rawQuery(
      '''SELECT amount FROM budgets
         WHERE book_id=? AND (category_id IS NULL OR category_id=?)
         AND period='monthly' LIMIT 1''',
      [bookId, categoryId],
    );
    if (budgets.isNotEmpty) {
      final budget = (budgets.first['amount'] as num).toDouble();
      final spent = await db.rawQuery(
        '''SELECT COALESCE(SUM(amount),0) as total FROM transactions
           WHERE book_id=? AND type='expense' AND date>=? AND date<?
           AND category_id=?''',
        [bookId, monthStart, nextMonth, categoryId],
      );
      final spentAmount = (spent.first['total'] as num).toDouble();
      final newTotal = spentAmount + amount;
      if (newTotal > budget) {
        final pct = (newTotal / budget * 100).toStringAsFixed(0);
        warnings.add('💸 预算超支：加上这笔后该分类本月已花费 ¥${newTotal.toStringAsFixed(2)}，超过预算 ¥${budget.toStringAsFixed(2)} ($pct%)');
      } else if (newTotal > budget * 0.85) {
        warnings.add('⚡ 预算预警：加上这笔后已达预算的 ${(newTotal / budget * 100).toStringAsFixed(0)}%');
      }
    }

    return AnomalyResult(warnings);
  }
}
