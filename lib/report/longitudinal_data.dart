/// Pure computation behind the longitudinal report: one entry per visit, and
/// the two figures the desktop draws.
///
/// Clinical scales are plotted against the visit (one assessment per visit),
/// session scales against visit + block (several configurations per visit).
/// Neither carries the aggregate index or its bands: the index is normalised
/// within a session, so ranking across visits would compare numbers that were
/// never on the same scale. A block index concatenated across files would
/// assert the same false comparability.
library;

import '../core/session/longitudinal.dart'
    show extractPatientId, isScaleValueOmitted, splitScalePairs;
import '../core/session/session_row.dart';
import '../core/timestamps.dart';
import '../core/session/scale_scoring.dart';
import 'report_data.dart'
    show
        ScalesChartSpec,
        SessionReportData,
        buildSessionReportData,
        coerceInt,
        trimZeros;

/// One imported file: a visit.
typedef LongitudinalVisit = ({
  String filename,

  /// From the rows themselves, "yyyy-MM-dd", or '' when none parse.
  String date,

  /// The BIDS `run-` entity, or ''.
  String run,

  /// "20260626_01", the desktop's `{date}_{run}` tick label.
  String label,

  /// Baseline (`is_initial == 1`) scale scores: the clinical assessment.
  Map<String, double> clinicalScales,

  /// Recording block IDs, ascending.
  List<int> blocks,

  /// Session scale -> block -> value, over the recording blocks.
  Map<String, Map<int, double>> sessionScales,

  /// The last recording row, i.e. the configuration in force at visit end.
  SessionRow? finalRow,

  /// This visit built as if it were its own session report, which is where the
  /// combined table, the electrode diagrams and the programming summary come
  /// from: every field they need is already computed there.
  SessionReportData session,
});

/// Everything the longitudinal builders render.
class LongitudinalReportData {
  const LongitudinalReportData({
    required this.patientId,
    required this.generatedOn,
    required this.visits,
    required this.clinicalChart,
    required this.sessionChart,
    required this.visitTable,
    required this.mismatchedPatients,
  });

  final String patientId;
  final String generatedOn;

  /// Visits in date order, oldest first.
  final List<LongitudinalVisit> visits;

  /// Clinical scales against the visit. No index, no bands; see above.
  final ScalesChartSpec clinicalChart;

  /// Session scales against visit + block.
  final ScalesChartSpec sessionChart;

  /// The per-visit summary: date, programme at visit end, primary scale, delta.
  final List<List<String>> visitTable;

  /// Patient IDs found beyond [patientId]. Non-empty means the import mixed
  /// people, which is a safety issue, not a formatting one.
  final List<String> mismatchedPatients;

  bool get isEmpty => visits.isEmpty;
}

/// Column headers for [LongitudinalReportData.visitTable].
const longitudinalTableHeaders = [
  'Visit',
  'Date',
  'Programme at visit end',
  'Blocks',
  'Primary clinical scale',
  'Change',
];

/// The `run-` entity of a BIDS filename, or ''.
String _runOf(String filename) =>
    RegExp(r'run-([A-Za-z0-9]+)').firstMatch(filename)?.group(1) ?? '';

/// Build one visit from a file's rows.
LongitudinalVisit _visitOf(
  String filename,
  List<SessionRow> rows,
  List<ScalePref> scalePrefs,
) {
  final initial = rows.where((r) => coerceInt(r.isInitial) == 1).toList();
  final recording = rows.where((r) => coerceInt(r.isInitial) != 1).toList();

  // The visit's date is the earliest `acq_time` instant in the file; rows
  // whose instant will not parse are skipped, not sorted as empty strings.
  final dates =
      rows
          .map((r) => recordedDate(r.acqTime))
          .where((d) => d.isNotEmpty)
          .toList()
        ..sort();
  final date = dates.isEmpty ? '' : dates.first;

  double? value(String raw) {
    if (isScaleValueOmitted(raw)) return null;
    final v = double.tryParse(raw.trim());
    return (v == null || !v.isFinite) ? null : v;
  }

  // Clinical scores come from the baseline rows; where a scale appears more
  // than once the LAST wins, so a re-entered score supersedes its predecessor.
  final clinical = <String, double>{};
  for (final row in initial) {
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      final v = value(pair.value);
      if (pair.name.isEmpty || v == null) continue;
      clinical[pair.name] = v;
    }
  }

  final blocks = <int>[];
  final session = <String, Map<int, double>>{};
  for (final row in recording) {
    final block = coerceInt(row.blockId);
    if (!blocks.contains(block)) blocks.add(block);
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      final v = value(pair.value);
      if (pair.name.isEmpty || v == null) continue;
      (session[pair.name] ??= <int, double>{})[block] = v;
    }
  }
  blocks.sort();

  final run = _runOf(filename);
  return (
    filename: filename,
    date: date,
    run: run,
    label: [date.replaceAll('-', ''), if (run.isNotEmpty) run].join('_'),
    clinicalScales: clinical,
    blocks: blocks,
    sessionScales: session,
    finalRow: recording.isEmpty ? null : recording.last,
    session: buildSessionReportData(
      rows: rows,
      scalePrefs: scalePrefs.isEmpty ? null : scalePrefs,
      sourceFile: filename,
    ),
  );
}

/// Build the whole report from the imported files. [files] is filename ->
/// rows in import order; visits are sorted by date here so the figures read
/// left to right in time.
LongitudinalReportData buildLongitudinalReportData({
  required Map<String, List<SessionRow>> files,
  DateTime? generatedAt,

  /// Targets for the per-visit ranking, which the desktop asks for before this
  /// report is built. A TSV records no memory of the targets used when its own
  /// report was made, so they have to be supplied again here.
  List<ScalePref> scalePrefs = const [],
}) {
  final dt = generatedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final generatedOn = '${dt.year}-${two(dt.month)}-${two(dt.day)}';

  final visits = [
    for (final e in files.entries) _visitOf(e.key, e.value, scalePrefs),
  ]..sort((a, b) => a.date.compareTo(b.date));

  // Patient identity. Mixing two people into one longitudinal report is a
  // safety problem, so it is surfaced rather than silently merged.
  final ids =
      files.keys
          .map(extractPatientId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  final patientId = ids.isEmpty ? 'unknown' : ids.first;

  // Figure 1: clinical scales, one point per visit.
  final clinicalSeries = <String, Map<int, double>>{};
  final clinicalLabels = <int, String>{};
  for (final (i, visit) in visits.indexed) {
    clinicalLabels[i] = visit.label;
    visit.clinicalScales.forEach((name, v) {
      (clinicalSeries[name] ??= <int, double>{})[i] = v;
    });
  }

  // Figure 2: session scales, one point per (visit, block).
  //
  // The bands mark the best-scoring block WITHIN each visit, which is what the
  // desktop highlights. That is the only scope the aggregate index supports:
  // it is normalised within a session, so ranking across visits would compare
  // numbers that were never on one scale. See the clinical figure's caption.
  final sessionSeries = <String, Map<int, double>>{};
  final sessionLabels = <int, String>{};
  final bestXs = <int>[];
  final secondXs = <int>[];
  var x = 0;
  for (final visit in visits) {
    for (final (bi, block) in visit.blocks.indexed) {
      // A visit's first block carries the full `{date}_{run}_{block}` and the
      // rest only the block number, so a long session does not repeat its date.
      sessionLabels[x] = bi == 0 ? '${visit.label}_$block' : '$block';
      if (visit.session.bestBlocks.contains(block)) bestXs.add(x);
      if (visit.session.secondBlocks.contains(block)) secondXs.add(x);
      visit.sessionScales.forEach((name, byBlock) {
        final v = byBlock[block];
        if (v != null) (sessionSeries[name] ??= <int, double>{})[x] = v;
      });
      x++;
    }
  }

  // Declared bounds when targets were given, so a scale sits on the same axis
  // at every visit and a drop between visits is a drop rather than a rescale.
  final declared = declaredScaleRange(parseScaleTargets(scalePrefs));

  ScalesChartSpec spec(
    Map<String, Map<int, double>> series,
    Map<int, String> labels,
    String title,
    String xLabel, {
    List<int> best = const [],
    List<int> second = const [],
  }) {
    final xs = <int>{for (final m in series.values) ...m.keys}.toList()..sort();
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final m in series.values) {
      for (final v in m.values) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (!lo.isFinite) {
      lo = 0;
      hi = 1;
    } else if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    if (declared != null) {
      lo = declared.$1;
      hi = declared.$2;
    }
    return ScalesChartSpec(
      series: series,
      amplitude: const {},
      xs: xs,
      yMin: lo,
      yMax: hi,
      // No index SERIES on either figure: it is normalised within a session,
      // so two visits' values share no scale. The desktop passes
      // `show_general_index=False` for the same reason. The bands are a
      // different matter: they mark the best block of one visit.
      aggregateIndex: const {},
      bestXs: best,
      secondXs: second,
      title: title,
      xLabel: xLabel,
      yLabel: 'Scale value',
      xTickLabels: labels,
    );
  }

  // The per-visit table. Its primary clinical scale is the one recorded at the
  // most visits; ties go to the alphabetically first, so the choice is stable
  // across exports.
  final counts = <String, int>{};
  for (final v in visits) {
    for (final name in v.clinicalScales.keys) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  String? primary;
  var best = 0;
  for (final name in counts.keys.toList()..sort()) {
    if (counts[name]! > best) {
      best = counts[name]!;
      primary = name;
    }
  }

  final table = <List<String>>[];
  double? previous;
  for (final (i, visit) in visits.indexed) {
    final score = primary == null ? null : visit.clinicalScales[primary];
    final delta = (score != null && previous != null) ? score - previous : null;
    table.add([
      '${i + 1}',
      visit.date.isEmpty ? 'unknown' : visit.date,
      _programmeText(visit.finalRow),
      '${visit.blocks.length}',
      score == null ? '-' : '${primary!}: ${trimZeros(score)}',
      delta == null ? '-' : '${delta > 0 ? '+' : ''}${trimZeros(delta)}',
    ]);
    if (score != null) previous = score;
  }

  return LongitudinalReportData(
    patientId: patientId,
    generatedOn: generatedOn,
    visits: visits,
    clinicalChart: spec(
      clinicalSeries,
      clinicalLabels,
      'Clinical scales by visit',
      'Visit (date_run)',
    ),
    sessionChart: spec(
      sessionSeries,
      sessionLabels,
      'Session scales by visit and block',
      'Visit and block',
      best: bestXs,
      second: secondXs,
    ),
    visitTable: table,
    mismatchedPatients: ids.length <= 1 ? const [] : ids.skip(1).toList(),
  );
}

/// The stimulation in force at the end of a visit, in one line.
String _programmeText(SessionRow? r) {
  if (r == null) return '-';
  String side(String amp, String freq, String pw) {
    final parts = [
      if (amp.trim().isNotEmpty) '${_sum(amp)} mA',
      if (freq.trim().isNotEmpty) '${freq.trim()} Hz',
      if (pw.trim().isNotEmpty) '${pw.trim()} µs',
    ];
    return parts.isEmpty ? '-' : parts.join('/');
  }

  final group = r.programId.trim();
  return 'L ${side(r.leftAmplitude, r.leftStimFreq, r.leftPulseWidth)}   '
      'R ${side(r.rightAmplitude, r.rightStimFreq, r.rightPulseWidth)}'
      '${group.isEmpty ? '' : '   Group $group'}';
}

/// Sum a possibly-split amplitude, at the device's 0.1 mA resolution.
String _sum(String raw) {
  final parts = raw
      .split('_')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (parts.isEmpty || parts.contains(null)) return raw.trim();
  final total = parts.fold(0.0, (a, b) => a + b!);
  return total.toStringAsFixed(1);
}
