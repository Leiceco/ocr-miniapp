import '../database/database_helper.dart';

class BookRecommender {
  /// 根据近期使用频率推荐最合适的账本
  /// 返回推荐账本 ID，若无数据则返回 null
  static Future<int?> recommend() async {
    final db = await DatabaseHelper.database;

    // 查询近 30 天各账本的交易数量
    final thirtyDaysAgo = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    final counts = await db.rawQuery(
      '''SELECT book_id, COUNT(*) as cnt
         FROM transactions
         WHERE date >= ?
         GROUP BY book_id
         ORDER BY cnt DESC
         LIMIT 1''',
      [thirtyDaysAgo],
    );

    if (counts.isNotEmpty) {
      return counts.first['book_id'] as int;
    }

    // 如果近 30 天无交易，返回最近使用的账本
    final recent = await db.rawQuery(
      '''SELECT book_id FROM transactions
         ORDER BY date DESC, id DESC LIMIT 1''',
    );
    if (recent.isNotEmpty) {
      return recent.first['book_id'] as int;
    }

    // 返回第一个账本
    final books = await db.query('account_books', limit: 1);
    if (books.isNotEmpty) {
      return books.first['id'] as int;
    }

    return null;
  }
}
