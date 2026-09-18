import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/src/app.dart';

void main() {
  testWidgets('shows Nexus hybrid execution defaults', (tester) async {
    await tester.pumpWidget(const NexusApp());

    expect(find.text('Nexus'), findsWidgets);
    expect(find.text('PC Local Model'), findsOneWidget);
    expect(
      find.text(
        'Automatic Build · Local-first · Autonomous · Auto Fix · Automatic Sync',
      ),
      findsOneWidget,
    );
    expect(find.text('Autonomous'), findsOneWidget);
  });
}
