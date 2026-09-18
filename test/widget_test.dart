import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/src/app.dart';

void main() {
  testWidgets('shows Nexus recommended execution defaults', (tester) async {
    await tester.pumpWidget(const NexusApp());

    expect(find.text('Nexus'), findsWidgets);
    expect(find.text('PC Local Model'), findsOneWidget);
    expect(find.text('GitHub Actions'), findsOneWidget);
    expect(find.text('Autonomous'), findsOneWidget);
  });
}
