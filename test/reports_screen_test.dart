import 'dart:io';

import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/upload_actions.dart';
import 'package:dbs_annotator/ui/reports_screen.dart';
import 'package:dbs_annotator/ui/session/entries_table.dart';
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
      'Create a BIDS dataset (zip)',
      'Add to an existing dataset',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Upload a TSV first.'), findsNWidgets(5));
    final load = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Load from dataset'),
    );
    expect(load.onPressed, isNotNull);
    for (final button in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      if (button == load) continue;
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
}
