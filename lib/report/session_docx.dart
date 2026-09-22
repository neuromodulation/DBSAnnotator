/// Session (Complete-Workflow) Word (.docx) report, the tablet counterpart of
/// the desktop's DOCX exporter (dbs_annotator/utils/session_exporter.py).
///
/// A pure function over already-parsed [SessionRow]s, so it is
/// headless-testable. Sections and row math are shared with the PDF via
/// report_data.dart, and the graphics are the same PNG bytes the PDF embeds,
/// passed in by the caller, so the two formats cannot drift.
///
/// Unlike the PDF there is no font concern: the XML is UTF-8 and Word uses
/// system fonts, so any character renders without sanitising.
library;

import 'dart:typed_data';

import '../app_info.dart' show appVersion;
import 'docx_ooxml.dart';
import '../core/brand_palette.dart';
import 'report_data.dart';
import 'report_sections.dart';
import 'session_pdf.dart' show ElectrodeReportImages, kElectrodeCellGapPt;

// Callers ask this library for the page size and the PNG reader, so keep them
// reachable here rather than making every call site learn where they moved.
export 'docx_ooxml.dart' show DocxPageSize, pngSize;

/// A borderless table for the electrode-image grid, so the images sit in a
/// clean 4-column layout with no visible cell edges.
String _borderlessTable(List<String> rowsXml, {required int contentTwips}) {
  // Four equal columns, explicitly quartered: with no grid, Word sized the
  // electrode cells from their captions and the four leads came out unequal.
  final widths = docxGridWidths(const [1, 1, 1, 1], contentTwips);
  final b = StringBuffer(
    '<w:tbl><w:tblPr><w:tblW w:w="$contentTwips" w:type="dxa"/>'
    '<w:tblBorders>',
  );
  for (final side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
    b.write('<w:$side w:val="none" w:sz="0" w:space="0" w:color="auto"/>');
  }
  b.write('</w:tblBorders>');
  b.write(docxTblGrid(widths));
  b.writeAll(rowsXml);
  b.write('</w:tbl>');
  return b.toString();
}

/// A centred cell holding arbitrary run XML, optionally spanning [span]
/// columns.
String _xmlCell(String runsXml, {int span = 1, int? widthTwips}) {
  final grid = span > 1 ? '<w:gridSpan w:val="$span"/>' : '';
  // A spanning cell's width is the sum of the columns it covers.
  final w = widthTwips == null
      ? ''
      : '<w:tcW w:w="${widthTwips * span}" w:type="dxa"/>';
  return '<w:tc><w:tcPr>$w$grid</w:tcPr>'
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>$runsXml</w:p></w:tc>';
}

/// A centred text cell for the electrode grid's caption rows.
String _captionCell(
  String text, {
  bool bold = false,
  int span = 1,
  int? widthTwips,
}) => _xmlCell(
  docxRun(text, bold: bold, size: 16),
  span: span,
  widthTwips: widthTwips,
);

/// Per-lead caption under an electrode image: "+ case" / "- 2b(3.3) 2c(2.2)".
/// Goes through the shared vendor-nomenclature helper: `E2b_E2c` is an
/// internal identifier, and an underscore-joined current reads as a dose.
String _tokenCaption(LateralTokens? tokens, {required bool left}) =>
    tokens == null ? '' : lateralText(tokens, left: left);

/// One decimal unless the value is whole. Twin of the PDF's formatter.
String _num(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  var out = v.toStringAsFixed(2);
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

/// Twin of the PDF's rated-per-block note, so both documents say it.
String? _ratedNote(SessionReportData data) {
  final counts = data.scalesRated.values.toSet();
  if (counts.isEmpty) return null;
  if (counts.length == 1) {
    return 'Scales rated per block: ${counts.first} throughout.';
  }
  final lo = counts.reduce((a, b) => a < b ? a : b);
  final hi = counts.reduce((a, b) => a > b ? a : b);
  return 'Scales rated per block: $lo-$hi. The index averages only the scales '
      'rated at each block, so blocks with different rated sets are not '
      'directly comparable.';
}

/// A signed delta: "-5", "+0.25", or "0" for no change, never "+0".
String _delta(double v) => v == 0 ? '0' : '${v > 0 ? '+' : ''}${_num(v)}';

/// Legend + scale targets + disclaimer under the session-data table, mirroring
/// `report_common.add_table_legend`. Returns '' when nothing was ranked.
String _legendBlock(SessionReportData data) {
  // No targets, no ranking, and the document says so.
  if (!data.hasTargets) return docxPara(data.targetsText, size: 18);
  if (data.bestBlocks.isEmpty && data.secondBlocks.isEmpty) return docxPara('');
  // A coloured square run, standing in for the desktop's coloured "■" glyph.
  String swatch(int argb) =>
      '<w:r><w:rPr><w:sz w:val="18"/><w:shd w:val="clear" w:color="auto" '
      'w:fill="${docxHex(argb)}"/></w:rPr><w:t xml:space="preserve">    </w:t></w:r>';
  final b = StringBuffer()
    ..write('<w:p>')
    ..write(docxRun('Legend: ', bold: true, size: 18))
    ..write(swatch(kBestFill))
    ..write(docxRun(' Highest aggregate index (rank 1)    ', size: 18))
    ..write(swatch(kSecondFill))
    ..write(docxRun(' Second highest (rank 2)', size: 18))
    ..write('</w:p>');
  if (data.targetsText.isNotEmpty) {
    b.write(docxPara('Scale targets: ${data.targetsText}', size: 18));
  }
  b.write(docxPara(kRankingDisclaimer, size: 18));
  return b.toString();
}

/// Build the session-report .docx and return its bytes. [subjectId] is the
/// BIDS subject label (without the "sub-" prefix). Mirrors the PDF's section
/// order and honours the same [sections] selection, so the two formats of one
/// export can never contain different sections.
Uint8List buildSessionDocx({
  required SessionReportData data,
  required String subjectId,
  ElectrodeReportImages? electrodeImages,
  Uint8List? chartPng,
  DocxPageSize pageSize = DocxPageSize.a4,
  Set<ReportSection> sections = kAllReportSections,
}) {
  final media = DocxMediaBag();
  final body = StringBuffer();

  // (a) Title + patient + generated-on.
  body.write(docxPara('DBS Annotator - Session report', bold: true, size: 40));
  body.write(
    docxPara('Patient: sub-$subjectId    Session: ${data.sessionStamp}'),
  );
  body.write(
    docxPara(
      'Generated on: ${data.generatedOn} by DBS Annotator v$appVersion'
      '${data.sourceFile.isEmpty ? '' : '  |  Source: ${data.sourceFile} '
                '(${data.rowCount} rows)'}',
      size: 18,
    ),
  );
  if (data.lastConfig.isNotEmpty) {
    // Same page-1 summary as the PDF, in the same words.
    body.write(
      docxTable(
        const ['At start of session', 'Last recorded configuration'],
        [
          [
            data.firstConfig.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('\n'),
            data.lastConfig.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('\n'),
          ],
        ],
        weights: const [1, 1],
        contentTwips: pageSize.contentWidthTwips,
      ),
    );
    for (final line in data.configChanges) {
      body.write(docxPara(line, size: 18));
    }
  }

  // (b) Baseline assessment. Headings and labels must match the PDF word for
  // word: two documents of one session that differ are a discovery problem.
  if (sections.contains(ReportSection.baseline)) {
    body.write(docxHeading('Baseline assessment (pre-session)'));
    if (!data.hasInitial) {
      body.write(docxPara('No baseline (is_initial = 1) rows recorded.'));
    } else {
      if (data.initScales.isNotEmpty) {
        // A two-column table, not bullets: Y-BOCS bulleted alike with its own
        // two subscales reads as three separate findings.
        body.write(
          docxTable(
            const ['Scale', 'Score'],
            [
              for (final pair in data.initScales) [pair.name, pair.value],
            ],
            weights: const [4, 1],
            contentTwips: pageSize.contentWidthTwips ~/ 2,
          ),
        );
      }
      if (data.initNotes.isNotEmpty) {
        body.write(docxPara('Notes: ${data.initNotes}'));
      }
      if (data.initScales.isEmpty && data.initNotes.isEmpty) {
        body.write(docxPara('(no baseline scales or notes)'));
      }
    }
  }

  // (c) Session data: chart, then lateral table. Graph and table are
  // independent sections, so the heading appears only when at least one does.
  final wantsChart = sections.contains(ReportSection.chart);
  final wantsTable = sections.contains(ReportSection.table);
  if (wantsChart || wantsTable) {
    body.write(docxHeading('Session data'));
    if (wantsChart && chartPng != null) {
      body.write(
        '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
        '${media.drawing(chartPng, widthPx: pageSize.contentWidthPx, description: data.figureCaption)}</w:p>',
      );
      // Same caption as the PDF, word for word.
      body.write(docxPara(data.figureCaption, size: 16));
    }
    if (wantsTable && !data.hasRecording) {
      body.write(docxPara('No recording blocks in this session.'));
    } else if (wantsTable) {
      // Green shading for the best / second-best blocks, and a 3 pt rule on
      // the first row of each block (tableData holds L then R per block).
      final fills = <int, String>{};
      final rules = <int>{};
      var previousBlock = '';
      for (var i = 0; i < data.tableData.length; i++) {
        final label = data.tableData[i].first;
        if (label != previousBlock) {
          if (i > 0) rules.add(i);
          previousBlock = label;
        }
        final block = int.tryParse(label);
        if (block == null) continue;
        if (data.bestBlocks.contains(block)) {
          fills[i] = docxHex(kBestFill);
        } else if (data.secondBlocks.contains(block)) {
          fills[i] = docxHex(kSecondFill);
        }
      }
      body.write(
        docxTable(
          sessionTableHeaders,
          data.tableData,
          rowFills: fills,
          rowRules: rules,
          // Scales and Notes: one tall cell per block, not one per side.
          mergeDownColumns: {
            sessionTableHeaders.indexOf('Scales'),
            sessionTableHeaders.indexOf('Notes'),
          },
          weights: sessionTableColumnWeights,
          contentTwips: pageSize.contentWidthTwips,
        ),
      );
      body.write(_legendBlock(data));
      final rated = _ratedNote(data);
      if (rated != null) body.write(docxPara(rated, size: 16));
      if (data.bestSettingText.isNotEmpty) {
        body.write(docxPara(data.bestSettingText, size: 16));
      }
      final resolution = data.rankingResolutionNote;
      if (resolution != null) body.write(docxPara(resolution, size: 16));
    }
  }

  // (d) Electrode configuration: the four rendered leads in a borderless grid
  // when the caller supplied them, else anode/cathode token text.
  if (sections.contains(ReportSection.electrodes)) {
    body.write(docxHeading('Electrode configuration'));
    final ei = electrodeImages;
    final hasImages =
        ei != null &&
        (ei.initLeft != null ||
            ei.initRight != null ||
            ei.finalLeft != null ||
            ei.finalRight != null);
    if (!data.hasElectrodeConfig) {
      body.write(docxPara('No electrode configuration recorded.'));
    } else {
      if (data.electrodeModel.isNotEmpty) {
        body.write(docxPara('Electrode model: ${data.electrodeModel}'));
      }
      final it = data.initialTokens;
      final ft = data.finalTokens;
      if (hasImages) {
        // One quarter of the content width per lead, less the same gap the PDF
        // leaves (expressed in points there, so convert 72 dpi -> 96 dpi).
        final cellPx =
            pageSize.contentWidthPx / 4 - kElectrodeCellGapPt * 96 / 72;
        String img(Uint8List? png) =>
            png == null ? '' : media.drawing(png, widthPx: cellPx);
        final quarter = pageSize.contentWidthTwips ~/ 4;
        String cap(String text, {bool bold = false, int span = 1}) =>
            _captionCell(text, bold: bold, span: span, widthTwips: quarter);
        String cell(Uint8List? png) => _xmlCell(img(png), widthTwips: quarter);
        body.write(
          _borderlessTable(contentTwips: pageSize.contentWidthTwips, [
            '<w:tr>${cap('Initial settings', bold: true, span: 2)}'
                '${cap('Final settings', bold: true, span: 2)}</w:tr>',
            '<w:tr>${cap('Left')}${cap('Right')}${cap('Left')}${cap('Right')}'
                '</w:tr>',
            '<w:tr>'
                '${cap(_tokenCaption(it, left: true))}'
                '${cap(_tokenCaption(it, left: false))}'
                '${cap(_tokenCaption(ft, left: true))}'
                '${cap(_tokenCaption(ft, left: false))}'
                '</w:tr>',
            '<w:tr>${cell(ei.initLeft)}${cell(ei.initRight)}'
                '${cell(ei.finalLeft)}${cell(ei.finalRight)}</w:tr>',
          ]),
        );
        // Same key as the PDF: the drawing encodes polarity by COLOUR alone,
        // which is useless on a mono printer or to a colour-blind reader.
        body.write(
          docxPara(
            'Orange = anode (+)   Blue = cathode (-)   Grey = inactive.   '
            "A percentage is that contact's share of the total current.",
            size: 14,
          ),
        );
        body.write(docxPara(''));
      } else {
        // Vendor nomenclature here too, through the SAME helper the PDF's
        // fallback uses; report_parity_test catches a divergence.
        for (final pair in [
          ('Initial settings', it),
          ('Last recorded settings', ft),
        ]) {
          final tokens = pair.$2;
          if (tokens == null) continue;
          body.write(docxPara(pair.$1, bold: true));
          body.write(docxPara('  Left:   ${lateralText(tokens, left: true)}'));
          body.write(docxPara('  Right:  ${lateralText(tokens, left: false)}'));
        }
      }
    }
  }

  // (e) Programming summary.
  if (sections.contains(ReportSection.summary)) {
    body.write(docxHeading('Programming summary'));
    if (!data.hasRows) {
      body.write(docxPara('No session data available.'));
    } else {
      body.write(
        docxPara('Annotation span (first to last entry): ${data.span}'),
      );
      body.write(docxPara('Configurations tested: ${configCountText(data)}'));
      body.write(docxPara('Amplitude:  L: ${data.ampL}  |  R: ${data.ampR}'));
      body.write(docxPara('Frequency:  L: ${data.freqL}  |  R: ${data.freqR}'));
      body.write(docxPara('Pulse width:  L: ${data.pwL}  |  R: ${data.pwR}'));

      // Same two subsections as the PDF, in the same order and the same words.
      if (data.response.isNotEmpty) {
        body.write(docxHeading2('Response (first to last rated block)'));
        for (final r in data.response) {
          body.write(
            docxPara(
              '  ${r.name}: ${_num(r.first)} -> ${_num(r.last)} '
              '(${_delta(r.last - r.first)})',
            ),
          );
        }
      }
      body.write(docxPara(data.instrumentNote, size: 16));
      if (data.anomalies.isNotEmpty) {
        body.write(docxHeading2('Data notes'));
        for (final line in data.anomalies) {
          body.write(docxPara('  • $line', size: 18));
        }
      }
      if (data.observations.isNotEmpty) {
        body.write(docxHeading2('Recorded observations'));
        for (final line in data.observations) {
          body.write(docxPara('  • $line', size: 18));
        }
      }
    }
  }

  // Attestation, so the document does not stand on a machine's word alone.
  // Underscores rather than a border, to survive a copy-paste elsewhere.
  body.write(docxHeading2('Attestation'));
  body.write(
    docxPara(
      'Recorded by: ${'_' * 26}    '
      'Reviewed by: ${'_' * 26}    Date: ${'_' * 14}',
    ),
  );

  // Packaging is shared with the annotations report: one implementation of the
  // content-types and relationships Word would otherwise offer to repair.
  return packDocx(
    body: body.toString(),
    pageSize: pageSize,
    media: media,
    title: 'DBS session report - sub-$subjectId - ${data.sessionDate}',
    subject: 'Deep brain stimulation programming session',
    createdDate: data.generatedOn,
    footerPrefix:
        'sub-$subjectId  |  ${data.sessionStamp}  |  '
        'DBS Annotator v$appVersion  |  Page ',
  );
}
