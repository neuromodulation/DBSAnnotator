import 'dart:io';

import 'package:dbs_annotator/report/upload_actions.dart';
import 'package:dbs_annotator/ui/reports_screen.dart';
import 'package:dbs_annotator/ui/scales_chart_painter.dart';
import 'package:dbs_annotator/ui/session/entries_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      'Create a BIDS dataset (zip)',
      'Add to an existing dataset',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Upload a TSV first.'), findsNWidgets(5));
    final load = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Load from dataset'),
    );
    expect(load.onPressed, isNotNull);
    for (final button in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      expect(button.onPressed, isNull, reason: 'no action is tappable yet');
    }

    // The info stays open on a disabled row: it says what the row needs.
    expect(find.byTooltip('About this export'), findsNWidgets(5));
    await tester.tap(find.byTooltip('About this export').first);
    await tester.pumpAndSettle();
    for (final heading in const [
      'How it is exported',
      'What it needs',
      'What it creates',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(find.text(ReportAction.sessionReport.needs), findsOneWidget);
  });

  testWidgets('one session: the page scrolls as a whole, and the dataset add '
      'files only the TSV unless the report is ticked', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const name = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
    final upload = classifyUpload(
      name,
      File('test/fixtures/$name').readAsStringSync(),
    ).file!;
    await tester.pumpWidget(
      MaterialApp(home: ReportsScreen(initialFiles: [upload])),
    );
    await tester.pump();

    final page = find.byType(Scrollable).first;
    await tester.drag(page, const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(page).position.pixels, greaterThan(0));
    expect(find.byType(SessionEntriesTable), findsOneWidget);
    expect(
      find.text('Upload TSVs').hitTestable(),
      findsNothing,
      reason: 'scrolled away with the rest of the page',
    );
    await tester.drag(page, const Offset(0, 3000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add to dataset'));
    await tester.pumpAndSettle();
    final boxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .map((b) => b.value)
        .toList();
    expect(boxes, [true, false]);
    final format = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('PDF'),
    );
    expect(format, findsNothing, reason: 'no format without the report');
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(format, findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'several sessions: one patient is charted, two patients are not',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tsv = File(
        'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv',
      ).readAsStringSync();
      Uploaded upload(String sub, String ses) => classifyUpload(
        'sub-${sub}_ses-${ses}_task-programming_run-01_beh.tsv',
        tsv,
      ).file!;
      bool charted() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .any((p) => p.painter is ScalesChartPainter);

      await tester.pumpWidget(
        MaterialApp(
          home: ReportsScreen(
            initialFiles: [upload('01', '20260203'), upload('01', '20260310')],
          ),
        ),
      );
      await tester.pump();
      expect(charted(), isTrue);
      // No targets confirmed, so the dialog's defaults rank, as at export.
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<ScalesChartPainter>()
          .single;
      expect(painter.spec.bestXs, isNotEmpty);

      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: ReportsScreen(
            initialFiles: [upload('01', '20260203'), upload('02', '20260310')],
          ),
        ),
      );
      await tester.pump();
      expect(charted(), isFalse);
      expect(
        find.text('No chart is drawn across different patients.'),
        findsOneWidget,
      );
    },
  );
}
