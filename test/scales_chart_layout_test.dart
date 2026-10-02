/// The chart's top band: title, then legend, then plot, none overlapping.
///
/// The legend's box is opaque and painted after the axes, so any overlap
/// erases what lies beneath it: the bottom third of every title glyph in the
/// reported defect, and the top of the plot when `_padTop` sits too high.
library;

import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/ui/scales_chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScalesChartSpec _spec({
  String title = 'Session scales',
  int scales = 5,
  bool withIndex = true,
}) => ScalesChartSpec(
  xs: const [1, 2, 3],
  series: {
    for (var i = 0; i < scales; i++)
      'Scale number $i': const {1: 3.0, 2: 4.0, 3: 5.0},
  },
  aggregateIndex: withIndex ? const {1: 0.4, 2: 0.5, 3: 0.6} : const {},
  amplitude: const {
    'Left': {1: 2.0, 2: 3.0, 3: 3.5},
  },
  bestXs: withIndex ? const [3] : const [],
  secondXs: withIndex ? const [2] : const [],
  yMin: 0,
  yMax: 10,
  title: title,
  xLabel: 'Block',
  yLabel: 'Score',
);

void main() {
  ChartTopBand band(ScalesChartSpec spec, [Size size = const Size(800, 376)]) =>
      ChartTopBand.measure(ScalesChartPainter(spec: spec), size);

  test('the legend starts below the title, and the plot below the legend', () {
    final b = band(_spec());
    expect(b.titleHeight, greaterThan(0));
    expect(
      b.legendTop,
      greaterThanOrEqualTo(b.titleTop + b.titleHeight),
      reason: 'the legend box would paint over the title',
    );
    expect(
      b.padTop,
      greaterThanOrEqualTo(b.legendTop + (b.legend?.height ?? 0)),
      reason: 'the legend would overrun the plot',
    );
  });

  test('a title-less chart reserves no title space', () {
    final b = band(_spec(title: ''));
    expect(b.titleHeight, 0);
    expect(b.legendTop, b.titleTop, reason: 'the legend moves up to fill it');
    expect(b.padTop, lessThan(band(_spec()).padTop));
  });

  test('the invariants hold however many scales there are', () {
    // Shrink-to-fit stops at the 10 px print floor and then wraps into rows,
    // so a long legend grows taller; it must still end above the plot and
    // leave the plot most of the canvas.
    for (final n in [1, 5, 12, 30]) {
      final b = band(_spec(scales: n));
      expect(
        b.legendTop,
        greaterThanOrEqualTo(b.titleTop + b.titleHeight),
        reason: '$n scales',
      );
      expect(
        b.padTop,
        greaterThanOrEqualTo(b.legendTop + (b.legend?.height ?? 0)),
        reason: '$n scales',
      );
      expect(
        b.padTop,
        lessThan(160),
        reason: '$n scales must not eat the plot',
      );
    }
  });

  test('no legend at all still leaves the plot a sane top', () {
    final b = band(_spec(title: '', scales: 0, withIndex: false));
    expect(b.legend, isNull);
    expect(b.padTop, greaterThan(0));
  });
}
