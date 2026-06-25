import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  DatabaseHelper._(); // 防止实例化
  static Database? _db;
  static const _dbName = 'expense_tracker.db';
  static const _version = 2; // 初始发布版本，非升级版本

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE account_books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('income','expense')),
        sort_order INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('income','expense')),
        note TEXT DEFAULT '',
        date TEXT NOT NULL,
        ocr_image_path TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (book_id) REFERENCES account_books(id) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        category_id INTEGER,
        amount REAL NOT NULL,
        period TEXT NOT NULL CHECK(period IN ('monthly','yearly')),
        FOREIGN KEY (book_id) REFERENCES account_books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_transactions_date ON transactions(date)');
    await db.execute(
        'CREATE INDEX idx_transactions_book ON transactions(book_id)');
    await db.execute(
        'CREATE INDEX idx_budgets_book ON budgets(book_id)');

    // 默认账本
    await db.insert('account_books', {
      'name': '日常账本',
      'description': '默认账本',
      'created_at': DateTime.now().toIso8601String(),
    });

    // 预设分类
    final expenseCategories = [
      ['餐饮', 'fastfood'],
      ['交通', 'directions_car'],
      ['购物', 'shopping_bag'],
      ['娱乐', 'movie'],
      ['居住', 'home'],
      ['通讯', 'phone'],
      ['医疗', 'local_hospital'],
      ['教育', 'school'],
      ['人情', 'people'],
      ['其他', 'more_horiz'],
    ];

    for (int i = 0; i < expenseCategories.length; i++) {
      await db.insert('categories', {
        'name': expenseCategories[i][0],
        'icon': expenseCategories[i][1],
        'type': 'expense',
        'sort_order': i,
      });
    }

    final incomeCategories = [
      ['工资', 'work'],
      ['兼职', 'handyman'],
      ['理财', 'trending_up'],
      ['退款', 'undo'],
      ['其他', 'more_horiz'],
    ];

    for (int i = 0; i < incomeCategories.length; i++) {
      await db.insert('categories', {
        'name': incomeCategories[i][0],
        'icon': incomeCategories[i][1],
        'type': 'income',
        'sort_order': i,
      });
    }
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // v1 → v2: 初始发布前的开发版本，可安全重建 schema
    if (oldV < 2) {
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE IF EXISTS transactions');
      await db.execute('DROP TABLE IF EXISTS budgets');
      await db.execute('DROP TABLE IF EXISTS categories');
      await db.execute('DROP TABLE IF EXISTS account_books');
      await db.execute('PRAGMA foreign_keys = ON');
      await _onCreate(db, newV);
    }
    // 后续版本迁移：在此添加 else if (oldV < 3) { ... } 分支
  }
}
