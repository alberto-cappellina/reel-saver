import 'package:flutter_test/flutter_test.dart';

import 'package:ig_saver/main.dart';

void main() {
  testWidgets('La schermata mostra il titolo e il pulsante di download',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ReelSaverApp());

    expect(find.text('Reel Saver'), findsWidgets);
    expect(find.text('Scarica e salva'), findsOneWidget);
  });
}
