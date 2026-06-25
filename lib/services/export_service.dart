import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';

class ExportService {
  /// 导出指定账本的全部交易记录为 Excel 文件并分享
  static Future<String?> exportToExcel({
    required int bookId,
    String? bookName,
  }) async {
    final db = await DatabaseHelper.database;

    // 查询账本名称
    String name = bookName ?? '';
    if (name.isEmpty) {
      final books = await db.query(
        'account_books',
        where: 'id=?',
        whereArgs: [bookId],
      );
      if (books.isNotEmpty) {
        name = books.first['name'] as String;
      }
    }

    // 查询该账本下所有交易（按日期降序）
    final transactions = await db.rawQuery(
      '''SELECT t.date, t.type, c.name as cat_name, t.amount, t.note
         FROM transactions t
         JOIN categories c ON t.category_id = c.id
         WHERE t.book_id = ?
         ORDER BY t.date DESC, t.id DESC''',
      [bookId],
    );

    if (transactions.isEmpty) {
      return null; // 无数据可导出
    }

    // 创建工作簿
    final workbook = Excel.createExcel();
    final sheet = workbook.sheets[workbook.getDefaultSheet()]!;

    // 表头样式
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#4CAF50'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
      topBorder: Border(borderStyle: BorderStyle.Thin),
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
      leftBorder: Border(borderStyle: BorderStyle.Thin),
      rightBorder: Border(borderStyle: BorderStyle.Thin),
    );

    final dataStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Center,
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
      leftBorder: Border(borderStyle: BorderStyle.Thin),
      rightBorder: Border(borderStyle: BorderStyle.Thin),
    );

    final amountStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Right,
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
      leftBorder: Border(borderStyle: BorderStyle.Thin),
      rightBorder: Border(borderStyle: BorderStyle.Thin),
    );

    // 标题行（合并 A1–E1）
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('E1'));
    final titleCell = sheet.cell(CellIndex.indexByString('A1'));
    titleCell.value = TextCellValue('$name - 账单明细');
    titleCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
    );
    sheet.setRowHeight(0, 30);

    // 表头行
    const headers = ['日期', '类型', '分类', '金额 (元)', '备注'];
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }
    sheet.setRowHeight(1, 24);

    // 数据行
    final fmt = NumberFormat('#,##0.00');
    for (int r = 0; r < transactions.length; r++) {
      final t = transactions[r];
      final row = r + 2; // 从第3行开始

      // 日期（只取日期部分）
      final dateStr = (t['date'] as String).substring(0, 10);
      _setCell(sheet, row, 0, dateStr, dataStyle);

      // 类型
      final typeStr = t['type'] == 'expense' ? '支出' : '收入';
      _setCell(sheet, row, 1, typeStr, dataStyle);

      // 分类
      _setCell(sheet, row, 2, t['cat_name'] as String, dataStyle);

      // 金额（右对齐）
      _setCell(sheet, row, 3, fmt.format(t['amount']), amountStyle);

      // 备注
      final note = (t['note'] as String?) ?? '';
      _setCell(sheet, row, 4, note.isNotEmpty ? note : '', dataStyle);
    }

    // 设置列宽
    sheet.setColumnWidth(0, 14); // 日期
    sheet.setColumnWidth(1, 8);  // 类型
    sheet.setColumnWidth(2, 10); // 分类
    sheet.setColumnWidth(3, 14); // 金额
    sheet.setColumnWidth(4, 20); // 备注

    // 保存到临时目录
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${dir.path}/$safeName-$timestamp.xlsx';
    final bytes = workbook.encode();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }

    // 调起系统分享
    await Share.shareXFiles(
      [XFile(filePath)],
      text: '$name 账单明细',
    );

    return filePath;
  }

  static void _setCell(
    Sheet sheet,
    int row,
    int col,
    String value,
    CellStyle style,
  ) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(
      columnIndex: col,
      rowIndex: row,
    ));
    cell.value = TextCellValue(value);
    cell.cellStyle = style;
  }
}
