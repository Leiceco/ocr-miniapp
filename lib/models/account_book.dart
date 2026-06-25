class AccountBook {
  final int? id;
  final String name;
  final String? description;
  final String createdAt;

  AccountBook({
    this.id,
    required this.name,
    this.description,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description ?? '',
      'created_at': createdAt,
    };
  }

  factory AccountBook.fromMap(Map<String, dynamic> map) {
    return AccountBook(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: (map['description'] as String?)?.isEmpty == true
          ? null
          : map['description'] as String?,
      createdAt: map['created_at'] as String?,
    );
  }
}
