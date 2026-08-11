import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/app.dart';

void main() {
  testWidgets('App launches and shows home', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pumpAndSettle();

    expect(find.text('南方科技大学附属医院（校本部）'), findsOneWidget);
  });
}
