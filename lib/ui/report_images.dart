/// Screen-side rasterisers that turn the electrode painter into PNG bytes for
/// the PDF / Word reports. Uses `dart:ui`, so it must run in the app rather
/// than in the headless report builders, which take the bytes as parameters.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/session/session_row.dart';
import '../report/report_data.dart' show SessionReportData;
import '../report/report_sections.dart';
import '../report/session_pdf.dart' show ElectrodeReportImages;
import 'scales_chart_painter.dart';

import '../core/electrode/electrode_model.dart';
import '../core/electrode/geometry.dart';
import '../core/electrode/tokens.dart';
import 'electrode_painter.dart';
import 'theme.dart';

/// Render one electrode configuration (from anode/cathode token strings) to a
/// white-background PNG, mirroring the desktop's `render_electrode_png`.
Future<Uint8List?> renderElectrodePng(
  ElectrodeModel model,
  String anode,
  String cathode, {
  Size size = const Size(300, 640),
  Color labelColor = const Color(0xFF222222),
  // Embedded at ~170 pt tall, so render above screen density to stay crisp
  // in print.
  double pixelRatio = 3.0,
}) async {
  final decoded = decodeTokens(anode, cathode, model);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
  ElectrodePainter(
    layout: computeLayout(model, size),
    states: decoded.states,
    caseState: decoded.caseState,
    labelColor: labelColor,
    // Reports print on white paper, whatever the app's current theme.
    palette: ElectrodePalette.light,
  ).paint(canvas, size);
  final image = await recorder.endRecording().toImage(
    (size.width * pixelRatio).round(),
    (size.height * pixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  // Null rather than `data!`: an export must never be lost because one lead
  // failed to rasterise. Both builders fall back to anode/cathode token text.
  return data?.buffer.asUint8List();
}

/// The graphics both report formats embed, rasterised once so the PDF and the
/// Word document are guaranteed to show identical images.
///
/// Only what [sections] will actually embed is rendered: PNG encoding costs a
/// few hundred ms on the UI isolate. [right] is the right lead's model when it
/// differs from the left one, [model].
Future<({ElectrodeReportImages? electrodes, Uint8List? chart})>
renderReportGraphics(
  SessionReportData data,
  ElectrodeModel? model,
  Set<ReportSection> sections, {
  ElectrodeModel? right,
}) async {
  // Every rasterisation is best-effort: a report without a picture beats no
  // report, and both builders degrade to token text when an image is missing.
  Uint8List? chart;
  if (sections.contains(ReportSection.chart)) {
    try {
      chart = await renderScalesChartPng(data.chart);
    } catch (e, st) {
      debugPrint('Scales chart could not be rendered: $e\n$st');
    }
  }
  final rightModel = right ?? model;
  if (model == null ||
      rightModel == null ||
      !sections.contains(ReportSection.electrodes)) {
    return (electrodes: null, chart: chart);
  }

  // Use the rows report_data resolved. Re-deriving them with a simpler rule
  // lets the images show one configuration and the text beside them another,
  // for instance on a TSV writing `is_initial` as "1.0".
  Future<Uint8List?> png(SessionRow? row, bool left) async {
    if (row == null) return null;
    try {
      return await renderElectrodePng(
        left ? model : rightModel,
        left ? row.leftAnode : row.rightAnode,
        left ? row.leftCathode : row.rightCathode,
      );
    } catch (e) {
      debugPrint('Electrode image could not be rendered: $e');
      return null;
    }
  }

  final leads = await Future.wait([
    png(data.initialRow, true),
    png(data.initialRow, false),
    png(data.finalRow, true),
    png(data.finalRow, false),
  ]);

  return (
    electrodes: (
      initLeft: leads[0],
      initRight: leads[1],
      finalLeft: leads[2],
      finalRight: leads[3],
    ),
    chart: chart,
  );
}
