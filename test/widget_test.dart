import 'package:flutter_test/flutter_test.dart';

import 'package:pin_and_paper_sketchpad/main.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SketchpadApp());
    expect(find.textContaining('Sketchpad'), findsOneWidget);
  });
}
