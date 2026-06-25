class Budget {
  final int? id;
  final int bookId;
  final int? categoryId; // null = 总预算
  final double amount;
  final String period; // 'monthly' or 'yearly'

  Budget({
    this.id,
    required this.bookId,
    this.categoryId,
    required this.amount,
    required this.period,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'category_id': categoryId,
      'amount': amount,
      'period': period,
    };
  }

  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      categoryId: map['category_id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      period: map['period'] as String,
    );
  }
}
