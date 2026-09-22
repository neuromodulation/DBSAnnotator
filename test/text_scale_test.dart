/// The A+/A- setting reaches the entry review, and stops at the report.
///
/// The entry charts paint their x-axis strip with a `TextPainter`, which
/// defaults to no scaling, so before this the labels around the axis grew and
/// the axis itself did not. The same primitives draw the chart rasterised into
/// every PDF and Word report, which must not change size because the person
/// exporting it had pressed A+.
library;

import 'dart:typed_data';

import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/entry_charts.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/ui/chart_primitives.dart';
import 'package:dbs_annotator/ui/scales_chart_painter.dart';
import 'package:dbs_annotator/ui/session/entries_table.dart';
import 'package:dbs_annotator/ui/session/entry_charts_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rows = [
  SessionRow(
    blockId: '1',
    isInitial: '0',
    acqTime: '2026-01-01T09:00:00',
    leftStimFreq: '130',
    leftAmplitude: '2.5',
    leftPulseWidth: '60',
    scaleName: 'Tremor',
    scaleValue: '4',
  ),
  SessionRow(
    blockId: '2',
    isInitial: '0',
    acqTime: '2026-01-01T09:12:00',
    leftStimFreq: '130',
    leftAmplitude: '3.5',
    leftPulseWidth: '60',
    scaleName: 'Tremor',
    scaleValue: '1',
  ),
];

Future<void> _pump(WidgetTester tester, Widget child, double scale) =>
    tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          // Scrollable, as the step body that hosts these is.
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

/// The painted x-axis strip, found by its painter since the class is private.
final _axis = find.byWidgetPredicate(
  (w) => w is CustomPaint && '${w.painter.runtimeType}' == '_XAxisPainter',
);

void main() {
  test('chartTextPainter scales only when asked', () {
    final plain = chartTextPainter('09:03:20', color: Colors.black, size: 11);
    final scaled = chartTextPainter(
      '09:03:20',
      color: Colors.black,
      size: 11,
      scaler: const TextScaler.linear(1.6),
    );
    expect(scaled.width, greaterThan(plain.width));
    expect(scaled.height, greaterThan(plain.height));

    final explicitNone = chartTextPainter(
      '09:03:20',
      color: Colors.black,
      size: 11,
      scaler: TextScaler.noScaling,
    );
    expect(explicitNone.width, plain.width);
  });

  testWidgets('the entry charts x axis grows with the text scale', (
    tester,
  ) async {
    final data = buildEntryChartData(_rows);

    await _pump(tester, EntryChartsView(data: data), 1);
    final small = tester.getSize(_axis);

    await _pump(tester, EntryChartsView(data: data), 1.6);
    final large = tester.getSize(_axis);

    expect(large.height, greaterThan(small.height));
    expect(
      large.width,
      lessThan(small.width),
      reason: 'the wider gutter takes room from the plot',
    );
  });

  testWidgets('the entries table grows with the text scale', (tester) async {
    await _pump(tester, const SessionEntriesTable(rows: _rows), 1);
    final small = tester.getSize(find.byType(Table));

    await _pump(tester, const SessionEntriesTable(rows: _rows), 1.6);
    expect(
      tester.getSize(find.byType(Table)).height,
      greaterThan(small.height),
    );
  });

  testWidgets('the report chart is the same drawing at any text scale', (
    tester,
  ) async {
    final chart = buildSessionReportData(rows: _rows).chart;
    late Uint8List? plain;
    late Uint8List? scaled;

    // Rasterised inside a pumped app, so an ambient scaler is present to be
    // picked up if the report path ever starts reading one.
    await _pump(tester, const SizedBox(), 1);
    await tester.runAsync(() async {
      plain = await renderScalesChartPng(chart);
    });
    await _pump(tester, const SizedBox(), 1.6);
    await tester.runAsync(() async {
      scaled = await renderScalesChartPng(chart);
    });

    expect(plain, isNotNull);
    expect(scaled, equals(plain));
  });
}
