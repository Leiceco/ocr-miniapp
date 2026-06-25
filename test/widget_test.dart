import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_app/main.dart';

void main() {
  testWidgets('App renders navigation bar with destinations', (WidgetTester tester) async {
    await tester.pumpWidget(const ExpenseApp());

    // 导航栏选中标签（index 0 = 首页）
    expect(find.text('首页'), findsOneWidget);

    // 导航栏图标始终存在
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.pie_chart_outline), findsOneWidget);
    expect(find.byIcon(Icons.savings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // Material3 NavigationBar 存在
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
