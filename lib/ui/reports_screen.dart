/// Reports and datasets: upload TSVs, then produce whatever they support.
///
/// One entry point instead of two screens, because which one you needed
/// depended on how many files you had, so the choice came before the
/// information needed to make it. Here the actions are always listed and the
/// ones the upload cannot support are disabled with the reason in place of
/// their description, rather than accepting the tap and answering with a
/// snackbar.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

import '../app_info.dart';
import '../core/annotation.dart';
import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/bids_merge.dart';
import '../core/bids_sidecar.dart';
import '../core/electrode/electrode_model.dart';
import '../core/prefs/user_prefs.dart';
import '../core/session/aggregate.dart';
import '../core/session/session_file.dart';
import '../core/session/longitudinal.dart';
import '../core/session/scale_scoring.dart';
import '../core/session/session_row.dart';
import '../core/session/tsv_kind.dart';
import '../core/timestamps.dart';
import '../report/annotations_report.dart';
import '../report/entry_charts.dart';
import '../report/longitudinal_data.dart';
import '../report/longitudinal_pdf.dart';
import '../report/longitudinal_sections.dart';
import '../report/report_data.dart';
import '../report/report_sections.dart';
import '../report/session_docx.dart';
import '../report/session_pdf.dart';
import '../report/upload_actions.dart';
import 'bids_export.dart';
import 'bids_merge_ui.dart';
import 'report_images.dart';
import 'report_sections_dialog.dart';
import 'save_target.dart';
import 'scale_targets_dialog.dart';
import 'scales_chart_painter.dart';
import 'session/entries_table.dart';
import 'session/entry_charts_view.dart';
import 'share_util.dart';
import 'theme.dart';

/// Merge per-file [scaleTimeline]s onto one x-axis. Each file's block indices
/// are offset by the running block count of the files before it, so sessions
/// render sequentially instead of colliding at block 0.
Map<String, Map<int, double>> combinedScaleTimeline(
  Iterable<List<SessionRow>> perFileRows,
) {
  final combined = <String, Map<int, double>>{};
  var offset = 0;
  for (final rows in perFileRows) {
    final timeline = scaleTimeline(rows);
    var maxBlock = -1;
    timeline.forEach((scale, byBlock) {
      final dest = combined.putIfAbsent(scale, () => <int, double>{});
      byBlock.forEach((block, value) {
        dest[block + offset] = value;
        if (block > maxBlock) maxBlock = block;
      });
    });
    offset += maxBlock + 1;
  }
  return combined;
}

/// The on-screen scales timeline, drawn by the painter the report embeds so
/// the screen and the PDF cannot disagree. The x axis is the concatenated
/// block index, so it is only comparable within a visit.
Widget _timelineChart(
  BuildContext context,
  Map<String, Map<int, double>> timeline,
) {
  final theme = Theme.of(context);
  return CustomPaint(
    painter: ScalesChartPainter(
      spec: buildScalesChartSpec(
        timeline: timeline,
        prefs: const [],
        title: '',
        xLabel: 'Block',
        yLabel: 'Scale value',
      ),
      background: theme.colorScheme.surface,
      ink: theme.colorScheme.onSurface,
    ),
    child: const SizedBox.expand(),
  );
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.catalog, this.initialFiles});

  /// Injected by tests and the screenshot build, which have no asset bundle.
  final ElectrodeCatalog? catalog;
  final List<Uploaded>? initialFiles;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final List<Uploaded> _files = chronological(widget.initialFiles ?? []);
  final _exportKey = GlobalKey();

  ElectrodeCatalog? _catalog;
  UserPrefs _prefs = UserPrefs();
  List<ScalePref>? _targets;
  Set<ReportSection> _sections = kAllReportSections;
  Set<LongitudinalSection> _longSections = kDefaultLongitudinalSections;

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog;
    loadUserPrefs().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  List<Uploaded> get _sessions =>
      _files.where((f) => f.kind == TsvKind.programming).toList();

  List<SessionRow> get _rows =>
      _sessions.isEmpty ? const [] : _sessions.single.rows;

  List<Annotation> get _notes => [
    for (final f in _files)
      if (f.kind == TsvKind.notes) ...f.notes,
  ];

  bool get _letter =>
      (_prefs.reportPageSize ?? kDefaultReportPageSize) == 'letter';

  Future<void> _upload() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: FileType.any);
    } catch (e) {
      if (mounted) _snack('Could not open the file picker. ($e)');
      return;
    }
    if (picked.isEmpty) return;

    final added = <Uploaded>[];
    final rejected = <String>[];
    for (final file in picked) {
      if (_files.any((f) => f.name == file.name) ||
          added.any((f) => f.name == file.name)) {
        rejected.add('${file.name} is already uploaded');
        continue;
      }
      final content = await readPickedText(file);
      if (content == null) {
        rejected.add('${file.name} could not be read');
        continue;
      }
      final kind = sniffTsvKind(content);
      switch (kind) {
        case TsvKind.programming:
          added.add((
            name: file.name,
            kind: kind,
            rows: parseSessionTsv(content),
            notes: const [],
          ));
        case TsvKind.notes:
          added.add((
            name: file.name,
            kind: kind,
            rows: const [],
            notes: parseAnnotations(content),
          ));
        case TsvKind.unknown:
        case TsvKind.unreadable:
          rejected.add(tsvKindMismatch(file.name, kind, TsvKind.programming));
      }
    }
    if (!mounted) return;
    if (added.isNotEmpty) {
      setState(() {
        final sorted = chronological([..._files, ...added]);
        _files
          ..clear()
          ..addAll(sorted);
        // A new upload is not the old upload's ranking.
        _targets = null;
      });
    }
    if (rejected.isNotEmpty) _snack(rejected.join('; '));
  }

  Future<void> _editTargets() async {
    final seed =
        _targets ??
        defaultScalePrefsFor([
          for (final f in _sessions)
            ...f.rows.where((r) => coerceInt(r.isInitial) != 1),
        ]);
    if (seed.isEmpty) {
      _snack('The uploaded files have no session scale ratings to rank.');
      return;
    }
    final updated = await showScaleTargetsDialog(context, seed);
    if (updated != null && mounted) setState(() => _targets = updated);
  }

  String? _warn(bool lost) => lost
      ? 'Some characters could not be rendered in the PDF and were replaced '
            'with "?". Add the IBM Plex fonts to assets/fonts/ for full '
            'Unicode, or export to Word instead.'
      : null;

  // ---- Actions ----

  Future<void> _sessionReport({required bool docx}) async {
    final isSession = _sessions.isNotEmpty;
    final source = isSession ? _sessions.single.name : _files.first.name;
    final sections = isSession
        ? await showReportSectionsDialog(
            context,
            _sections,
            onEditTargets: _editTargets,
          )
        : kAllReportSections;
    if (sections == null || !mounted) return;
    if (isSession) setState(() => _sections = sections);

    final subject = BidsName.parse(source)?.subject ?? 'unknown';
    final base = source
        .replaceAll(RegExp(r'\.tsv$'), '')
        .replaceAll(
          RegExp('_(${BidsName.behSuffix}|${BidsName.legacySuffix})\$'),
          '',
        );

    await exportFile(
      context,
      filename: '${base}_report.${docx ? 'docx' : 'pdf'}',
      anchor: _exportKey,
      failureLabel: 'Report export failed',
      build: () async {
        if (!isSession) {
          final data = buildAnnotationsReportData(
            entries: _notes,
            subjectId: subject,
            sourceFile: source,
          );
          if (docx) {
            return (
              bytes: buildAnnotationsDocx(
                data,
                pageSize: _letter ? DocxPageSize.letter : DocxPageSize.a4,
              ),
              warning: null,
            );
          }
          final report = await buildAnnotationsPdf(
            data,
            pageFormat: _letter ? PdfPageFormat.letter : PdfPageFormat.a4,
          );
          return (bytes: report.bytes, warning: _warn(report.lostCharacters));
        }

        final data = buildSessionReportData(
          rows: _rows,
          scalePrefs: _targets,
          sourceFile: source,
          notes: _notes,
        );
        final gfx = await renderReportGraphics(
          data,
          _catalog?.models[electrodeModelIn(_rows)],
          sections,
        );
        if (docx) {
          return (
            bytes: buildSessionDocx(
              data: data,
              subjectId: subject,
              electrodeImages: gfx.electrodes,
              chartPng: gfx.chart,
              pageSize: _letter ? DocxPageSize.letter : DocxPageSize.a4,
              sections: sections,
            ),
            warning: null,
          );
        }
        final report = await buildSessionPdf(
          data: data,
          subjectId: subject,
          electrodeImages: gfx.electrodes,
          chartPng: gfx.chart,
          pageFormat: _letter ? PdfPageFormat.letter : PdfPageFormat.a4,
          sections: sections,
        );
        return (bytes: report.bytes, warning: _warn(report.lostCharacters));
      },
    );
  }

  Future<Uint8List?> _chartPng(ScalesChartSpec spec) async {
    if (spec.isEmpty) return null;
    try {
      return await renderScalesChartPng(spec);
    } catch (e) {
      debugPrint('Longitudinal figure could not be rendered: $e');
      return null;
    }
  }

  Future<void> _longitudinalReport({required bool docx}) async {
    // The desktop asks for both before exporting, and it has to: a TSV carries
    // no record of the targets used when its own report was made.
    final sections = await showLongitudinalSectionsDialog(
      context,
      _longSections,
      onEditTargets: _editTargets,
    );
    if (sections == null || !mounted) return;
    setState(() => _longSections = sections);

    final data = buildLongitudinalReportData(
      files: {for (final f in _sessions) f.name: f.rows},
      scalePrefs: _targets ?? const [],
    );
    if (data.isEmpty) {
      _snack('The uploaded files contain no visits to report.');
      return;
    }
    final name =
        'sub-${BidsName.label(data.patientId)}'
        '_desc-longitudinal_report.${docx ? 'docx' : 'pdf'}';

    await exportFile(
      context,
      filename: name,
      anchor: _exportKey,
      failureLabel: 'Report export failed',
      build: () async {
        final clinical = await _chartPng(data.clinicalChart);
        final session = await _chartPng(data.sessionChart);
        // Four leads a visit, so this is rendered only when asked for.
        final leads = <String, ElectrodeReportImages>{};
        if (sections.contains(LongitudinalSection.electrodes)) {
          for (final visit in data.visits) {
            final gfx = await renderReportGraphics(
              visit.session,
              _catalog?.models[electrodeModelIn(
                _sessions.firstWhere((f) => f.name == visit.filename).rows,
              )],
              const {ReportSection.electrodes},
            );
            if (gfx.electrodes != null) leads[visit.filename] = gfx.electrodes!;
          }
        }
        if (docx) {
          return (
            bytes: buildLongitudinalDocx(
              data: data,
              clinicalChartPng: clinical,
              sessionChartPng: session,
              electrodeImages: leads,
              pageSize: _letter ? DocxPageSize.letter : DocxPageSize.a4,
              sections: sections,
            ),
            warning: null,
          );
        }
        final report = await buildLongitudinalPdf(
          data: data,
          clinicalChartPng: clinical,
          sessionChartPng: session,
          electrodeImages: leads,
          pageFormat: _letter ? PdfPageFormat.letter : PdfPageFormat.a4,
          sections: sections,
        );
        return (bytes: report.bytes, warning: _warn(report.lostCharacters));
      },
    );
  }

  Future<void> _exportAggregate() async {
    final out = buildAggregate([
      for (final f in _sessions) (filename: f.name, rows: f.rows),
    ]);
    if (out.rowCount == 0) {
      _snack(
        out.skipped.isEmpty
            ? 'The uploaded files contain no rows to combine.'
            : 'No uploaded file carries BIDS entities in its name.',
      );
      return;
    }
    final stem = out.subjects.length == 1
        ? '${out.subjects.single}_$aggregateStem'
        : 'study_$aggregateStem';

    await exportFile(
      context,
      filename: '$stem.tsv',
      anchor: _exportKey,
      failureLabel: 'Combined table export failed',
      build: () async => (bytes: utf8.encode(out.tsv), warning: null),
    );
    if (!mounted) return;
    _snack(
      '${out.rowCount} rows from ${out.fileCount} file'
      '${out.fileCount == 1 ? '' : 's'}, '
      '${out.subjects.length} subject${out.subjects.length == 1 ? '' : 's'}.',
    );
    if (out.skipped.isNotEmpty) {
      _snack(
        'Left out: '
        '${out.skipped.map((s) => '${s.filename}: ${s.reason}').join('; ')}',
      );
    }
  }

  /// Fold the uploaded files into a BIDS dataset the user already has.
  ///
  /// The plan is shown and confirmed before a byte is written: this is the one
  /// action here that touches data the app did not create, and it has no undo.
  Future<void> _addToDataset({required bool inPlace}) async {
    final Map<String, dynamic> contract;
    try {
      contract = await loadTsvContract();
    } catch (e) {
      if (mounted) _snack('Could not read the TSV contract: $e');
      return;
    }
    final built = _datasetFiles(contract);
    if (built.files.isEmpty) {
      if (mounted) {
        _snack('No uploaded file carries BIDS entities in its name.');
      }
      return;
    }

    // Writing into the folder, or reading a zip and giving a merged one back.
    final target = inPlace ? await _pickFolderTarget() : await _pickZipTarget();
    if (target == null || !mounted) return;

    final plan = planBidsMerge(target.existing, built.files);
    if (plan.write.isEmpty) {
      _snack(
        plan.refused.isEmpty
            ? 'That dataset already has these files.'
            : 'Nothing to add: ${plan.refused.length} already recorded there.',
      );
      return;
    }
    if (!await confirmMerge(context, plan, target.label) || !mounted) return;

    try {
      await target.apply(plan);
    } catch (e) {
      if (mounted) _snack('The merge stopped partway: $e');
      return;
    }
    if (mounted) _snack(describeMergePlan(plan));
  }

  /// The chosen dataset, and how to write the merge back into it.
  Future<_MergeTarget?> _pickFolderTarget() async {
    final root = await pickDatasetFolder();
    if (root == null) return null;
    try {
      final existing = await readDatasetDirectory(root);
      return (
        existing: existing,
        label: root,
        apply: (MergePlan plan) => applyMergeToDirectory(root, plan),
      );
    } catch (e) {
      if (mounted) _snack('Could not read that folder: $e');
      return null;
    }
  }

  Future<_MergeTarget?> _pickZipTarget() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.any);
    } catch (e) {
      if (mounted) _snack('Could not open the file picker. ($e)');
      return null;
    }
    if (picked == null) return null;
    final size = await picked.length();
    if (size > kMaxMergeZipBytes) {
      // Decoding a dataset that carries imaging would run a tablet out of
      // memory, so it is refused with its size rather than attempted.
      if (mounted) {
        _snack(
          'That dataset is ${(size / (1024 * 1024)).round()} MB. '
          'Merging a zip works up to '
          '${kMaxMergeZipBytes ~/ (1024 * 1024)} MB; use the desktop app.',
        );
      }
      return null;
    }
    try {
      final bytes = await picked.readAsBytes();
      final existing = readDatasetZip(bytes);
      final name = picked.name;
      return (
        existing: existing,
        label: name,
        apply: (MergePlan plan) async {
          if (!mounted) return;
          await exportFile(
            context,
            filename: '${name.replaceAll(RegExp(r'\.zip$'), '')}-merged.zip',
            anchor: _exportKey,
            failureLabel: 'Merged dataset export failed',
            build: () async =>
                (bytes: mergedZip(existing, plan), warning: null),
          );
        },
      );
    } catch (e) {
      if (mounted) _snack('Could not read that dataset: $e');
      return null;
    }
  }

  /// The dataset the uploaded files describe: its entries, the whole file
  /// list, and the names left out for want of BIDS entities.
  ///
  /// Shared by the zip export and the merge, so the two cannot disagree about
  /// what a dataset made from this upload contains.
  ({List<DatasetEntry> entries, List<DatasetFile> files, List<String> skipped})
  _datasetFiles(Map<String, dynamic> contract) {
    final entries = <DatasetEntry>[];
    final skipped = <String>[];
    for (final file in _files) {
      final name = BidsName.parse(file.name);
      if (name == null || name.session.isEmpty) {
        skipped.add(file.name);
        continue;
      }
      final isSession = file.kind == TsvKind.programming;
      entries.add(
        datasetEntry(
          // Re-emitted with the current suffix and column names, so a 0.4.x
          // `_events.tsv` lands in the dataset as a valid `_beh.tsv`.
          name: BidsName(
            subject: name.subject,
            session: name.session,
            task: name.task.isEmpty
                ? (isSession ? 'programming' : 'notes')
                : name.task,
            run: name.run,
          ),
          tsv: isSession
              ? serializeSessionTsv(file.rows)
              : writeAnnotations(file.notes),
          contract: contract,
          kind: isSession ? 'session_tsv' : 'annotation_tsv',
          acqTime: isSession
              ? (file.rows.isEmpty ? '' : file.rows.first.acqTime)
              : (file.notes.isEmpty ? '' : file.notes.first.acqTime),
        ),
      );
    }
    if (entries.isEmpty) {
      return (entries: entries, files: const [], skipped: skipped);
    }

    // The combined table goes where BIDS puts a cross-session derivation: its
    // own directory under `derivatives/`, with its own dataset_description.
    final aggregate = buildAggregate([
      for (final f in _sessions) (filename: f.name, rows: f.rows),
    ]);
    final files = <DatasetFile>[
      ...buildBidsDataset(
        entries,
        appName: appName,
        appVersion: appVersion,
        repoUrl: repoUrl,
      ),
      if (aggregate.rowCount > 0) ...[
        derivativeDescription(
          dir: aggregateDerivativeDir,
          name: '$appName combined sessions',
          appName: appName,
          appVersion: appVersion,
          repoUrl: repoUrl,
        ),
        (
          path: '$aggregateDerivativeDir/$aggregateStem.tsv',
          content: aggregate.tsv,
        ),
        (
          path: '$aggregateDerivativeDir/$aggregateStem.json',
          content: aggregateSidecarJson(contract, appVersion: appVersion),
        ),
      ],
    ];
    return (entries: entries, files: files, skipped: skipped);
  }

  Future<void> _exportBids() async {
    final Map<String, dynamic> contract;
    try {
      contract = await loadTsvContract();
    } catch (e) {
      if (mounted) _snack('BIDS export failed: $e');
      return;
    }
    final built = _datasetFiles(contract);
    if (!mounted) return;
    if (built.entries.isEmpty) {
      _snack('No uploaded file carries BIDS entities in its name.');
      return;
    }
    await exportBidsDataset(
      context,
      anchor: _exportKey,
      entries: built.entries,
      extraFiles: [
        for (final f in built.files)
          if (f.path.startsWith('$aggregateDerivativeDir/')) f,
      ],
    );
    if (mounted && built.skipped.isNotEmpty) {
      _snack(
        'Skipped (no BIDS entities in the filename): '
        '${built.skipped.join(', ')}',
      );
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports and datasets'),
        actions: const [TextSizeButtons(), HelpButton(), ThemeToggleButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _uploadBar(theme),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 8),
              _fileList(theme),
            ],
            const SizedBox(height: 12),
            _actions(theme),
            const Divider(height: 24),
            Expanded(child: _preview(theme)),
          ],
        ),
      ),
    );
  }

  Widget _uploadBar(ThemeData theme) => Row(
    children: [
      FilledButton.icon(
        key: _exportKey,
        onPressed: _upload,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload TSVs'),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(uploadSummary(_files), style: theme.textTheme.bodyMedium),
      ),
      if (_files.isNotEmpty)
        TextButton.icon(
          onPressed: () => setState(() {
            _files.clear();
            _targets = null;
          }),
          icon: const Icon(Icons.clear_all),
          label: const Text('Clear'),
        ),
    ],
  );

  Widget _fileList(ThemeData theme) {
    final mismatch =
        _sessions.length > 1 &&
        !patientIdsMatch(_sessions.map((f) => f.name).toList());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mismatch)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'These files name different patients. A combined table or '
                    'dataset may be what you want; a longitudinal report is '
                    'not, so it stays off.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 140),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final f in _files)
                ListTile(
                  dense: true,
                  leading: Icon(
                    f.kind == TsvKind.programming
                        ? Icons.table_chart_outlined
                        : Icons.sticky_note_2_outlined,
                    size: 20,
                  ),
                  title: Text(f.name, style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    f.kind == TsvKind.programming
                        ? '${blockCount(f.rows)} blocks'
                        : '${f.notes.length} notes',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove',
                    onPressed: () => setState(() {
                      _files.remove(f);
                      _targets = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Every action, always listed. A disabled one shows why in place of its
  /// description, which a menu item cannot do.
  Widget _actions(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final action in _shown)
        _ActionRow(
          action: action,
          reason: unavailableReason(
            action,
            _files,
            canWriteFolder: canWriteChosenFolder,
          ),
          buttons: _buttonsFor(action),
        ),
    ],
  );

  _ActionButton _btn(
    String label,
    Future<void> Function() run, [
    String? unavailable,
  ]) => (label: label, run: run, unavailable: unavailable);

  List<_ActionButton> _buttonsFor(ReportAction action) => switch (action) {
    ReportAction.sessionReport => [
      _btn('PDF', () => _sessionReport(docx: false)),
      _btn('Word', () => _sessionReport(docx: true)),
    ],
    ReportAction.longitudinalReport => [
      _btn('PDF', () => _longitudinalReport(docx: false)),
      _btn('Word', () => _longitudinalReport(docx: true)),
    ],
    ReportAction.aggregateTsv => [_btn('Export', _exportAggregate)],
    ReportAction.bidsDataset => [_btn('Export', _exportBids)],
    // Both ways, so the choice is the user's rather than the platform's:
    // writing into the folder is the point, and a merged zip is the dry run
    // that leaves the original dataset untouched.
    ReportAction.addToDataset => [
      _btn(
        'Add',
        () => _addToDataset(inPlace: true),
        canWriteChosenFolder
            ? null
            : 'A tablet cannot be given a writable folder. Use Export.',
      ),
      _btn('Export', () => _addToDataset(inPlace: false)),
    ],
  };

  static const _shown = ReportAction.values;

  Widget _preview(ThemeData theme) {
    if (_files.isEmpty) {
      return Center(
        child: Text(
          'Upload one or more TSV files to see what can be produced from them.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.disabledColor,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_sessions.length == 1) {
      final rows = _sessions.single.rows;
      return ListView(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${blockCount(rows)} blocks, '
                  '${electrodeModelIn(rows).isEmpty ? 'no model named' : electrodeModelIn(rows)}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _editTargets,
                icon: const Icon(Icons.adjust, size: 18),
                label: Text(
                  _targets == null ? 'Set scale targets' : 'Scale targets',
                ),
              ),
            ],
          ),
          if (_targets == null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'No scale targets are set, so nothing is ranked.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          EntryChartsView(
            data: buildEntryChartData(rows, scalePrefs: _targets ?? const []),
            visibleConfigs: kDefaultVisibleConfigs,
          ),
          SessionEntriesTable(rows: rows),
        ],
      );
    }
    if (_sessions.length > 1) {
      final timeline = combinedScaleTimeline(_sessions.map((f) => f.rows));
      if (timeline.isEmpty) {
        return Center(
          child: Text(
            'No session scale values in the uploaded files.',
            style: theme.textTheme.bodyLarge,
          ),
        );
      }
      return _timelineChart(context, timeline);
    }
    return ListView(
      children: [
        for (final n in _notes.take(50))
          ListTile(
            dense: true,
            leading: Text(
              recordedTime(n.acqTime),
              style: theme.textTheme.bodySmall,
            ),
            title: Text(n.notes),
          ),
      ],
    );
  }
}

/// One offered action: what it makes, and either the buttons to make it or the
/// reason it cannot be made.
/// One button on an action row: what it says, what it does, and why it is off
/// when it is. A per-button reason exists because the two ways of merging do
/// not have the same platform support.
typedef _ActionButton = ({
  String label,
  Future<void> Function() run,
  String? unavailable,
});

/// One offered action: what it makes, and either the buttons to make it or the
/// reason it cannot be made.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.reason,
    required this.buttons,
  });

  final ReportAction action;

  /// Null when the upload supports this action at all.
  final String? reason;
  final List<_ActionButton> buttons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = reason == null;
    final ink = enabled ? null : theme.disabledColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.label,
                  style: theme.textTheme.titleSmall?.copyWith(color: ink),
                ),
                Text(
                  reason ?? action.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled ? theme.colorScheme.onSurfaceVariant : ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          for (final button in buttons) ...[
            Tooltip(
              message: button.unavailable ?? '',
              child: OutlinedButton(
                onPressed: enabled && button.unavailable == null
                    ? button.run
                    : null,
                child: Text(button.label),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// A dataset chosen for a merge: what it already holds, what to call it in the
/// confirmation, and how to write the merge back.
typedef _MergeTarget = ({
  List<DatasetFile> existing,
  String label,
  Future<void> Function(MergePlan plan) apply,
});
