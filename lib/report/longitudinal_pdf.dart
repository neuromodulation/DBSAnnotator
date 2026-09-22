/// Longitudinal report, in PDF and Word: the tablet counterpart of the
/// desktop's longitudinal exporter.
///
/// Pure functions over already-computed [LongitudinalReportData], so both
/// formats are built from one set of numbers and are headless-testable. The
/// two figures come in as PNG bytes the caller rasterised.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart' show appVersion;
import 'docx_ooxml.dart';
import 'longitudinal_data.dart';
import 'report_data.dart' show ReportBytes;
import 'report_fonts.dart';
import 'report_palette.dart';
import 'report_text.dart';

/// Relative column widths for [longitudinalTableHeaders].
const _tableWeights = <double>[6, 12, 34, 7, 22, 9];

/// Page margins, matching the session report so a clinician filing both does
/// not get two different geometries for one patient.
const _marginSide = 36.0;
const _marginEnd = 54.0;

/// A PNG at exactly [width] points, aspect preserved.
///
/// Never a bare `pw.Image`: dart_pdf lays one out at the PNG's PIXEL size, so
/// a print-resolution raster becomes a widget hundreds of points tall and the
/// page fails to generate.
pw.Widget _fitWidth(Uint8List png, double width) {
  final image = pw.MemoryImage(png);
  final w = image.width ?? 0;
  final h = image.height ?? 0;
  return pw.Image(image, width: width, height: w > 0 ? width * h / w : null);
}

/// Build the longitudinal report PDF.
Future<ReportBytes> buildLongitudinalPdf({
  required LongitudinalReportData data,
  Uint8List? clinicalChartPng,
  Uint8List? sessionChartPng,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
}) async {
  final fonts = await loadReportFonts();
  final theme = fonts.theme;
  final t = ReportTextSanitiser(coverage: fonts.coverage);
  final format = pageFormat.copyWith(
    marginLeft: _marginSide,
    marginRight: _marginSide,
    marginTop: _marginEnd,
    marginBottom: _marginEnd,
  );
  final span = data.visits.isEmpty
      ? ''
      : '${data.visits.first.date} to ${data.visits.last.date}';

  final doc = pw.Document(
    theme: theme,
    title: 'DBS longitudinal report - sub-${data.patientId}',
    author: kDocxCreator,
    creator: kDocxCreator,
    subject: 'Deep brain stimulation longitudinal review',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'sub-${t(data.patientId)}  |  ${data.visits.length} visits'
          '${span.isEmpty ? '' : ', $span'}  |  DBS Annotator v$appVersion'
          '  |  Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: pdfInk),
        ),
      ),
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            'DBS Annotator - Longitudinal report',
            style: const pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(
          'Patient: sub-${t(data.patientId)}    '
          'Visits: ${data.visits.length}${span.isEmpty ? '' : '    $span'}',
        ),
        pw.Text(
          'Generated on: ${data.generatedOn} by DBS Annotator v$appVersion',
          style: const pw.TextStyle(fontSize: 9, color: pdfInk),
        ),

        // Mixing two patients into one longitudinal report is a safety problem,
        // so it is stated at the top of page 1, not buried in a file list.
        if (data.mismatchedPatients.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: pdfPanelFill,
              border: pw.Border.all(color: PdfColors.black, width: 1),
            ),
            child: pw.Text(
              'WARNING: the imported files name more than one patient '
              '(${t(([data.patientId, ...data.mismatchedPatients]).join(', '))}). '
              'This report combines them.',
              style: const pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
        pw.SizedBox(height: 12),

        if (data.isEmpty)
          pw.Text('No visits imported.')
        else ...[
          // (a) Clinical scales by visit.
          pw.Header(level: 1, text: 'Clinical scales by visit'),
          if (clinicalChartPng != null) ...[
            _fitWidth(clinicalChartPng, format.availableWidth),
            pw.Text(
              'Figure 1. Clinical scale scores, one assessment per visit. '
              'No aggregate index is shown: it is normalised within a session, '
              'so values from different visits were never on one scale.',
              style: const pw.TextStyle(
                fontSize: 8,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ] else if (data.clinicalChart.isEmpty)
            pw.Text('No baseline clinical scale scores were recorded.')
          else
            pw.Text('(figure unavailable)'),
          pw.SizedBox(height: 10),

          // (b) Session scales by visit and block.
          pw.Header(level: 1, text: 'Session scales by visit and block'),
          if (sessionChartPng != null) ...[
            _fitWidth(sessionChartPng, format.availableWidth),
            pw.Text(
              'Figure 2. Session scale ratings against visit and block. Each '
              'visit contributes one point per configuration tested.',
              style: const pw.TextStyle(
                fontSize: 8,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ] else if (data.sessionChart.isEmpty)
            pw.Text('No session scale ratings were recorded.')
          else
            pw.Text('(figure unavailable)'),
          pw.SizedBox(height: 10),

          // (c) The per-visit table.
          pw.Header(level: 1, text: 'Visits'),
          pw.TableHelper.fromTextArray(
            headers: longitudinalTableHeaders,
            data: t.rows(data.visitTable),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: const pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: pdfHeaderFill),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              for (final (i, w) in _tableWeights.indexed)
                i: pw.FlexColumnWidth(w),
            },
          ),
          pw.Text(
            'Change is against the previous visit that recorded the same '
            'scale. The programme shown is the last configuration recorded at '
            'that visit, which is not necessarily one a clinician confirmed.',
            style: const pw.TextStyle(fontSize: 8),
          ),

          // (d) Sources, demoted to an appendix: provenance, not content.
          pw.SizedBox(height: 12),
          pw.Header(level: 1, text: 'Source files'),
          for (final v in data.visits)
            pw.Bullet(
              text: t('${v.filename}  (${v.blocks.length} blocks)'),
              style: const pw.TextStyle(fontSize: 8),
              bulletSize: 1.5,
            ),
        ],
      ],
    ),
  );
  return (bytes: await doc.save(), lostCharacters: t.lostCharacters);
}

/// The same report as a .docx, saying the same things in the same words.
Uint8List buildLongitudinalDocx({
  required LongitudinalReportData data,
  Uint8List? clinicalChartPng,
  Uint8List? sessionChartPng,
  DocxPageSize pageSize = DocxPageSize.a4,
}) {
  final media = DocxMediaBag();
  final span = data.visits.isEmpty
      ? ''
      : '${data.visits.first.date} to ${data.visits.last.date}';

  final body = StringBuffer()
    ..write(
      docxPara('DBS Annotator - Longitudinal report', bold: true, size: 40),
    )
    ..write(
      docxPara(
        'Patient: sub-${data.patientId}    '
        'Visits: ${data.visits.length}${span.isEmpty ? '' : '    $span'}',
      ),
    )
    ..write(
      docxPara(
        'Generated on: ${data.generatedOn} by DBS Annotator v$appVersion',
        size: 18,
      ),
    );

  if (data.mismatchedPatients.isNotEmpty) {
    body.write(
      docxPara(
        'WARNING: the imported files name more than one patient '
        '(${([data.patientId, ...data.mismatchedPatients]).join(', ')}). '
        'This report combines them.',
        bold: true,
      ),
    );
  }

  if (data.isEmpty) {
    body.write(docxPara('No visits imported.'));
  } else {
    body.write(docxHeading('Clinical scales by visit'));
    if (clinicalChartPng != null) {
      body
        ..write(
          '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
          '${media.drawing(clinicalChartPng, widthPx: pageSize.contentWidthPx, description: 'Clinical scale scores by visit')}</w:p>',
        )
        ..write(
          docxPara(
            'Figure 1. Clinical scale scores, one assessment per visit. '
            'No aggregate index is shown: it is normalised within a session, '
            'so values from different visits were never on one scale.',
            size: 16,
          ),
        );
    } else if (data.clinicalChart.isEmpty) {
      body.write(docxPara('No baseline clinical scale scores were recorded.'));
    }

    body.write(docxHeading('Session scales by visit and block'));
    if (sessionChartPng != null) {
      body
        ..write(
          '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
          '${media.drawing(sessionChartPng, widthPx: pageSize.contentWidthPx, description: 'Session scale ratings by visit and block')}</w:p>',
        )
        ..write(
          docxPara(
            'Figure 2. Session scale ratings against visit and block. Each '
            'visit contributes one point per configuration tested.',
            size: 16,
          ),
        );
    } else if (data.sessionChart.isEmpty) {
      body.write(docxPara('No session scale ratings were recorded.'));
    }

    body
      ..write(docxHeading('Visits'))
      ..write(
        docxTable(
          longitudinalTableHeaders,
          data.visitTable,
          weights: _tableWeights,
          contentTwips: pageSize.contentWidthTwips,
        ),
      )
      ..write(
        docxPara(
          'Change is against the previous visit that recorded the same scale. '
          'The programme shown is the last configuration recorded at that '
          'visit, which is not necessarily one a clinician confirmed.',
          size: 16,
        ),
      )
      ..write(docxHeading('Source files'));
    for (final v in data.visits) {
      body.write(
        docxPara('  • ${v.filename}  (${v.blocks.length} blocks)', size: 16),
      );
    }
  }

  return packDocx(
    body: body.toString(),
    pageSize: pageSize,
    media: media,
    title: 'DBS longitudinal report - sub-${data.patientId}',
    subject: 'Deep brain stimulation longitudinal review',
    createdDate: data.generatedOn,
    footerPrefix:
        'sub-${data.patientId}  |  ${data.visits.length} visits'
        '${span.isEmpty ? '' : ', $span'}  |  DBS Annotator v$appVersion'
        '  |  Page ',
  );
}
