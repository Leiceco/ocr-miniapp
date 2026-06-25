import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../services/notification_service.dart';
import '../utils/app_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _expenseCats = [];
  List<Map<String, dynamic>> _incomeCats = [];
  int _reminderHour = 21;
  int _reminderMinute = 0;

  @override
  void initState() {
    super.initState();
    AppState.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    AppState.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseHelper.database;
    final books = await db.query('account_books');
    final ec = await db.query('categories', where: 'type=?', whereArgs: ['expense'], orderBy: 'sort_order');
    final ic = await db.query('categories', where: 'type=?', whereArgs: ['income'], orderBy: 'sort_order');
    if (mounted) setState(() { _books = books; _expenseCats = ec; _incomeCats = ic; });

    // 加载通知时间偏好
    final prefs = await SharedPreferences.getInstance();
    final h = prefs.getInt('reminder_hour') ?? 21;
    final m = prefs.getInt('reminder_minute') ?? 0;
    if (mounted) setState(() { _reminderHour = h; _reminderMinute = m; });
  }

  Future<void> _addBook() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建账本'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '账本名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) {
                // 空名称不允许提交，弹出提示
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入账本名称')),
                );
                return;
              }
              Navigator.pop(ctx, text);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty) {
      try {
        final db = await DatabaseHelper.database;
        await db.insert('account_books', {
          'name': name,
          'description': '',
          'created_at': DateTime.now().toIso8601String(),
        });
        AppState.notify();
        // _load() 已通过 AppState 监听器自动触发，无需重复调用
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('账本「$name」创建成功')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _addCategory(String type) async {
    final nameCtrl = TextEditingController();
    final iconCtrl = TextEditingController(text: 'more_horiz');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == 'expense' ? '添加支出分类' : '添加收入分类'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '名称'),
              autofocus: true,
            ),
            TextField(
              controller: iconCtrl,
              decoration: const InputDecoration(labelText: 'Material图标名'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final nameText = nameCtrl.text.trim();
              if (nameText.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入分类名称')),
                );
                return;
              }
              Navigator.pop(ctx, {
                'name': nameText,
                'icon': iconCtrl.text.trim(),
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    iconCtrl.dispose();
    if (result != null && (result['name'] ?? '').isNotEmpty) {
      try {
        final db = await DatabaseHelper.database;
        final maxOrder = await db.rawQuery(
          'SELECT COALESCE(MAX(sort_order), -1) as mo FROM categories WHERE type=?',
          [type],
        );
        await db.insert('categories', {
          'name': result['name'],
          'icon': result['icon'],
          'type': type,
          'sort_order': (maxOrder.first['mo'] as int) + 1,
        });
        AppState.notify();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('分类「${result['name']}」添加成功')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('添加分类失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _renameBook(int id, String oldName) async {
    final ctrl = TextEditingController(text: oldName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '新名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('名称不能为空')),
                );
                return;
              }
              Navigator.pop(ctx, text);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty) {
      try {
        final db = await DatabaseHelper.database;
        await db.update(
          'account_books',
          {'name': name},
          where: 'id=?',
          whereArgs: [id],
        );
        AppState.notify();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('重命名失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteBook(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账本'),
        content: const Text('该账本下的所有记录将一并删除，确定吗？'),
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
          'account_books',
          where: 'id=?',
          whereArgs: [id],
        );
        AppState.notify();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('账本已删除')),
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

  Future<void> _setReminderTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time != null) {
      await NotificationService.scheduleDailyReminder(
        hour: time.hour,
        minute: time.minute,
      );
      setState(() {
        _reminderHour = time.hour;
        _reminderMinute = time.minute;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('提醒时间已设为 ${time.hour}:${time.minute.toString().padLeft(2, '0')}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('账本管理', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._books.map((b) => Card(
            child: ListTile(
              title: Text(b['name'] as String),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _renameBook(b['id'] as int, b['name'] as String)),
                if (_books.length > 1)
                  IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _deleteBook(b['id'] as int)),
              ]),
            ),
          )),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新建账本'),
            onTap: _addBook,
          ),
          const Divider(height: 32),
          Text('支出分类', style: Theme.of(context).textTheme.titleMedium),
          ..._expenseCats.map((c) => ListTile(
            dense: true,
            leading: const Icon(Icons.label, size: 20),
            title: Text(c['name'] as String),
          )),
          ListTile(
            leading: const Icon(Icons.add, size: 20),
            title: const Text('添加分类'),
            onTap: () => _addCategory('expense'),
          ),
          const Divider(height: 32),
          Text('收入分类', style: Theme.of(context).textTheme.titleMedium),
          ..._incomeCats.map((c) => ListTile(
            dense: true,
            leading: const Icon(Icons.label, size: 20),
            title: Text(c['name'] as String),
          )),
          ListTile(
            leading: const Icon(Icons.add, size: 20),
            title: const Text('添加分类'),
            onTap: () => _addCategory('income'),
          ),
          const Divider(height: 32),
          // ---- 通知设置 ----
          Text('🔔 通知设置', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('每日记账提醒'),
            subtitle: Text(
              '$_reminderHour:${_reminderMinute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 14),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _setReminderTime,
          ),
          const Divider(height: 32),
          Text('关于', style: Theme.of(context).textTheme.titleMedium),
          const ListTile(
            title: Text('记账助手 v1.1'),
            subtitle: Text('纯本地记账 · 智能解析 · 语音录入 · 完全离线'),
          ),
        ],
      ),
    );
  }
}
