import 'package:flutter_test/flutter_test.dart';

import 'package:dayby/main.dart';

void main() {
  testWidgets('app renders', (tester) async {
    await tester.pumpWidget(const DaybyApp());
    expect(find.text('Dayby'), findsWidgets);
  });
}
