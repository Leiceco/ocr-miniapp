class Transaction {
  final int? id;
  final int bookId;
  final int categoryId;
  final double amount;
  final String type; // 'income' or 'expense'
  final String? note;
  final String date; // yyyy-MM-dd
  final String? ocrImagePath;
  final String createdAt;

  Transaction({
    this.id,
    required this.bookId,
    required this.categoryId,
    required this.amount,
    required this.type,
    this.note,
    required this.date,
    this.ocrImagePath,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'category_id': categoryId,
      'amount': amount,
      'type': type,
      'note': note ?? '',
      'date': date,
      'ocr_image_path': ocrImagePath ?? '',
      'created_at': createdAt,
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      categoryId: map['category_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      note: (map['note'] as String?)?.isEmpty == true ? null : map['note'] as String?,
      date: map['date'] as String,
      ocrImagePath: (map['ocr_image_path'] as String?)?.isEmpty == true
          ? null
          : map['ocr_image_path'] as String?,
      createdAt: map['created_at'] as String?,
    );
  }

  Transaction copyWith({
    int? id,
    int? bookId,
    int? categoryId,
    double? amount,
    String? type,
    String? note,
    String? date,
    String? ocrImagePath,
  }) {
    return Transaction(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      note: note ?? this.note,
      date: date ?? this.date,
      ocrImagePath: ocrImagePath ?? this.ocrImagePath,
      createdAt: createdAt,
    );
  }
}
