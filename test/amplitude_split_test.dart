/// The stepper remounts the split on every step change, and the value it
/// reports is what the next insert records. An equal split reported on
/// remount would file a configuration that was never programmed.
library;

import 'package:dbs_annotator/ui/amplitude_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<List<double>> reported;

  Future<void> pump(
    WidgetTester tester, {
    List<String> cathodes = const ['2b', '2c'],
    List<double> initial = const [],
    Key? key,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AmplitudeSplit(
            key: key,
            cathodes: cathodes,
            total: 5,
            decimals: 1,
            initial: initial,
            onChanged: reported.add,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String pct(WidgetTester tester, int i) => tester
      .widgetList<TextField>(find.byType(TextField))
      .elementAt(i)
      .controller!
      .text;

  setUp(() => reported = []);

  testWidgets('a stored split is shown and reported unchanged', (tester) async {
    await pump(tester, initial: const [70, 30]);
    expect(pct(tester, 0), '70');
    expect(pct(tester, 1), '30');
    expect(reported, [
      [70.0, 30.0],
    ]);
    expect(find.text('→ 3.5 mA'), findsOneWidget);
  });

  testWidgets('a remount, as a step change does, keeps the split', (
    tester,
  ) async {
    await pump(tester, initial: const [70, 30], key: const ValueKey(1));
    await pump(tester, initial: reported.last, key: const ValueKey(2));
    expect(pct(tester, 0), '70');
    expect(reported.every((p) => p[0] == 70), isTrue);
  });

  testWidgets('a new cathode set starts from an equal split', (tester) async {
    await pump(tester, initial: const [70, 30]);
    await pump(tester, cathodes: const ['2a', '2b'], initial: const [70, 30]);
    expect(pct(tester, 0), '50');
    expect(reported.last, [50.0, 50.0]);
  });

  testWidgets('a split that does not fit the cathodes is ignored', (
    tester,
  ) async {
    await pump(
      tester,
      cathodes: const ['2a', '2b', '2c'],
      initial: const [70, 30],
    );
    expect(reported.last.length, 3);
    expect(reported.last.fold(0.0, (a, b) => a + b), closeTo(100, 1e-9));
  });
}
