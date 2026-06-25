class Category {
  final int? id;
  final String name;
  final String icon; // Material Icons name
  final String type; // 'income' or 'expense'
  final int sortOrder;

  Category({
    this.id,
    required this.name,
    required this.icon,
    required this.type,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'icon': icon,
      'type': type,
      'sort_order': sortOrder,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      icon: map['icon'] as String,
      type: map['type'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}
