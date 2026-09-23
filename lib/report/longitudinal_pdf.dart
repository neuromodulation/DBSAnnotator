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
import 'longitudinal_sections.dart';
import 'report_data.dart'
    show ReportBytes, sessionTableColumnWeights, sessionTableHeaders;
import 'session_pdf.dart' show ElectrodeReportImages, kElectrodeCellGapPt;
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
  Map<String, ElectrodeReportImages> electrodeImages = const {},
  PdfPageFormat pageFormat = PdfPageFormat.a4,
  Set<LongitudinalSection> sections = kAllLongitudinalSections,
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
          if (sections.contains(LongitudinalSection.clinicalChart)) ...[
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
          ],

          // (b) Session scales by visit and block.
          if (sections.contains(LongitudinalSection.sessionChart)) ...[
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
          ],

          // (c) The per-visit table.
          if (sections.contains(LongitudinalSection.visits)) ...[
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
          ],

          // (d) Every configuration of every visit, grouped by visit rather
          // than given a visit COLUMN: the session table's twelve widths are
          // sized to their headers, and a thirteenth broke them mid-word.
          if (sections.contains(LongitudinalSection.sessionTable))
            ..._sessionTable(data, t),

          // (e) Per-visit lead diagrams, the section that adds pages.
          if (sections.contains(LongitudinalSection.electrodes))
            ..._electrodes(data, electrodeImages, format, t),

          // (f) Per-visit parameter ranges.
          if (sections.contains(LongitudinalSection.summary))
            ..._summary(data, t),

          // (g) Sources, demoted to an appendix: provenance, not content.
          if (sections.contains(LongitudinalSection.sources)) ...[
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
  Map<String, ElectrodeReportImages> electrodeImages = const {},
  DocxPageSize pageSize = DocxPageSize.a4,
  Set<LongitudinalSection> sections = kAllLongitudinalSections,
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
    if (sections.contains(LongitudinalSection.clinicalChart)) {
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
        body.write(
          docxPara('No baseline clinical scale scores were recorded.'),
        );
      }
    }

    if (sections.contains(LongitudinalSection.sessionChart)) {
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
    }

    if (sections.contains(LongitudinalSection.visits)) {
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
        );
    }

    if (sections.contains(LongitudinalSection.sessionTable)) {
      body.write(docxHeading('Session data'));
      for (final v in data.visits) {
        if (v.session.tableData.isEmpty) continue;
        body
          ..write(docxHeading2(_visitLabel(v)))
          ..write(
            docxTable(
              sessionTableHeaders,
              v.session.tableData,
              weights: sessionTableColumnWeights,
              contentTwips: pageSize.contentWidthTwips,
            ),
          );
      }
    }

    if (sections.contains(LongitudinalSection.electrodes)) {
      body.write(docxHeading('Electrode configuration'));
      for (final v in data.visits) {
        final gfx = electrodeImages[v.filename];
        if (gfx == null) continue;
        body.write(docxHeading2(_visitLabel(v)));
        for (final (label, png) in [
          ('Initial L', gfx.initLeft),
          ('Initial R', gfx.initRight),
          ('Last L', gfx.finalLeft),
          ('Last R', gfx.finalRight),
        ]) {
          if (png == null) continue;
          body.write(
            '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
            '${media.drawing(png, widthPx: pageSize.contentWidthPx / 4, description: '$label lead')}</w:p>',
          );
        }
      }
    }

    if (sections.contains(LongitudinalSection.summary)) {
      body.write(docxHeading('Programming summary'));
      for (final v in data.visits) {
        body.write(docxHeading2(_visitLabel(v)));
        for (final line in [
          'Configurations tested: ${v.session.numConfigs} '
              '(${v.session.numDistinctConfigs} distinct settings)',
          'Amplitude: L: ${v.session.ampL} | R: ${v.session.ampR}',
          'Frequency: L: ${v.session.freqL} | R: ${v.session.freqR}',
          'Pulse width: L: ${v.session.pwL} | R: ${v.session.pwR}',
        ]) {
          body.write(docxPara('  • $line', size: 16));
        }
      }
    }

    if (sections.contains(LongitudinalSection.sources)) {
      body.write(docxHeading('Source files'));
      for (final v in data.visits) {
        body.write(
          docxPara('  • ${v.filename}  (${v.blocks.length} blocks)', size: 16),
        );
      }
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

/// "2026-02-03 run 01", the per-visit subheading both formats use.
String _visitLabel(LongitudinalVisit v) =>
    '${v.date}${v.run.isEmpty ? '' : ' run ${v.run}'}';

/// (d) Every configuration of every visit, under a per-visit subheading rather
/// than with a visit column: the twelve column widths are sized to their own
/// headers, and a thirteenth broke them mid-word.
List<pw.Widget> _sessionTable(
  LongitudinalReportData data,
  ReportTextSanitiser t,
) => [
  pw.SizedBox(height: 12),
  pw.Header(level: 1, text: 'Session data'),
  for (final v in data.visits)
    if (v.session.tableData.isNotEmpty) ...[
      pw.SizedBox(height: 6),
      pw.Text(
        t('${v.date}${v.run.isEmpty ? '' : ' run ${v.run}'}'),
        style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      pw.TableHelper.fromTextArray(
        headers: sessionTableHeaders,
        data: t.rows(v.session.tableData),
        cellStyle: const pw.TextStyle(fontSize: 7),
        headerStyle: const pw.TextStyle(
          fontSize: 7,
          fontWeight: pw.FontWeight.bold,
        ),
        headerDecoration: const pw.BoxDecoration(color: pdfHeaderFill),
        cellAlignment: pw.Alignment.centerLeft,
        columnWidths: {
          for (final (i, w) in sessionTableColumnWeights.indexed)
            i: pw.FlexColumnWidth(w),
        },
      ),
    ],
];

/// (e) Per-visit lead diagrams. Four images a visit, so this is the section
/// that turns a three-page report into a ten-page one.
List<pw.Widget> _electrodes(
  LongitudinalReportData data,
  Map<String, ElectrodeReportImages> images,
  PdfPageFormat format,
  ReportTextSanitiser t,
) {
  final leadWidth = format.availableWidth / 4 - kElectrodeCellGapPt;
  return [
    pw.SizedBox(height: 12),
    pw.Header(level: 1, text: 'Electrode configuration'),
    for (final v in data.visits)
      if (images[v.filename] case final gfx?)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 6),
            pw.Text(
              t('${v.date}${v.run.isEmpty ? '' : ' run ${v.run}'}'),
              style: const pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Row(
              children: [
                for (final (label, png) in [
                  ('Initial L', gfx.initLeft),
                  ('Initial R', gfx.initRight),
                  ('Last L', gfx.finalLeft),
                  ('Last R', gfx.finalRight),
                ])
                  pw.Container(
                    width: leadWidth,
                    margin: const pw.EdgeInsets.only(
                      right: kElectrodeCellGapPt,
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
                        if (png != null)
                          _fitWidth(png, leadWidth)
                        else
                          pw.Text(
                            '(not recorded)',
                            style: const pw.TextStyle(
                              fontSize: 7,
                              color: pdfInk,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
  ];
}

/// (f) Per-visit parameter ranges and how many configurations were tried.
List<pw.Widget> _summary(LongitudinalReportData data, ReportTextSanitiser t) =>
    [
      pw.SizedBox(height: 12),
      pw.Header(level: 1, text: 'Programming summary'),
      for (final v in data.visits)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 6),
            pw.Text(
              t('${v.date}${v.run.isEmpty ? '' : ' run ${v.run}'}'),
              style: const pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            for (final line in [
              'Configurations tested: ${v.session.numConfigs} '
                  '(${v.session.numDistinctConfigs} distinct settings)',
              'Amplitude: L: ${v.session.ampL} | R: ${v.session.ampR}',
              'Frequency: L: ${v.session.freqL} | R: ${v.session.freqR}',
              'Pulse width: L: ${v.session.pwL} | R: ${v.session.pwR}',
            ])
              pw.Bullet(
                text: t(line),
                style: const pw.TextStyle(fontSize: 8),
                bulletSize: 1.5,
              ),
          ],
        ),
    ];
