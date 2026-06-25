import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../database/database_helper.dart';
import '../services/ocr_service.dart';
import '../utils/app_state.dart';

class AddTransactionPage extends StatefulWidget {
  const AddTransactionPage({super.key});
  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _picker = ImagePicker();
  final _ocr = OCRService();

  String _type = 'expense';
  int _bookId = 1;
  int _categoryId = 1;
  DateTime _date = DateTime.now();
  File? _imageFile;
  bool _processing = false;

  List<Map<String, dynamic>> _expenseCategories = [];
  List<Map<String, dynamic>> _incomeCategories = [];
  List<Map<String, dynamic>> _books = [];

  @override
  void initState() {
    super.initState();
    AppState.addListener(_loadMeta);
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final db = await DatabaseHelper.database;
    final ec = await db.query('categories',
        where: 'type=?', whereArgs: ['expense'], orderBy: 'sort_order');
    final ic = await db.query('categories',
        where: 'type=?', whereArgs: ['income'], orderBy: 'sort_order');
    final books = await db.query('account_books');
    if (mounted) {
      setState(() {
        _expenseCategories = ec;
        _incomeCategories = ic;
        _books = books;
        if (_expenseCategories.isNotEmpty) {
          _categoryId = _expenseCategories.first['id'] as int;
        }
        // 动态获取第一个账本 ID，避免硬编码 1
        if (_books.isNotEmpty) _bookId = _books.first['id'] as int;
      });
    }
  }

  Future<void> _pickCamera() async {
    try {
      final img = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1920);
      if (img != null) {
        setState(() => _imageFile = File(img.path));
        _ocrBill();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开相机: $e')),
        );
      }
    }
  }

  Future<void> _pickGallery() async {
    try {
      final img = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1920);
      if (img != null) {
        setState(() => _imageFile = File(img.path));
        _ocrBill();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开相册: $e')),
        );
      }
    }
  }

  Future<void> _ocrBill() async {
    if (_imageFile == null) return;
    setState(() => _processing = true);
    try {
      final result = await _ocr.extractBillInfo(_imageFile!);
      if (result.amount != null) {
        _amountCtrl.text = result.amount!.toStringAsFixed(2);
      }
      if (result.merchant != null) {
        _noteCtrl.text = result.merchant!;
      }
    } on OCRException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('识别失败: $e')),
        );
      }
    }
    if (mounted) setState(() => _processing = false);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请输入有效金额')));
      }
      return;
    }

    final catList = _type == 'expense' ? _expenseCategories : _incomeCategories;
    if (catList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('分类数据未就绪，请稍后重试')));
      }
      _loadMeta();
      return;
    }

    final cat = catList.firstWhere(
        (c) => c['id'] == _categoryId,
        orElse: () => catList.first);

    try {
      final db = await DatabaseHelper.database;
      await db.insert('transactions', {
        'book_id': _bookId,
        'category_id': cat['id'],
        'amount': amount,
        'type': _type,
        'note': _noteCtrl.text,
        'date': _date.toIso8601String(),
        'ocr_image_path': _imageFile?.path ?? '',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('记录成功'), duration: Duration(seconds: 1)));
        _amountCtrl.clear();
        _noteCtrl.clear();
        // 重置分类到当前类型的第一个
        setState(() {
          _imageFile = null;
          if (catList.isNotEmpty) _categoryId = catList.first['id'] as int;
        });
        // 通知其他页面刷新
        AppState.notify();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = _type == 'expense' ? _expenseCategories : _incomeCategories;
    return Scaffold(
      appBar: AppBar(title: const Text('记一笔')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 类型切换
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('支出')),
                ButtonSegment(value: 'income', label: Text('收入')),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() {
                _type = v.first;
                if (cats.isNotEmpty) _categoryId = cats.first['id'] as int;
              }),
            ),
            const SizedBox(height: 16),
            // 账本选择
            InputDecorator(
              decoration: const InputDecoration(labelText: '账本', border: OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _books.any((b) => b['id'] == _bookId) ? _bookId : null,
                  isExpanded: true,
                  isDense: true,
                  items: _books.map((b) => DropdownMenuItem(
                      value: b['id'] as int, child: Text(b['name'] as String))).toList(),
                  onChanged: (v) => setState(() => _bookId = v!),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 金额
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '金额',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // 分类
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cats.map((c) => ChoiceChip(
                label: Text(c['name'] as String),
                selected: _categoryId == (c['id'] as int),
                onSelected: (_) => setState(() => _categoryId = c['id'] as int),
              )).toList(),
            ),
            const SizedBox(height: 12),
            // 日期
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: '日期', border: OutlineInputBorder()),
                child: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
              ),
            ),
            const SizedBox(height: 12),
            // 备注
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: '备注', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            // 拍照OCR
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('拍照识别'),
                    onPressed: _pickCamera,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('相册选择'),
                    onPressed: _pickGallery,
                  ),
                ),
              ],
            ),
            if (_imageFile != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _processing
                    ? const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()))
                    : Image.file(_imageFile!, height: 200, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('保存记录'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    AppState.removeListener(_loadMeta);
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _ocr.dispose();
    super.dispose();
  }
}
