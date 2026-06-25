import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../utils/app_state.dart';

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final _amountCtrl = TextEditingController();
  int _bookId = 1;
  String _period = 'monthly';
  List<Map<String, dynamic>> _budgets = [];
  List<Map<String, dynamic>> _books = [];
  /// key = category_id (non-null), 不包含 null.
  /// 总预算的已花金额 = values 之和.
  Map<int, double> _spentMap = {};

  @override
  void initState() {
    super.initState();
    AppState.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    AppState.removeListener(_onDataChanged);
    _amountCtrl.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseHelper.database;
    final books = await db.query('account_books');
    // 动态获取当前选中的 bookId，避免硬编码假设
    if (!books.any((b) => b['id'] == _bookId) && books.isNotEmpty) {
      _bookId = books.first['id'] as int;
    }

    final now = DateTime.now();
    final start = _period == 'monthly'
        ? DateTime(now.year, now.month, 1).toIso8601String()
        : DateTime(now.year, 1, 1).toIso8601String();

    final budgets = await db.rawQuery(
      '''SELECT b.*, c.name as cat_name, c.icon as cat_icon
         FROM budgets b LEFT JOIN categories c ON b.category_id=c.id
         WHERE b.book_id=? ORDER BY b.period, b.id''',
      [_bookId],
    );

    final spent = await db.rawQuery(
      '''SELECT category_id, SUM(amount) as total
         FROM transactions WHERE book_id=? AND type='expense' AND date>=?
         GROUP BY category_id''',
      [_bookId, start],
    );

    if (mounted) {
      setState(() {
        _books = books;
        _budgets = budgets;
        _spentMap = {
          for (var s in spent)
            if (s['category_id'] != null)
              s['category_id'] as int: (s['total'] as num).toDouble()
        };
      });
    }
  }

  Future<void> _addBudget() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入有效金额')),
        );
      }
      return;
    }

    final db = await DatabaseHelper.database;
    await db.insert('budgets', {
      'book_id': _bookId,
      'category_id': null,
      'amount': amount,
      'period': _period,
    });
    _amountCtrl.clear();
    AppState.notify();
    _load();
  }

  Future<void> _deleteBudget(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预算'),
        content: const Text('确定要删除这条预算吗？'),
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
    if (confirm != true) return;

    final db = await DatabaseHelper.database;
    await db.delete('budgets', where: 'id=?', whereArgs: [id]);
    AppState.notify();
    _load();
  }

  /// 计算某条预算已花费金额。
  /// - 分类预算（category_id 非空）：取该分类的支出
  /// - 总预算（category_id 为空）：取所有分类支出之和
  double _spentFor(Map<String, dynamic> budget) {
    final catId = budget['category_id'];
    if (catId != null) {
      return _spentMap[catId as int] ?? 0.0;
    }
    // 总预算：汇总所有分类的支出
    return _spentMap.values.fold(0.0, (a, b) => a + b);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return Scaffold(
      appBar: AppBar(title: const Text('预算管理')),
      body: Column(children: [
        // 账本切换
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Text('账本: '),
            Expanded(
              child: DropdownButton<int>(
                value: _books.any((b) => b['id'] == _bookId) ? _bookId : null,
                isExpanded: true,
                items: _books.map((b) => DropdownMenuItem(
                    value: b['id'] as int, child: Text(b['name'] as String))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _bookId = v);
                  _load();
                },
              ),
            ),
          ]),
        ),
        // 添加预算
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '预算金额',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'monthly', label: Text('月')),
                ButtonSegment(value: 'yearly', label: Text('年')),
              ],
              selected: {_period},
              onSelectionChanged: (v) => setState(() => _period = v.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.add),
              onPressed: _addBudget,
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _budgets.isEmpty
              ? const Center(child: Text('暂无预算，请添加'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _budgets.length,
                  itemBuilder: (_, i) {
                    final b = _budgets[i];
                    final amount = (b['amount'] as num).toDouble();
                    final spent = _spentFor(b);
                    final remain = amount - spent;
                    final pct = amount > 0 ? (spent / amount).clamp(0.0, 1.0) : 0.0;
                    final periodLabel = b['period'] == 'monthly' ? '月预算' : '年预算';
                    final label = b['cat_name'] ?? '$periodLabel (总预算)';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(child: Text(label,
                                  style: const TextStyle(fontWeight: FontWeight.bold))),
                              Text('¥${fmt.format(amount)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => _deleteBudget(b['id'] as int),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: pct,
                                color: remain >= 0 ? Colors.green : Colors.red),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('已花 ¥${fmt.format(spent)}',
                                    style: Theme.of(context).textTheme.bodySmall),
                                Text('剩余 ¥${fmt.format(remain)}',
                                    style: TextStyle(
                                        color: remain >= 0 ? Colors.green : Colors.red,
                                        fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
