import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/ui/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('combinedScaleTimeline', () {
    test('offsets each file onto a sequential block axis', () {
      const fileA = [
        SessionRow(blockId: '0', scaleName: 'Mood', scaleValue: '3'),
        SessionRow(blockId: '1', scaleName: 'Mood', scaleValue: '4'),
      ];
      const fileB = [
        SessionRow(blockId: '0', scaleName: 'Mood', scaleValue: '2'),
        SessionRow(blockId: '0', scaleName: 'Anxiety', scaleValue: '5'),
      ];
      expect(combinedScaleTimeline(const [fileA, fileB]), {
        'Mood': {0: 3.0, 1: 4.0, 2: 2.0},
        'Anxiety': {2: 5.0},
      });
    });

    test('single file is identical to its own timeline; empty input is {}', () {
      const rows = [
        SessionRow(blockId: '0', scaleName: 'Mood', scaleValue: '3'),
      ];
      expect(combinedScaleTimeline(const [rows]), {
        'Mood': {0: 3.0},
      });
      expect(combinedScaleTimeline(const []), isEmpty);
    });
  });

  testWidgets('with nothing uploaded, every action is offered but disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await tester.pump();

    expect(find.text('Upload TSVs'), findsOneWidget);
    expect(find.text('No files uploaded.'), findsOneWidget);
    // Listed rather than hidden, so what the screen can do is visible before
    // anything is uploaded, with the reason it cannot do it yet.
    for (final label in const [
      'Single session report',
      'Longitudinal report',
      'Combined table (TSV)',
      'BIDS dataset (zip)',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Upload a TSV first.'), findsNWidgets(4));
    for (final button in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      expect(button.onPressed, isNull, reason: 'nothing is tappable yet');
    }
  });
}
