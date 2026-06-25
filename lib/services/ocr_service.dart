import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  TextRecognizer? _recognizer;

  TextRecognizer get _getRecognizer {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _recognizer!;
  }

  Future<OCRBillResult> extractBillInfo(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizer = _getRecognizer;
    final RecognizedText result;
    try {
      result = await recognizer.processImage(inputImage);
    } catch (e) {
      throw OCRException('图片识别失败: $e');
    }
    final allText = <String>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        allText.add(line.text);
      }
    }
    final fullText = allText.join('\n');
    return OCRBillResult(
      amount: _extractAmount(fullText),
      merchant: _extractMerchant(allText),
      fullText: fullText,
    );
  }

  double? _extractAmount(String text) {
    final moneyPattern = RegExp(r'[¥￥]\s*(\d+\.?\d{0,2})');
    final matches = moneyPattern.allMatches(text);
    if (matches.isNotEmpty) {
      final amounts = matches
          .map((m) => double.tryParse(m.group(1)!))
          .where((d) => d != null)
          .cast<double>()
          .toList();
      if (amounts.isNotEmpty) {
        amounts.sort((a, b) => b.compareTo(a));
        return amounts.first;
      }
    }
    final totalPattern =
        RegExp(r'(合计|总计|金额|实付|应付)[：:\s]*(\d+\.?\d{0,2})');
    final totalMatch = totalPattern.firstMatch(text);
    if (totalMatch != null) return double.tryParse(totalMatch.group(2)!);
    return null;
  }

  String? _extractMerchant(List<String> lines) {
    if (lines.isEmpty) return null;
    final candidates = lines.take(3).where((l) => l.trim().isNotEmpty);
    for (final line in candidates) {
      final cleaned = line.trim();
      if (cleaned.length >= 2 &&
          cleaned.length <= 20 &&
          !RegExp(r'^\d+$').hasMatch(cleaned) &&
          !RegExp(r'^(合计|总计|小票|发票|订单)').hasMatch(cleaned)) {
        return cleaned;
      }
    }
    return null;
  }

  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}

class OCRException implements Exception {
  final String message;
  OCRException(this.message);
  @override
  String toString() => 'OCRException: $message';
}

class OCRBillResult {
  final double? amount;
  final String? merchant;
  final String fullText;
  OCRBillResult({this.amount, this.merchant, required this.fullText});
}
