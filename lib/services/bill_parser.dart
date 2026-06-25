import 'package:shared_preferences/shared_preferences.dart';

/// 解析结果
class ParsedBill {
  double? amount;         // 提取的金额
  String? type;           // 'expense' | 'income'
  String? categoryHint;   // 分类关键词匹配结果
  String? note;           // 备注（去掉金额和关键词后的剩余文本）

  bool get isValid => amount != null && amount! > 0;
}

/// 基于规则引擎的账单文本解析器
/// 完全本地运行，不调用任何云端 API
class BillParser {
  // ---- 内置分类关键词库 ----
  static const Map<String, List<String>> _categoryKeywords = {
    '餐饮': ['吃饭', '食堂', '午餐', '晚饭', '早餐', '外卖', '聚餐', '火锅', '烧烤', '麻辣烫', '面', '饭', '餐厅', '小吃', '奶茶', '咖啡', '饮料'],
    '交通': ['打车', '滴滴', '地铁', '公交', '高铁', '火车', '机票', '加油', '停车', '过路费', '单车', '骑行', '出租车'],
    '购物': ['买', '淘宝', '京东', '拼多多', '衣服', '鞋子', '超市', '便利店', '日用品', '网购', '代购'],
    '娱乐': ['电影', 'KTV', '游戏', '旅游', '门票', '景区', '演唱会', '剧本杀', '密室', '按摩'],
    '居住': ['房租', '房贷', '物业', '水电', '燃气', '宽带', '取暖', '维修'],
    '通讯': ['话费', '流量', '手机', '网费'],
    '医疗': ['医院', '药', '挂号', '体检', '诊所', '牙科', '看病'],
    '教育': ['学费', '培训', '书', '课程', '考试', '报名'],
    '人情': ['红包', '礼物', '请客', '结婚', '生日', '随礼', '礼金'],
    '工资': ['工资', '薪水', '奖金', '年终奖', '提成'],
    '理财': ['理财', '股票', '基金', '利息', '分红', '收益', '投资'],
    '兼职': ['兼职', '副业', '稿费', '外快', '接单'],
    '退款': ['退款', '退货', '报销', '返现', '补贴'],
  };

  /// 收入关键词（命中则判定为收入）
  static const _incomeKeywords = [
    '工资', '薪水', '奖金', '年终奖', '提成', '理财', '股票', '基金',
    '利息', '分红', '收益', '投资', '兼职', '副业', '稿费', '外快',
    '退款', '退货', '报销', '返现', '补贴', '红包收入', '收红包',
  ];

  /// 解析文本：提取金额、判断类型、匹配分类
  static ParsedBill parse(String text) {
    final result = ParsedBill();

    if (text.trim().isEmpty) return result;

    // 1. 提取金额
    result.amount = _extractAmount(text);

    // 2. 判断类型
    result.type = _detectType(text);

    // 3. 匹配分类
    result.categoryHint = _matchCategory(text, result.type);

    // 4. 生成备注（清理后的原文）
    result.note = text.trim();

    return result;
  }

  /// 未来可扩展：从 SharedPreferences 加载用户自定义关键词
  static Future<Map<String, List<String>>> loadCustomKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, List<String>>{};
    for (final cat in _categoryKeywords.keys) {
      final stored = prefs.getStringList('kw_$cat');
      if (stored != null && stored.isNotEmpty) {
        result[cat] = stored;
      }
    }
    return result;
  }

  /// 保存用户自定义关键词
  static Future<void> saveCustomKeywords(
      Map<String, List<String>> keywords) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in keywords.entries) {
      await prefs.setStringList('kw_${entry.key}', entry.value);
    }
  }

  /// 获取合并后的分类关键词（内置 + 用户自定义）
  static Future<Map<String, List<String>>> getMergedKeywords() async {
    final custom = await loadCustomKeywords();
    final merged = <String, List<String>>{};
    for (final cat in _categoryKeywords.keys) {
      final builtIn = List<String>.from(_categoryKeywords[cat]!);
      if (custom.containsKey(cat)) {
        builtIn.addAll(custom[cat]!);
      }
      merged[cat] = builtIn;
    }
    return merged;
  }

  // -------- 内部实现 --------

  /// 从文本中提取金额（支持多种格式）
  static double? _extractAmount(String text) {
    // 匹配: 123.45元, ¥123.45, 123元, 123.45, -123.45
    final patterns = [
      RegExp(r'(\d+(?:\.\d{1,2})?)\s*[元块]'),
      RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)'),
      RegExp(r'(\d+(?:\.\d{1,2})?)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final val = double.tryParse(match.group(1)!);
        if (val != null && val > 0 && val < 100000000) {
          return val;
        }
      }
    }
    return null;
  }

  /// 判断收入还是支出
  static String _detectType(String text) {
    for (final kw in _incomeKeywords) {
      if (text.contains(kw)) return 'income';
    }
    return 'expense'; // 默认支出
  }

  /// 匹配分类关键词
  static String? _matchCategory(String text, String? type) {
    String? bestMatch;
    int bestLen = 0;

    for (final entry in _categoryKeywords.entries) {
      // 收入类型只匹配收入分类
      if (type == 'income') {
        if (!['工资', '兼职', '理财', '退款'].contains(entry.key)) continue;
      } else {
        if (['工资', '兼职', '理财', '退款'].contains(entry.key)) continue;
      }

      for (final kw in entry.value) {
        if (text.contains(kw) && kw.length > bestLen) {
          bestMatch = entry.key;
          bestLen = kw.length;
        }
      }
    }
    return bestMatch;
  }
}
