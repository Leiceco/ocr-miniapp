import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../main.dart';
import '../services/report_service.dart';
import '../services/notification_service.dart';
import '../utils/app_state.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  double _monthExpense = 0;
  double _monthIncome = 0;
  double _monthBudget = 0;
  String _currentBook = '日常账本';
  int _currentBookId = 1;

  /// key = category_id, value = (name, icon, total)
  Map<int, _CatTotal> _categoryTotals = {};

  /// 完整交易列表（已按日期倒序）
  List<Map<String, dynamic>> _transactions = [];

  /// 账本列表
  List<Map<String, dynamic>> _books = [];

  /// 筛选条件: all / expense / income
  String _filter = 'all';

  /// 周报/月报摘要
  ReportSummary? _weeklyReport;
  ReportSummary? _monthlyReport;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppState.addListener(_onDataChanged);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppState.removeListener(_onDataChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadData();
  }

  void _onDataChanged() {
    _loadData();
  }

  Future<void> _loadData() async {
    final db = await DatabaseHelper.database;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final nextMonth =
        DateTime(now.year, now.month + 1, 1).toIso8601String();

    // --- 账本列表 & 当前选中账本 ---
    final books = await db.query('account_books');
    final curBook = books.firstWhere(
      (b) => b['id'] == _currentBookId,
      orElse: () => books.isNotEmpty ? books.first : {'name': '日常账本', 'id': 1},
    );

    // --- 月度汇总 ---
    final expenseSum = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) as total FROM transactions
         WHERE type='expense' AND date >= ? AND date < ? AND book_id=?''',
      [monthStart, nextMonth, _currentBookId],
    );
    final incomeSum = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) as total FROM transactions
         WHERE type='income' AND date >= ? AND date < ? AND book_id=?''',
      [monthStart, nextMonth, _currentBookId],
    );
    final budgetSum = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) as total FROM budgets
         WHERE book_id=? AND period='monthly' AND (category_id IS NULL)''',
      [_currentBookId],
    );

    // --- 分类统计（本月支出） ---
    final catTotals = await db.rawQuery(
      '''SELECT c.id as cat_id, c.name, c.icon, SUM(t.amount) as total
         FROM transactions t JOIN categories c ON t.category_id=c.id
         WHERE t.type='expense' AND t.date >= ? AND t.date < ? AND t.book_id=?
         GROUP BY t.category_id ORDER BY total DESC''',
      [monthStart, nextMonth, _currentBookId],
    );

    // --- 交易列表（全部 / 按筛选条件） ---
    List<Map<String, dynamic>> transactions;
    if (_filter == 'all') {
      transactions = await db.rawQuery(
        '''SELECT t.*, c.name as cat_name, c.icon as cat_icon
           FROM transactions t JOIN categories c ON t.category_id=c.id
           WHERE t.book_id=?
           ORDER BY t.date DESC, t.id DESC''',
        [_currentBookId],
      );
    } else {
      transactions = await db.rawQuery(
        '''SELECT t.*, c.name as cat_name, c.icon as cat_icon
           FROM transactions t JOIN categories c ON t.category_id=c.id
           WHERE t.book_id=? AND t.type=?
           ORDER BY t.date DESC, t.id DESC''',
        [_currentBookId, _filter],
      );
    }

    if (mounted) {
      setState(() {
        _books = books;
        _currentBook = curBook['name'] as String;
        _currentBookId = curBook['id'] as int;

        _monthExpense = (expenseSum.first['total'] as num).toDouble();
        _monthIncome = (incomeSum.first['total'] as num).toDouble();
        _monthBudget = (budgetSum.first['total'] as num).toDouble();

        _categoryTotals = {
          for (var r in catTotals)
            r['cat_id'] as int: _CatTotal(
              name: r['name'] as String,
              icon: r['icon'] as String,
              total: (r['total'] as num).toDouble(),
            )
        };

        _transactions = transactions;
      });
    }
    // 加载报告（非阻塞）
    _loadReports();
  }

  Future<void> _loadReports() async {
    final weekly = await ReportService.generateWeeklyReport();
    final monthly = await ReportService.generateMonthlyReport();
    if (mounted) {
      setState(() {
        _weeklyReport = weekly;
        _monthlyReport = monthly;
      });
    }
  }

  /// 推送报告通知
  Future<void> _pushReports() async {
    await ReportService.checkAndPushReports();
    // 同时记录活跃时间，用于智能调整提醒
    await NotificationService.recordActiveTime();
  }

  /// 删除交易 —— 弹出确认对话框后执行
  Future<void> _deleteTransaction(Map<String, dynamic> t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text(
          '确定删除这笔${t['type'] == 'expense' ? '支出' : '收入'}记录吗？\n'
          '金额：¥${NumberFormat('#,##0.00').format(t['amount'])}\n'
          '分类：${t['cat_name']}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final db = await DatabaseHelper.database;
        await db.delete(
          'transactions',
          where: 'id=?',
          whereArgs: [t['id']],
        );
        AppState.notify();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已删除')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final remain = _monthBudget - _monthExpense;
    final budgetPct =
        _monthBudget > 0 ? (_monthExpense / _monthBudget).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value:
                _books.any((b) => b['name'] == _currentBook) ? _currentBook : null,
            items: _books
                .map((b) => DropdownMenuItem(
                    value: b['name'] as String,
                    child: Text(b['name'] as String)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              final b = _books.firstWhere((b) => b['name'] == v);
              setState(() {
                _currentBook = v;
                _currentBookId = b['id'] as int;
              });
              _loadData();
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: () {
              context.findAncestorStateOfType<MainShellState>()?.switchToTab(1);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ===== 月度概览卡片 =====
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('本月支出',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text('¥${fmt.format(_monthExpense)}',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error)),
                    if (_monthBudget > 0) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: budgetPct),
                      const SizedBox(height: 4),
                      Text(
                        '预算 ¥${fmt.format(_monthBudget)}  剩余 ¥${fmt.format(remain)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _summaryChip(context, '收入', _monthIncome, Colors.green),
                        const SizedBox(width: 32),
                        _summaryChip(context, '结余',
                            _monthIncome - _monthExpense,
                            (_monthIncome - _monthExpense) >= 0
                                ? Colors.blue
                                : Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ===== 分类统计（本月支出） =====
            if (_categoryTotals.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('支出分类', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _categoryTotals.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _categoryCard(context, e.value.name,
                          e.value.icon, e.value.total, _monthExpense),
                    );
                  }).toList(),
                ),
              ),
            ],

            // ===== 周报/月报 =====
            if (_weeklyReport != null || _monthlyReport != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('消费报告', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _loadReports,
                    tooltip: '刷新报告',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_weeklyReport != null) _reportCard(context, _weeklyReport!),
              if (_monthlyReport != null) ...[
                const SizedBox(height: 8),
                _reportCard(context, _monthlyReport!),
              ],
            ],

            // ===== 筛选 + 列表 =====
            const SizedBox(height: 16),
            Row(
              children: [
                Text('账单明细', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${_transactions.length} 笔',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),

            // 筛选芯片
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('全部', 'all'),
                  const SizedBox(width: 8),
                  _filterChip('支出', 'expense'),
                  const SizedBox(width: 8),
                  _filterChip('收入', 'income'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 交易列表
            if (_transactions.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('暂无记录，点击底部"记账"开始'),
                ),
              )
            else
              ..._transactions.map((t) => _transactionItem(t, fmt)),
          ],
        ),
      ),
    );
  }

  // -------- 小组件 --------

  Widget _summaryChip(
      BuildContext context, String label, double amount, Color color) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text('¥${NumberFormat('#,##0.00').format(amount)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _categoryCard(BuildContext context, String name, String icon,
      double total, double all) {
    final pct = all > 0 ? total / all : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(_catIcon(icon),
                color: Theme.of(context).colorScheme.primary),
            Text(name, style: Theme.of(context).textTheme.bodySmall),
            Text('${(pct * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _filter = value);
        _loadData();
      },
      showCheckmark: false,
    );
  }

  /// 单条交易记录 —— 支持滑动删除
  Widget _transactionItem(Map<String, dynamic> t, NumberFormat fmt) {
    final isExpense = t['type'] == 'expense';
    final dateStr = t['date'] as String;
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();

    return Dismissible(
      key: Key('txn-${t['id']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteTransaction(t);
        return false; // 由 _deleteTransaction 内部处理删除与刷新
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          leading: CircleAvatar(
            radius: 18,
            child: Icon(_catIcon(t['cat_icon'] as String?), size: 18),
          ),
          title: Text(
            t['cat_name'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Row(
            children: [
              Text(DateFormat('MM-dd HH:mm').format(date),
                  style: const TextStyle(fontSize: 12)),
              if ((t['note'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    t['note'] as String,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          trailing: Text(
            '${isExpense ? '-' : '+'}¥${fmt.format(t['amount'])}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isExpense ? Colors.red : Colors.green,
              fontSize: 16,
            ),
          ),
          onLongPress: () => _deleteTransaction(t),
        ),
      ),
    );
  }

  Widget _reportCard(BuildContext context, ReportSummary report) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assessment, size: 18, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Text('${report.label}总支出: ¥${report.fmt.format(report.totalAmount)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Text(report.trend,
                style: TextStyle(
                    fontSize: 13,
                    color: report.trend.contains('增加')
                        ? Colors.red
                        : Colors.green.shade700)),
            if (report.topCategories.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...report.topCategories
                  .map((c) => Text(c,
                      style: const TextStyle(fontSize: 12, color: Colors.black87)))
                  .take(3),
            ],
          ],
        ),
      ),
    );
  }

  IconData _catIcon(String? icon) {
    return switch (icon) {
      'fastfood' => Icons.fastfood,
      'directions_car' => Icons.directions_car,
      'shopping_bag' => Icons.shopping_bag,
      'movie' => Icons.movie,
      'home' => Icons.home,
      'phone' => Icons.phone,
      'local_hospital' => Icons.local_hospital,
      'school' => Icons.school,
      'people' => Icons.people,
      'work' => Icons.work,
      'handyman' => Icons.handyman,
      'trending_up' => Icons.trending_up,
      'undo' => Icons.undo,
      _ => Icons.more_horiz,
    };
  }
}

/// 分类统计条目
class _CatTotal {
  final String name;
  final String icon;
  final double total;
  const _CatTotal(
      {required this.name, required this.icon, required this.total});
}
