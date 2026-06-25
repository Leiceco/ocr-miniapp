import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../utils/app_state.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});
  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  String _period = 'month';
  DateTime _currentMonth = DateTime.now();
  int _currentYear = DateTime.now().year;
  int _bookId = 1;

  double _totalExpense = 0;
  double _totalIncome = 0;
  List<PieChartSectionData> _pieSections = [];
  List<BarChartGroupData> _barGroups = [];
  Map<String, double> _categoryData = {};
  List<Map<String, dynamic>> _books = [];

  @override
  void initState() {
    super.initState();
    AppState.addListener(_onDataChanged);
    _loadMeta();
  }

  @override
  void dispose() {
    AppState.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    _loadStats();
  }

  Future<void> _loadMeta() async {
    final db = await DatabaseHelper.database;
    final books = await db.query('account_books');
    if (mounted) {
      setState(() {
        _books = books;
        if (_books.isNotEmpty &&
            !_books.any((b) => b['id'] == _bookId)) {
          _bookId = _books.first['id'] as int;
        }
      });
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    final db = await DatabaseHelper.database;
    String start, end;

    if (_period == 'month') {
      start = DateTime(_currentMonth.year, _currentMonth.month, 1).toIso8601String();
      // Dart: day=0 取上个月最后一天，配合 23:59:59 覆盖整月
      end = DateTime(_currentMonth.year, _currentMonth.month + 1, 0, 23, 59, 59)
          .toIso8601String();
    } else {
      start = DateTime(_currentYear, 1, 1).toIso8601String();
      end = DateTime(_currentYear, 12, 31, 23, 59, 59).toIso8601String();
    }

    final totals = await db.rawQuery(
      '''SELECT type, COALESCE(SUM(amount),0) as total
         FROM transactions WHERE date>=? AND date<=? AND book_id=?
         GROUP BY type''',
      [start, end, _bookId],
    );

    final catData = await db.rawQuery(
      '''SELECT c.name, c.icon, t.type, SUM(t.amount) as total
         FROM transactions t JOIN categories c ON t.category_id=c.id
         WHERE t.date>=? AND t.date<=? AND t.type='expense' AND t.book_id=?
         GROUP BY t.category_id ORDER BY total DESC''',
      [start, end, _bookId],
    );

    // monthly bar chart
    List<Map<String, dynamic>> monthlyBars;
    if (_period == 'year') {
      monthlyBars = await db.rawQuery(
        '''SELECT strftime('%m', date) as month, type, SUM(amount) as total
           FROM transactions WHERE date>=? AND date<=? AND book_id=?
           GROUP BY month, type ORDER BY month''',
        [start, end, _bookId],
      );
    } else {
      monthlyBars = await db.rawQuery(
        '''SELECT strftime('%d', date) as day, type, SUM(amount) as total
           FROM transactions WHERE date>=? AND date<=? AND book_id=?
           GROUP BY day, type ORDER BY day''',
        [start, end, _bookId],
      );
    }

    if (mounted) {
      double exp = 0, inc = 0;
      for (var t in totals) {
        if (t['type'] == 'expense') exp = (t['total'] as num).toDouble();
        if (t['type'] == 'income') inc = (t['total'] as num).toDouble();
      }

      final colors = [
        Colors.red, Colors.orange, Colors.amber, Colors.green,
        Colors.teal, Colors.blue, Colors.indigo, Colors.purple,
        Colors.brown, Colors.blueGrey,
      ];
      final pieSections = <PieChartSectionData>[];
      for (int i = 0; i < catData.length; i++) {
        final total = (catData[i]['total'] as num).toDouble();
        if (total == 0) continue;
        pieSections.add(PieChartSectionData(
          value: total,
          title: exp > 0 ? '${(total / exp * 100).toStringAsFixed(0)}%' : '0%',
          color: colors[i % colors.length],
          radius: 50,
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ));
      }

      setState(() {
        _totalExpense = exp;
        _totalIncome = inc;
        _pieSections = pieSections;
        _categoryData = {
          for (var c in catData)
            '${c['name']}|${c['icon']}': (c['total'] as num).toDouble()
        };

        // build bars
        final bars = <BarChartGroupData>[];
        final expMap = <int, double>{};
        final incMap = <int, double>{};
        final isYear = _period == 'year';
        for (var r in monthlyBars) {
          final key = int.parse((isYear ? r['month'] : r['day']) as String);
          if (r['type'] == 'expense') expMap[key] = (r['total'] as num).toDouble();
          if (r['type'] == 'income') incMap[key] = (r['total'] as num).toDouble();
        }
        final maxKey = isYear ? 12 : DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
        for (int i = 1; i <= maxKey; i++) {
          bars.add(BarChartGroupData(x: i, barRods: [
            BarChartRodData(toY: expMap[i] ?? 0, color: Colors.red.shade300, width: isYear ? 6 : 4),
            BarChartRodData(toY: incMap[i] ?? 0, color: Colors.green.shade300, width: isYear ? 6 : 4),
          ]));
        }
        _barGroups = bars;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('统计分析'),
        actions: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'month', label: Text('月')),
              ButtonSegment(value: 'year', label: Text('年')),
            ],
            selected: {_period},
            onSelectionChanged: (v) {
              setState(() => _period = v.first);
              _loadStats();
            },
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // 账本选择
          if (_books.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '账本',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _books.any((b) => b['id'] == _bookId) ? _bookId : null,
                    isExpanded: true,
                    isDense: true,
                    items: _books
                        .map((b) => DropdownMenuItem(
                            value: b['id'] as int, child: Text(b['name'] as String)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _bookId = v!);
                      _loadStats();
                    },
                  ),
                ),
              ),
            ),
          // period switcher
          if (_period == 'month')
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      setState(() {
                        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
                      });
                      _loadStats();
                    }),
                Text('${_currentMonth.year}年${_currentMonth.month}月',
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      setState(() {
                        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
                      });
                      _loadStats();
                    }),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      setState(() => _currentYear--);
                      _loadStats();
                    }),
                Text('$_currentYear年', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      setState(() => _currentYear++);
                      _loadStats();
                    }),
              ],
            ),
          const SizedBox(height: 16),
          // 收支汇总
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Text('支出', style: Theme.of(context).textTheme.bodySmall),
                      Text('¥${fmt.format(_totalExpense)}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Text('收入', style: Theme.of(context).textTheme.bodySmall),
                      Text('¥${fmt.format(_totalIncome)}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                    ]),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 饼图
          if (_pieSections.isNotEmpty) ...[
            Text('支出构成', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: PieChart(PieChartData(
                sections: _pieSections,
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              )),
            ),
            ..._categoryData.entries.map((e) {
              final parts = e.key.split('|');
              return ListTile(
                title: Text(parts[0]),
                trailing: Text('¥${fmt.format(e.value)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              );
            }),
            const SizedBox(height: 16),
          ],
          // 柱状图
          if (_barGroups.isNotEmpty) ...[
            Text(_period == 'month' ? '每日收支' : '每月收支',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: BarChart(BarChartData(
                barGroups: _barGroups,
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${v.toInt()}', style: const TextStyle(fontSize: 10)),
                    ),
                    reservedSize: 28,
                  )),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
              )),
            ),
          ],
        ]),
      ),
    );
  }
}
