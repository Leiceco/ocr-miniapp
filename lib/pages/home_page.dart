import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../main.dart';
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
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _books = [];

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
    // 用下月首日作为上界，避免包含未来记录
    final nextMonth = DateTime(now.year, now.month + 1, 1).toIso8601String();

    final books = await db.query('account_books');
    final expenses = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) as total FROM transactions
         WHERE type='expense' AND date >= ? AND date < ? AND book_id=?''',
      [monthStart, nextMonth, _currentBookId],
    );
    final incomes = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) as total FROM transactions
         WHERE type='income' AND date >= ? AND date < ? AND book_id=?''',
      [monthStart, nextMonth, _currentBookId],
    );
    final budgets = await db.rawQuery(
      '''SELECT COALESCE(SUM(amount),0) as total FROM budgets
         WHERE book_id=? AND period='monthly' AND (category_id IS NULL)''',
      [_currentBookId],
    );
    final catTotals = await db.rawQuery(
      '''SELECT c.id as cat_id, c.name, c.icon, SUM(t.amount) as total
         FROM transactions t JOIN categories c ON t.category_id=c.id
         WHERE t.type='expense' AND t.date >= ? AND t.date < ? AND t.book_id=?
         GROUP BY t.category_id ORDER BY total DESC''',
      [monthStart, nextMonth, _currentBookId],
    );
    final recent = await db.rawQuery(
      '''SELECT t.*, c.name as cat_name, c.icon as cat_icon
         FROM transactions t JOIN categories c ON t.category_id=c.id
         WHERE t.book_id=?
         ORDER BY t.date DESC, t.id DESC LIMIT 10''',
      [_currentBookId],
    );

    if (mounted) {
      setState(() {
        _books = books;
        // 动态取当前选中账本信息，避免硬编码假设
        final cur = books.firstWhere(
          (b) => b['id'] == _currentBookId,
          orElse: () => books.isNotEmpty ? books.first : {'name': '日常账本', 'id': 1},
        );
        _currentBook = cur['name'] as String;
        _currentBookId = cur['id'] as int;

        _monthExpense = (expenses.first['total'] as num).toDouble();
        _monthIncome = (incomes.first['total'] as num).toDouble();
        _monthBudget = (budgets.first['total'] as num).toDouble();
        _categoryTotals = {
          for (var r in catTotals)
            r['cat_id'] as int: _CatTotal(
              name: r['name'] as String,
              icon: r['icon'] as String,
              total: (r['total'] as num).toDouble(),
            )
        };
        _recentTransactions = recent;
      });
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
            value: _books.any((b) => b['name'] == _currentBook)
                ? _currentBook
                : null,
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
              // 通过 MainShellState 切换到记账页（索引 1）
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
            // 月度概览卡片
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
                        _summaryChip(context, '结余', _monthIncome - _monthExpense,
                            (_monthIncome - _monthExpense) >= 0
                                ? Colors.blue
                                : Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 分类统计
            if (_categoryTotals.isNotEmpty) ...[
              Text('支出分类', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _categoryTotals.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _categoryCard(context, e.value.name, e.value.icon,
                          e.value.total, _monthExpense),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 最近记录
            Text('最近记录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_recentTransactions.isEmpty)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('暂无记录，点击"记账"开始')))
            else
              ..._recentTransactions.map((t) => _transactionTile(t, fmt)),
          ],
        ),
      ),
    );
  }

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
            Icon(_catIcon(icon), color: Theme.of(context).colorScheme.primary),
            Text(name, style: Theme.of(context).textTheme.bodySmall),
            Text('${(pct * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _transactionTile(Map<String, dynamic> t, NumberFormat fmt) {
    final isExpense = t['type'] == 'expense';
    final dateStr = t['date'] as String;
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();
    return ListTile(
      leading: CircleAvatar(
        child: Icon(_catIcon(t['cat_icon'] as String?), size: 20),
      ),
      title: Text(t['cat_name'] as String? ?? ''),
      subtitle: Text(DateFormat('MM-dd HH:mm').format(date)),
      trailing: Text(
        '${isExpense ? '-' : '+'}¥${fmt.format(t['amount'])}',
        style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isExpense ? Colors.red : Colors.green,
            fontSize: 16),
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
  const _CatTotal({required this.name, required this.icon, required this.total});
}
