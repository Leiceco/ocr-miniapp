import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';

/// 导入结果统计
class ImportResult {
  int success;   // 成功导入条数
  int skipped;   // 跳过条数（重复）
  int newBooks;  // 自动创建账本数
  List<String> errors;

  ImportResult({
    this.success = 0,
    this.skipped = 0,
    this.newBooks = 0,
  }) : errors = [];

  String summary() {
    final parts = <String>[
      if (success > 0) '成功导入 $success 条',
      if (skipped > 0) '跳过 $skipped 条重复',
      if (newBooks > 0) '新建 $newBooks 个账本',
      if (errors.isNotEmpty) '${errors.length} 条格式错误',
    ];
    return parts.isEmpty ? '无数据导入' : parts.join('，');
  }
}

class ImportService {
  /// 必填列名
  static const requiredHeaders = [
    '账本名称',
    '日期',
    '类型',
    '分类',
    '金额',
  ];

  /// 可选列名
  static const optionalHeaders = ['备注'];

  /// 所有列（用于模板生成）
  static const allHeaders = [
    '账本名称',
    '日期',
    '类型',
    '分类',
    '金额',
    '备注',
  ];

  /// 示例数据（用于模板说明）
  static const sampleRow = [
    '日常账本',
    '2026-06-20',
    '支出',
    '餐饮',
    '35.50',
    '午餐',
  ];

  /// 下载导入模板 —— 生成仅含表头 + 示例的 Excel 并分享
  static Future<void> downloadTemplate() async {
    final workbook = Excel.createExcel();
    final sheet = workbook.sheets[workbook.getDefaultSheet()]!;

    // 表头样式
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#2196F3'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );

    // 写入表头
    for (int i = 0; i < allHeaders.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(allHeaders[i]);
      cell.cellStyle = headerStyle;
    }

    // 写入示例行
    for (int i = 0; i < sampleRow.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1));
      cell.value = TextCellValue(sampleRow[i]);
    }

    // 列宽
    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 14);
    sheet.setColumnWidth(2, 8);
    sheet.setColumnWidth(3, 10);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 20);

    // 保存
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/导入模板.xlsx';
    final bytes = workbook.encode();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }

    // 分享
    await Share.shareXFiles(
      [XFile(filePath)],
      text: '账单导入模板 - 请按表头填写数据',
    );
  }

  /// 解析并导入 Excel 文件
  static Future<ImportResult> importFromFile({
    required String filePath,
    bool skipDuplicates = true, // true=跳过重复, false=覆盖更新
  }) async {
    final result = ImportResult();

    final file = File(filePath);
    if (!file.existsSync()) {
      result.errors.add('文件不存在: $filePath');
      return result;
    }

    // 解析 Excel
    final bytes = file.readAsBytesSync();
    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook.sheets[workbook.getDefaultSheet()];
    if (sheet == null) {
      result.errors.add('Excel 文件中未找到工作表');
      return result;
    }

    // 读取所有行
    final rows = <List<String?>>[];
    for (int r = 0; r < sheet.maxRows; r++) {
      final row = <String?>[];
      bool hasAny = false;
      for (int c = 0; c < allHeaders.length; c++) {
        final cellValue =
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final val = _cellString(cellValue);
        row.add(val);
        if (val.isNotEmpty) hasAny = true;
      }
      if (hasAny) rows.add(row);
    }

    if (rows.isEmpty) {
      result.errors.add('Excel 文件中无数据');
      return result;
    }

    // 第一行应为表头
    final headerRow = rows.first;
    final colMap = _buildColumnMap(headerRow);

    // 校验必填列
    final missing = requiredHeaders.where((h) => !colMap.containsKey(h)).toList();
    if (missing.isNotEmpty) {
      result.errors.add('缺少必填列: ${missing.join('、')}。'
          '当前表头: ${headerRow.where((h) => h != null && h!.isNotEmpty).join('、')}');
      return result;
    }

    final db = await DatabaseHelper.database;

    // 缓存：账本名称 → id
    final bookCache = <String, int>{};
    final existingBooks = await db.query('account_books');
    for (final b in existingBooks) {
      bookCache[b['name'] as String] = b['id'] as int;
    }

    // 缓存：分类名称 → id（支出/收入分开）
    final catCache = <String, int>{};
    final existingCats = await db.query('categories');
    for (final c in existingCats) {
      // key: "name|type" 确保分类+类型唯一
      catCache['${c['name']}|${c['type']}'] = c['id'] as int;
    }

    final fmt = NumberFormat('#,##0.00');

    // 逐行解析（跳过表头行）
    for (int i = 1; i < rows.length; i++) {
      try {
        final row = rows[i];

        // 提取字段
        final bookName = _get(row, colMap['账本名称']);
        final dateStr = _get(row, colMap['日期']);
        final typeStr = _get(row, colMap['类型']);
        final catName = _get(row, colMap['分类']);
        final amountStr = _get(row, colMap['金额']);
        final note = _get(row, colMap['备注']);

        // 校验必填
        if (bookName.isEmpty || dateStr.isEmpty || typeStr.isEmpty ||
            catName.isEmpty || amountStr.isEmpty) {
          result.errors.add('第 ${i + 1} 行: 必填字段缺失，已跳过');
          continue;
        }

        // 校验类型
        final type = typeStr == '支出'
            ? 'expense'
            : typeStr == '收入'
                ? 'income'
                : null;
        if (type == null) {
          result.errors.add('第 ${i + 1} 行: 类型必须为"支出"或"收入"，实际为"$typeStr"');
          continue;
        }

        // 校验金额
        final amount = double.tryParse(amountStr);
        if (amount == null || amount <= 0) {
          result.errors.add('第 ${i + 1} 行: 金额无效 "$amountStr"');
          continue;
        }

        // 校验日期
        DateTime? date;
        for (final pattern in ['yyyy-MM-dd', 'yyyy/MM/dd', 'yyyy.MM.dd']) {
          try {
            date = DateFormat(pattern).parseStrict(dateStr);
            break;
          } catch (_) {}
        }
        if (date == null) {
          result.errors.add('第 ${i + 1} 行: 日期格式无效 "$dateStr"，请使用 yyyy-MM-dd');
          continue;
        }

        // 获取/创建账本
        int bookId;
        if (bookCache.containsKey(bookName)) {
          bookId = bookCache[bookName]!;
        } else {
          bookId = await db.insert('account_books', {
            'name': bookName,
            'description': '导入自动创建',
            'created_at': DateTime.now().toIso8601String(),
          });
          bookCache[bookName] = bookId;
          result.newBooks++;
        }

        // 获取/匹配分类
        final catKey = '$catName|$type';
        int categoryId;
        if (catCache.containsKey(catKey)) {
          categoryId = catCache[catKey]!;
        } else {
          // 分类不存在则自动创建
          final maxOrder = await db.rawQuery(
            'SELECT COALESCE(MAX(sort_order), -1) as mo FROM categories WHERE type=?',
            [type],
          );
          categoryId = await db.insert('categories', {
            'name': catName,
            'icon': 'more_horiz',
            'type': type,
            'sort_order': (maxOrder.first['mo'] as int) + 1,
          });
          catCache[catKey] = categoryId;
        }

        final isoDate = date.toIso8601String();

        // 去重检查
        final existing = await db.rawQuery(
          '''SELECT id FROM transactions
             WHERE book_id=? AND date=? AND type=? AND category_id=? AND amount=?
             LIMIT 1''',
          [bookId, isoDate, type, categoryId, amount],
        );

        if (existing.isNotEmpty) {
          if (skipDuplicates) {
            result.skipped++;
            continue;
          } else {
            // 覆盖更新：更新备注
            await db.update(
              'transactions',
              {'note': note},
              where: 'id=?',
              whereArgs: [existing.first['id']],
            );
            result.success++;
            continue;
          }
        }

        // 插入新记录
        await db.insert('transactions', {
          'book_id': bookId,
          'category_id': categoryId,
          'amount': amount,
          'type': type,
          'note': note,
          'date': isoDate,
          'created_at': DateTime.now().toIso8601String(),
        });
        result.success++;
      } catch (e) {
        result.errors.add('第 ${i + 1} 行: 解析异常 - $e');
      }
    }

    return result;
  }

  /// 从表头行构建列名→列索引的映射
  static Map<String, int> _buildColumnMap(List<String?> headerRow) {
    final map = <String, int>{};
    for (int i = 0; i < headerRow.length; i++) {
      final h = (headerRow[i] ?? '').trim();
      if (h.isNotEmpty) map[h] = i;
    }
    return map;
  }

  /// 安全取行中某列的值
  static String _get(List<String?> row, int? colIdx) {
    if (colIdx == null || colIdx >= row.length) return '';
    return (row[colIdx] ?? '').trim();
  }

  /// 将单元格内容转为纯文本字符串
  static String _cellString(dynamic cell) {
    try {
      final value = cell.value;
      if (value == null) return '';
      return value.toString().trim();
    } catch (_) {
      return '';
    }
  }
}
