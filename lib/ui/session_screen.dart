import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;

import '../core/bids.dart';
import '../core/bids_sidecar.dart';
import '../core/electrode/amplitude.dart';
import '../core/electrode/contact_state.dart';
import '../core/electrode/electrode_model.dart';
import '../core/electrode/stimulation_rule.dart';
import '../core/electrode/tokens.dart';
import '../core/prefs/user_prefs.dart';
import '../core/safe_file.dart';
import '../core/session/authoring.dart';
import '../core/session/scale_presets.dart';
import '../core/session/tsv_kind.dart';
import '../core/session/scale_scoring.dart'
    show ScaleMode, ScalePref, scaleModeFromString;
import '../core/session/session_row.dart';
import '../report/entry_charts.dart';
import '../report/report_data.dart';
import '../report/report_sections.dart';
import '../report/session_docx.dart';
import '../report/session_pdf.dart';
import '../app_info.dart';
import 'amplitude_split.dart';
import 'bids_export.dart';
import 'electrode_view.dart';
import 'list_editor_dialog.dart';
import 'report_images.dart';
import 'report_sections_dialog.dart';
import 'session/entries_table.dart';
import 'session/entry_charts_view.dart';
import 'scale_presets_dialog.dart';
import 'scale_targets_dialog.dart';
import 'save_target.dart';
import 'scale_slider.dart';
import 'share_util.dart';
import 'setting_presets_dialog.dart';
import 'stim_params_form.dart';
import 'theme.dart';

/// Complete-Workflow authoring as the desktop's 4-step wizard
/// (step0..step3_view.py), driven by a Material [Stepper]:
///
/// - Step 0, File: patient/run, start empty or open an existing TSV.
/// - Step 1, Initial configuration: baseline stimulation and clinical scales,
///   inserted as ONE is_initial=1 block.
/// - Step 2, Session scales: define the (name, min, max) scale set that Step 3
///   rates. Nothing is written to the TSV here.
/// - Step 3, Recording: stimulation and one slider/omit row per Step-2 scale,
///   inserted as is_initial=0 blocks; TSV and PDF export.
///
/// Produces the same `task-programming` TSV the desktop writes, via
/// [SessionAuthoring]. Offline pattern as in annotations_screen.dart:
/// in-memory rows, Open via file_picker, Export via share_plus.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    this.catalog,
    this.limits,
    this.scalePresets,
    this.authoring,
  });

  /// Injectable for headless tests; loaded from bundled assets when null.
  final ElectrodeCatalog? catalog;
  final StimLimits? limits;
  final ScalePresets? scalePresets;

  /// Injectable for headless tests so inserted rows can be asserted without
  /// touching platform channels (export/share). A fresh one is created when
  /// null.
  final SessionAuthoring? authoring;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

/// Desktop-identical number formatting: f"{x:.2f}".rstrip("0").rstrip(".").
String _fmtValue(double v) {
  var out = v.toStringAsFixed(2);
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  return out;
}

/// One Step-1 clinical scale row: name + typed numeric score.
class _ClinicalScaleEdit {
  final name = TextEditingController();
  final score = TextEditingController();

  void dispose() {
    name.dispose();
    score.dispose();
  }
}

/// One session scale: defined in Step 2 (name/min/max) and rated in Step 3
/// (slider [value] + [omitted] "not assessed" toggle).
class _SessionScaleEdit {
  _SessionScaleEdit({
    required double min,
    required double max,
    String name = '',
    this.mode = ScaleMode.min,
  }) : value = min {
    this.name.text = name;
    minCtrl.text = _fmtValue(min);
    maxCtrl.text = _fmtValue(max);
  }

  final name = TextEditingController();
  final minCtrl = TextEditingController();
  final maxCtrl = TextEditingController();
  double value;
  bool omitted = false;

  /// How this scale is scored when ranking configurations (the desktop export
  /// dialog's Min / Max / Custom radio). Seeded from the preset's contract cell
  /// and editable via [showScaleTargetsDialog].
  ScaleMode mode;
  double? custom;

  double minOr(double fallback) =>
      double.tryParse(minCtrl.text.trim()) ?? fallback;
  double maxOr(double fallback) =>
      double.tryParse(maxCtrl.text.trim()) ?? fallback;

  void dispose() {
    name.dispose();
    minCtrl.dispose();
    maxCtrl.dispose();
  }
}

/// One side's stimulation inputs (form controllers + electrode contacts).
/// Shared by Step 1 and Step 3, like the desktop keeps the last-used
/// settings when moving between steps.
class _SideInputs {
  final freq = TextEditingController();
  final amp = TextEditingController();
  final pulseWidth = TextEditingController();
  Map<ContactKey, ContactState> states = {};
  ContactState caseState = ContactState.off;
  String validationError = '';

  /// Per-side enable checkbox (desktop's checkable electrode group).
  bool enabled = true;

  /// Amplitude split percentages, aligned to the active cathodes; used to
  /// serialize `left/right_amplitude` when >= 2 cathodes are active.
  List<double> ampSplit = const [];

  void dispose() {
    freq.dispose();
    amp.dispose();
    pulseWidth.dispose();
  }
}

class _SessionScreenState extends State<SessionScreen> {
  late SessionAuthoring _authoring = widget.authoring ?? SessionAuthoring();
  final _subjectCtrl = TextEditingController();
  final _runCtrl = TextEditingController(text: '01');
  // Notes are per-context: the initial-config notes persist across inserts (the
  // user keeps refining them); recording notes clear after each block.
  final _notesInitCtrl = TextEditingController();
  final _notesRecCtrl = TextEditingController();

  /// Side effects observed at the configuration being rated. Folded into the
  /// `notes` cell on insert (see [_recordingNotes]) so no new TSV column is
  /// needed.
  final _sideEffectsCtrl = TextEditingController();
  // Electrode/param state is INDEPENDENT per step: editing the recording config
  // must not change what the initial config shows. The recording pair is seeded
  // once from the initial pair on first entry to the Recording step.
  final _leftInit = _SideInputs();
  final _rightInit = _SideInputs();
  final _leftRec = _SideInputs();
  final _rightRec = _SideInputs();
  bool _recSeeded = false;
  final _clinicalScales = <_ClinicalScaleEdit>[];
  final _sessionScales = <_SessionScaleEdit>[];
  // Removed rows are kept here so their controllers outlive the frame in
  // which their TextField unmounts; disposed with the screen.
  final _removedClinical = <_ClinicalScaleEdit>[];
  final _removedSession = <_SessionScaleEdit>[];

  // Serialised, atomic autosave to the chosen file. See [SafeFileWriter].
  final _writer = SafeFileWriter();

  // Anchor the iPadOS share popover to whichever export button was tapped.
  // See [shareOriginFrom].
  /// Share-popover anchor. ONE key, on the Export button: a menu item is
  /// already unmounted by the time the iPad share sheet asks for its rect, so
  /// three per-item keys could only ever resolve to null.
  final _exportKey = GlobalKey();

  int _currentStep = 0;
  String? _modelName;
  // Chosen save path (from New/Open); when set, inserts autosave to it.
  String? _savePath;
  // True when that path is an iOS sandbox copy rather than the user's own
  // file. See [pickedPathAutosavesToOriginal].
  bool _savePathIsSandboxCopy = false;
  // Currently-applied disease preset, for the selected pill styling.
  String? _selectedClinicalPreset;
  String? _selectedSessionPreset;
  // Selected program name (desktop program combo).
  String? _selectedProgram;
  // Per-user overrides (programs + presets), loaded async.
  UserPrefs _prefs = UserPrefs();
  late final Future<(ElectrodeCatalog, StimLimits, ScalePresets)> _contracts;

  @override
  void initState() {
    super.initState();
    _contracts = _loadContracts();
    loadUserPrefs().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  // Chart data is derived from every inserted row, so it is cached and rebuilt
  // only when the rows actually change. Without this it would be recomputed on
  // every setState -- i.e. on every slider tick in this step -- and, because
  // EntryChartData holds maps with no value equality, every panel would repaint
  // too.
  EntryChartData? _entryChartsCache;
  List<ScalePref>? _entryChartsPrefs;

  EntryChartData _entryCharts() {
    final prefs = _scalePrefs();
    // Also rebuild when the TARGETS change, not only the rows: the bounds set
    // the scales panel's y axis and the modes decide which block is banded, so
    // caching on rows alone left the figure stale after editing either.
    if (_entryChartsCache == null || !listEquals(_entryChartsPrefs, prefs)) {
      _entryChartsPrefs = prefs;
      _entryChartsCache = buildEntryChartData(
        _authoring.rows,
        scalePrefs: prefs,
      );
    }
    return _entryChartsCache!;
  }

  /// Call wherever [_authoring] is mutated, or the figure goes stale.
  void _invalidateEntryCharts() => _entryChartsCache = null;

  /// The optimisation targets for every named session scale: the single input
  /// to both the on-screen ranking and the report's, so the green bands on the
  /// charts and in the document can never point at different blocks.
  List<ScalePref> _scalePrefs() => [
    for (final s in _sessionScales)
      if (s.name.text.trim().isNotEmpty)
        (
          name: s.name.text.trim(),
          min: s.minOr(0),
          max: s.maxOr(10),
          mode: s.mode,
          custom: s.custom,
        ),
  ];

  /// Edit the targets, then push them back onto the Step-2 rows so Step 2, the
  /// figure and the report all stay in agreement.
  Future<void> _editScaleTargets() async {
    final updated = await showScaleTargetsDialog(context, _scalePrefs());
    if (updated == null || !mounted) return;
    final byName = {for (final p in updated) p.name: p};
    setState(() {
      for (final s in _sessionScales) {
        final p = byName[s.name.text.trim()];
        if (p == null) continue;
        s.minCtrl.text = _fmtValue(p.min);
        s.maxCtrl.text = _fmtValue(p.max);
        s.mode = p.mode;
        s.custom = p.custom;
      }
    });
  }

  /// The report content, computed ONCE per export and shared by the graphics
  /// step and both builders, so the two formats cannot disagree and
  /// `DateTime.now()` is read a single time.
  ///
  /// The Step-2 scale bounds and optimisation modes go through as [ScalePref]s.
  /// Without them the report falls back to a 0-10 default, and the chart's
  /// y-axis clamp and the whole ranking ignore what the user typed.
  SessionReportData _reportData() => buildSessionReportData(
    rows: _authoring.rows,
    scalePrefs: _scalePrefs(),
    // Provenance: the report prints which file it came from, so it can be
    // tied back to one run among several of the same session.
    sourceFile: _savePath == null ? '' : pickedBasename(_savePath!),
  );

  /// Report paper size from the user preference, applied to BOTH formats so the
  /// PDF and the Word document always agree.
  bool get _reportLetter =>
      (_prefs.reportPageSize ?? kDefaultReportPageSize) == 'letter';

  /// Effective program names (user override, else the desktop defaults).
  List<String> get _programs => _prefs.programs ?? kDefaultPrograms;

  /// Desktop default electrode (step1_view: preselect "Medtronic SenSight
  /// B33005"), so the L/R canvases render immediately instead of a placeholder.
  static const String kDefaultModel = 'Medtronic SenSight B33005';

  Future<(ElectrodeCatalog, StimLimits, ScalePresets)> _loadContracts() async {
    final catalog = widget.catalog ?? await loadElectrodeCatalog();
    final limits = widget.limits ?? await loadStimLimits();
    final presets = widget.scalePresets ?? await loadScalePresets();
    if (_modelName == null && catalog.models.containsKey(kDefaultModel)) {
      _modelName = kDefaultModel;
    }
    return (catalog, limits, presets);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _runCtrl.dispose();
    _notesInitCtrl.dispose();
    _notesRecCtrl.dispose();
    _sideEffectsCtrl.dispose();
    _leftInit.dispose();
    _rightInit.dispose();
    _leftRec.dispose();
    _rightRec.dispose();
    for (final s in [..._clinicalScales, ..._removedClinical]) {
      s.dispose();
    }
    for (final s in [..._sessionScales, ..._removedSession]) {
      s.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// The `left_amplitude`/`right_amplitude` cell to WRITE for a side: '' when
  /// blank, otherwise the total encoded by encodeAmplitude.
  ///
  /// Named `_encodeAmplitudeCell`, not `_amplitudeCell`, because
  /// report_data.dart has an unrelated `_amplitudeCell` that RENDERS a stored
  /// cell for a report table. Two functions with one name on opposite sides of
  /// the same column invite exactly the wrong assumption.
  static String _encodeAmplitudeCell(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    final v = double.tryParse(t);
    return v == null ? t : encodeAmplitude(v, const []);
  }

  // ---- Insert (Step 1 baseline / Step 3 recording) ----

  /// True when every stim field is blank or within limits; otherwise shows
  /// the blocking snackbar (Step-1 and Step-3 inserts share this guard).
  bool _stimInRange(StimLimits limits, _SideInputs left, _SideInputs right) {
    final outOfRange = [
      rangeError(left.freq.text, limits.frequency),
      rangeError(left.amp.text, limits.amplitude),
      rangeError(left.pulseWidth.text, limits.pulseWidth),
      rangeError(right.freq.text, limits.frequency),
      rangeError(right.amp.text, limits.amplitude),
      rangeError(right.pulseWidth.text, limits.pulseWidth),
    ].whereType<String>();
    if (outOfRange.isNotEmpty) {
      _snack('Fix out-of-range stimulation values before inserting.');
      return false;
    }
    return true;
  }

  /// The 10 stimulation TSV cells from the given L/R inputs (initial or
  /// recording pair).
  Map<String, String> _stimCells(
    ElectrodeCatalog catalog,
    _SideInputs left,
    _SideInputs right,
  ) {
    final model = _modelName == null ? null : catalog.models[_modelName];
    var leftTokens = (anode: '', cathode: '');
    var rightTokens = (anode: '', cathode: '');
    if (model != null) {
      leftTokens = encodeTokens(left.states, left.caseState, model);
      rightTokens = encodeTokens(right.states, right.caseState, model);
    }
    return {
      'left_stim_freq': left.freq.text.trim(),
      'left_anode': leftTokens.anode,
      'left_cathode': leftTokens.cathode,
      'left_amplitude': _amplitudeFor(left, leftTokens),
      'left_pulse_width': left.pulseWidth.text.trim(),
      'right_stim_freq': right.freq.text.trim(),
      'right_anode': rightTokens.anode,
      'right_cathode': rightTokens.cathode,
      'right_amplitude': _amplitudeFor(right, rightTokens),
      'right_pulse_width': right.pulseWidth.text.trim(),
    };
  }

  /// Serialize a side's amplitude: an "a_b" split across cathodes when >= 2 are
  /// active (using the amplitude-split percentages), else the plain total.
  String _amplitudeFor(
    _SideInputs side,
    ({String anode, String cathode}) tokens,
  ) {
    final cathodes = tokens.cathode
        .split('_')
        .where((t) => t.isNotEmpty && t != 'case')
        .toList();
    final total = double.tryParse(side.amp.text.trim());
    if (cathodes.length >= 2 &&
        total != null &&
        side.ampSplit.length == cathodes.length) {
      return encodeAmplitude(total, side.ampSplit);
    }
    return _encodeAmplitudeCell(side.amp.text);
  }

  /// Navigate to [step], seeding the recording config from the initial config
  /// the first time the Recording step (3) is opened, so recording STARTS from
  /// the initial config but is then edited independently. Call inside setState.
  void _goToStep(int step) {
    if (step == 3 && !_recSeeded) {
      _copySide(_leftInit, _leftRec);
      _copySide(_rightInit, _rightRec);
      _recSeeded = true;
    }
    _currentStep = step;
  }

  /// Copy one side's electrode + param state (for seeding recording from
  /// initial). Maps/lists are copied so the two pairs stay independent.
  void _copySide(_SideInputs from, _SideInputs to) {
    to.freq.text = from.freq.text;
    to.amp.text = from.amp.text;
    to.pulseWidth.text = from.pulseWidth.text;
    to.states = Map.of(from.states);
    to.caseState = from.caseState;
    to.enabled = from.enabled;
    to.ampSplit = List.of(from.ampSplit);
  }

  /// Step 1: ONE baseline block (is_initial=1) with the typed clinical
  /// scores, mirroring the desktop write_clinical_scales.
  void _insertBaseline(ElectrodeCatalog catalog, StimLimits limits) {
    if (!_stimInRange(limits, _leftInit, _rightInit)) return;
    _invalidateEntryCharts();
    final inserted = _authoring.addInsert(
      isInitial: true,
      stim: _stimCells(catalog, _leftInit, _rightInit),
      scales: [
        for (final s in _clinicalScales)
          (name: s.name.text.trim(), value: s.score.text.trim()),
      ],
      programId: _selectedProgram ?? '',
      electrodeModel: _modelName ?? '',
      notes: _notesInitCtrl.text.trim(),
    );
    // Initial notes are intentionally NOT cleared, so the user can keep
    // refining the initial-config notes without losing earlier text.
    _autosave();
    _snack(
      'Inserted baseline block ${inserted.first.blockId} '
      '(${inserted.length} row${inserted.length == 1 ? '' : 's'}).',
    );
  }

  /// Step 3: one recording block (is_initial=0). Omitted scales write the
  /// contract literal ("NaN"); rated scales write the slider value with the
  /// desktop formatting.
  void _insertRecording(ElectrodeCatalog catalog, StimLimits limits) {
    if (!_stimInRange(limits, _leftRec, _rightRec)) return;
    _invalidateEntryCharts();
    final inserted = _authoring.addInsert(
      isInitial: false,
      stim: _stimCells(catalog, _leftRec, _rightRec),
      scales: [
        for (final s in _sessionScales)
          (
            name: s.name.text.trim(),
            value: s.omitted
                ? limits.sessionScaleOmittedTsv
                : _fmtValue(s.value),
          ),
      ],
      programId: _selectedProgram ?? '',
      electrodeModel: _modelName ?? '',
      notes: _recordingNotes(),
    );
    setState(() {
      _notesRecCtrl.clear();
      _sideEffectsCtrl.clear();
    });
    _autosave();
    _snack(
      'Inserted recording block ${inserted.first.blockId} '
      '(${inserted.length} row${inserted.length == 1 ? '' : 's'}).',
    );
  }

  /// If a save path was chosen (New/Open), rewrite the TSV to it after each
  /// insert (desktop autosaves every entry). No-op when there is no path.
  ///
  /// Goes through [SafeFileWriter], so overlapping inserts cannot interleave
  /// and a crash mid-write cannot truncate the clinician's only copy.
  Future<void> _autosave() async {
    final path = _savePath;
    if (path == null) return;
    try {
      await _writer.write(path, _authoring.serialize());
    } catch (e) {
      if (mounted) _snack('Autosave failed: $e');
    }
  }

  /// Write the `_beh.json` sidecar beside [tsvPath].
  ///
  /// Best-effort and silent: the sidecar documents the columns for whoever
  /// analyses the file later, so failing to write it must never stop a session
  /// from being recorded. Skipped when one is already there, since its content
  /// depends only on the schema version, not on the session.
  Future<void> _writeSidecar(String tsvPath) async {
    try {
      final json = tsvPath.replaceFirst(RegExp(r'\.tsv$'), '.json');
      if (json == tsvPath || File(json).existsSync()) return;
      final contract = await loadTsvContract();
      await File(
        json,
      ).writeAsString(sessionSidecarJson(contract, appVersion: appVersion));
    } catch (_) {
      // No sidecar is a documentation loss, not a data loss.
    }
  }

  // ---- Open / Export (offline pattern from annotations_screen.dart) ----

  Future<void> _newSession() async {
    final subject = _subjectCtrl.text.trim().isEmpty
        ? '01'
        : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    final name = _bidsName((subject: subject, run: run)).filename;
    // Desktop parity: choose where to create the BIDS TSV before continuing.
    final authoring = SessionAuthoring();
    final NewTsvTarget? target;
    try {
      target = await createNewTsv(
        dialogTitle: 'Create new session TSV',
        fileName: name,
        header: authoring.serialize(), // header only
      );
    } catch (e) {
      if (mounted) _snack('Could not create $name: $e');
      return;
    }
    if (target == null) return; // dialog shown but cancelled
    if (target.fellBack && mounted) {
      _snack('No file dialog available; saved to ${target.location}');
    }
    final p = target.path;
    if (p != null) await _writeSidecar(p);
    if (!mounted) return;
    setState(() {
      _authoring = authoring;
      _savePath = p;
      _savePathIsSandboxCopy = !pickedPathAutosavesToOriginal(p);
      _subjectCtrl.text = subject;
      _runCtrl.text = run;
      _currentStep = 1;
    });
    _snack('New session: ${target.location}');
  }

  Future<void> _open() async {
    // `pickFile`, not `pickFiles`: `allowMultiple` defaults to TRUE, so
    // `pickFiles` here would silently accept a multi-selection.
    final PlatformFile? chosen;
    try {
      chosen = await FilePicker.pickFile(type: FileType.any);
    } catch (e) {
      if (mounted) {
        // On Linux desktop this usually means zenity/kdialog is missing.
        _snack('Could not open the file picker. ($e)');
      }
      return;
    }
    if (chosen == null) return;
    final picked = chosen; // non-nullable, so the setState closure can use it
    final content = await readPickedText(picked);
    if (content == null) {
      if (mounted) _snack('Could not read ${picked.name}.');
      return;
    }
    // Refuse the wrong workflow's file rather than loading it into nothing.
    // `SessionRow.fromMap` is total, so a notes TSV parses into all-empty rows
    // and would open "successfully" with no blocks and no explanation.
    final kind = sniffTsvKind(content);
    if (kind != TsvKind.programming) {
      if (mounted) {
        _snack(tsvKindMismatch(picked.name, kind, TsvKind.programming));
      }
      return;
    }

    _invalidateEntryCharts();
    _authoring.loadExisting(content);
    final bids = BidsName.parse(picked.name);

    // The file names its own electrode model, so the dropdown follows it. A
    // mismatch is not cosmetic: it labels one lead's contacts with another
    // lead's geometry, in the diagrams here and in the report.
    final catalog = (await _contracts).$1;
    final named = electrodeModelIn(_authoring.rows);
    final unknownModel = named.isNotEmpty && !catalog.models.containsKey(named);

    if (!mounted) return;
    setState(() {
      // Autosave future inserts back to the opened file (when a real path).
      _savePath = picked.path;
      _savePathIsSandboxCopy = !pickedPathAutosavesToOriginal(picked.path);
      if (bids != null) {
        _subjectCtrl.text = bids.subject;
        _runCtrl.text = bids.run;
      }
      if (named.isNotEmpty && !unknownModel) _modelName = named;
    });
    final opened =
        'Opened ${picked.name} (${_authoring.rows.length} rows, '
        'next block ${_authoring.blockId}, append ${_authoring.appendId}).';
    _snack(_savePathIsSandboxCopy ? '$opened $sandboxCopyNotice' : opened);
    if (unknownModel) {
      _snack(
        'This file names electrode model "$named", which is not in the '
        'catalogue. The diagrams show ${_modelName ?? 'the selected model'} '
        'instead.',
      );
    }
  }

  /// BIDS labels for a filename: sanitised, because these fields are free text
  /// and become a path component.
  ({String subject, String run}) get _labels {
    final subject = BidsName.label(_subjectCtrl.text.trim());
    final run = BidsName.index(_runCtrl.text.trim());
    return (subject: subject.isEmpty ? 'unknown' : subject, run: run);
  }

  /// The BIDS entities for everything this screen writes: the session TSV, its
  /// sidecar and the report derivative all carry the same ones.
  BidsName _bidsName(({String subject, String run}) labels) => BidsName(
    subject: labels.subject,
    session: BidsName.sessionStamp(DateTime.now()),
    task: 'programming',
    run: labels.run,
  );

  /// Report sections the user last chose (all of them, by default).
  Set<ReportSection> get _sections {
    final saved = _prefs.reportSections;
    if (saved == null) return kAllReportSections;
    final on = {
      for (final s in ReportSection.values)
        if (saved.contains(s.name)) s,
    };
    // An empty saved list would silently produce a title page and nothing else.
    return on.isEmpty ? kAllReportSections : on;
  }

  /// Ask which sections to include, offering the scale targets alongside, since
  /// they are what the ranking inside two of those sections is measured
  /// against. Returns null if the user cancelled the export.
  Future<Set<ReportSection>?> _askSections() async {
    final chosen = await showReportSectionsDialog(
      context,
      _sections,
      onEditTargets: _editScaleTargets,
    );
    if (chosen == null) return null;
    setState(() => _prefs.reportSections = [for (final s in chosen) s.name]);
    saveUserPrefs(_prefs);
    return chosen;
  }

  Future<void> _export() async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting.');
      return;
    }
    await exportFile(
      context,
      filename: _bidsName(_labels).filename,
      anchor: _exportKey,
      build: () async =>
          (bytes: utf8.encode(_authoring.serialize()), warning: null),
    );
  }

  /// Export this session as a one-subject BIDS dataset (zipped).
  ///
  /// The TSV on its own carries BIDS entities in its *name*; this is the tree
  /// those entities describe (`sub-XX/ses-YYYYMMDD/beh/` with the sidecar, a
  /// `dataset_description.json`, a `README`, `participants.tsv` and
  /// `scans.tsv`), which is what a validator and a colleague pooling several
  /// patients actually need.
  Future<void> _exportBids() async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting.');
      return;
    }
    final Map<String, dynamic> contract;
    try {
      contract = await loadTsvContract();
    } catch (e) {
      if (mounted) _snack('BIDS export failed: $e');
      return;
    }
    if (!mounted) return;
    final rows = _authoring.rows;
    await exportBidsDataset(
      context,
      anchor: _exportKey,
      entries: [
        datasetEntry(
          name: _bidsName(_labels),
          tsv: _authoring.serialize(),
          contract: contract,
          kind: 'session_tsv',
          acqTime: rows.isEmpty ? '' : rows.first.acqTime,
        ),
      ],
    );
  }

  /// Build the session report in [format] and share it (mobile) or save it
  /// (desktop). Both formats are built from ONE [SessionReportData] and one
  /// section selection, so they cannot disagree about content.
  Future<void> _exportReport(
    ElectrodeModel? model, {
    required bool docx,
  }) async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting a report.');
      return;
    }
    final sections = await _askSections();
    if (sections == null || !mounted) return;

    final l = _labels;
    // A report is a derivative, not raw data: `_report` is not a BIDS suffix.
    // Built from the same entities as the TSV so the two files sort together,
    // and through the one builder so they cannot drift.
    final filename = _bidsName(
      l,
    ).withSuffix('report', extension: docx ? 'docx' : 'pdf').filename;

    await exportFile(
      context,
      filename: filename,
      anchor: _exportKey,
      failureLabel: 'Report export failed',
      build: () async {
        final data = _reportData();
        // Only rasterise what the chosen sections will actually embed.
        final gfx = await renderReportGraphics(data, model, sections);
        if (docx) {
          return (
            bytes: buildSessionDocx(
              data: data,
              subjectId: l.subject,
              electrodeImages: gfx.electrodes,
              chartPng: gfx.chart,
              pageSize: _reportLetter ? DocxPageSize.letter : DocxPageSize.a4,
              sections: sections,
            ),
            warning: null,
          );
        }
        final report = await buildSessionPdf(
          data: data,
          subjectId: l.subject,
          electrodeImages: gfx.electrodes,
          chartPng: gfx.chart,
          pageFormat: _reportLetter ? PdfPageFormat.letter : PdfPageFormat.a4,
          sections: sections,
        );
        return (
          bytes: report.bytes,
          // Silently altering a clinical note is worse than saying so.
          warning: report.lostCharacters
              ? 'Some characters could not be rendered in the PDF and were '
                    'replaced with "?". Add the IBM Plex fonts to assets/fonts/ '
                    'for full Unicode, or export to Word instead.'
              : null,
        );
      },
    );
  }

  /// One `Export` menu instead of four separate controls.
  ///
  /// Replaces three buttons and a paper-size toggle: the choice is always
  /// "export WHAT, as WHICH format, on WHICH paper", which is a menu, not a row
  /// of buttons that grows every time a format is added.
  Widget _exportMenu(ElectrodeModel? model) => MenuAnchor(
    builder: (context, controller, child) => FilledButton.icon(
      key: _exportKey,
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.ios_share),
      label: const Text('Export'),
    ),
    menuChildren: [
      MenuItemButton(
        leadingIcon: const Icon(Icons.picture_as_pdf),
        onPressed: () => _exportReport(model, docx: false),
        child: const Text('Export report (PDF)'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.description_outlined),
        onPressed: () => _exportReport(model, docx: true),
        child: const Text('Export report (Word)'),
      ),
      const Divider(height: 8),
      MenuItemButton(
        leadingIcon: const Icon(Icons.table_chart_outlined),
        onPressed: _export,
        child: const Text('Export TSV'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.folder_zip_outlined),
        onPressed: _exportBids,
        child: const Text('Export BIDS dataset (zip)'),
      ),
      const Divider(height: 8),
      SubmenuButton(
        leadingIcon: const Icon(Icons.description),
        menuChildren: [
          for (final size in kReportPageSizes)
            MenuItemButton(
              leadingIcon: Icon(
                (_prefs.reportPageSize ?? kDefaultReportPageSize) == size
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onPressed: () {
                setState(() => _prefs.reportPageSize = size);
                saveUserPrefs(_prefs);
              },
              child: Text(size == 'letter' ? 'US Letter' : 'A4'),
            ),
        ],
        child: Text(
          'Paper size: '
          '${(_prefs.reportPageSize ?? kDefaultReportPageSize) == 'letter' ? 'US Letter' : 'A4'}',
        ),
      ),
    ],
  );

  // ---- Shared UI pieces ----

  List<DropdownMenuItem<String>> _modelItems(ElectrodeCatalog catalog) {
    final items = <DropdownMenuItem<String>>[];
    for (final entry in catalog.manufacturers.entries) {
      items.add(
        DropdownMenuItem<String>(
          value: null,
          enabled: false,
          child: Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      for (final name in entry.value) {
        items.add(
          DropdownMenuItem<String>(
            value: name,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(name),
            ),
          ),
        );
      }
    }
    return items;
  }

  /// Two rows: what was delivered on top, what was observed below.
  ///
  /// Row 1 holds the stimulation parameters and the electrode canvases side by
  /// side, because a contact selection and the amplitude that drives it are one
  /// decision. Row 2 holds the scales, the notes and (recording only) side
  /// effects.
  ///
  /// Rows rather than three columns: params, electrodes and
  /// scales-plus-notes would each take a third of the width, which squeezes
  /// the sliders and the notes into one narrow column. The split also matches
  /// the order the work is done in, set the configuration then rate it.
  ///
  /// Portrait/narrow keeps the single stacked column; the rows only appear once
  /// there is width to split.
  Widget _stepBody(
    Widget params,
    Widget electrodes,
    Widget scalesCard,
    TextEditingController notesCtrl, {
    TextEditingController? sideEffectsCtrl,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        // The free-text half of row 2, built once and placed by either branch.
        final freeText = <Widget>[
          if (sideEffectsCtrl != null) _sideEffectsField(sideEffectsCtrl),
          _notesField(notesCtrl),
        ];

        if (c.maxWidth >= 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: the configuration.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: params),
                  const SizedBox(width: 12),
                  Expanded(child: electrodes),
                ],
              ),
              const Divider(height: 28, thickness: 1.2),
              // Row 2: the observations. Scales on the left, the free text on
              // the right, so a long scale list and a long note grow
              // independently instead of pushing each other down.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: scalesCard),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final w in freeText) ...[
                          w,
                          if (w != freeText.last) const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        }
        // Portrait: one column, in the same order.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            params,
            const SizedBox(height: 12),
            electrodes,
            const Divider(height: 28, thickness: 1.2),
            scalesCard,
            // Portrait: no neighbouring column to line up with, so the notes
            // field starts modest and grows with the text instead of filling a
            // height borrowed from the scales card.
            for (final w in [
              if (sideEffectsCtrl != null) _sideEffectsField(sideEffectsCtrl),
              _notesField(notesCtrl),
            ]) ...[const SizedBox(height: 12), w],
          ],
        );
      },
    );
  }

  Widget _modelCard(ElectrodeCatalog catalog) {
    return GroupCard(
      title: 'Electrode',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _modelName,
          isExpanded: true,
          isDense: true,
          hint: const Text('Select model'),
          items: _modelItems(catalog),
          onChanged: (name) => setState(() {
            _modelName = name;
            // ElectrodeView resets on model change; mirror in every captured
            // pair (initial + recording, both sides).
            for (final s in [_leftInit, _rightInit, _leftRec, _rightRec]) {
              s.states = {};
              s.caseState = ContactState.off;
            }
          }),
        ),
      ),
    );
  }

  Widget _programCard() {
    final items = _programs;
    final value = items.contains(_selectedProgram) ? _selectedProgram : null;
    return GroupCard(
      title: 'Program',
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                isDense: true,
                hint: const Text('Select program'),
                items: [
                  for (final p in items)
                    DropdownMenuItem<String>(value: p, child: Text(p)),
                ],
                onChanged: (p) => setState(() => _selectedProgram = p),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            tooltip: 'Edit programs',
            onPressed: _editPrograms,
          ),
        ],
      ),
    );
  }

  /// Edit + persist the program-name list (desktop program editor).
  Future<void> _editPrograms() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => ListEditorDialog(
        title: 'Programs',
        items: List<String>.of(_programs),
      ),
    );
    if (result == null) return;
    _prefs.programs = result;
    await saveUserPrefs(_prefs);
    if (!mounted) return;
    setState(() {
      if (!result.contains(_selectedProgram)) _selectedProgram = null;
    });
  }

  /// Active cathode labels for [side] (from the encoded cathode string), which
  /// drive the amplitude-split rows.
  List<String> _cathodesFor(_SideInputs side, ElectrodeModel? model) {
    if (model == null) return const [];
    final cathode = encodeTokens(side.states, side.caseState, model).cathode;
    return cathode
        .split('_')
        .where((t) => t.isNotEmpty && t != 'case')
        .toList();
  }

  /// Column 1 item: one side's stim params + its amplitude split.
  Widget _paramsCard(
    String title,
    _SideInputs side,
    ElectrodeModel? model,
    StimLimits limits,
  ) {
    final card = GroupCard(
      title: side.enabled ? title : '$title (off)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StimParamsForm(
            limits: limits,
            frequency: side.freq,
            amplitude: side.amp,
            pulseWidth: side.pulseWidth,
          ),
          // Rebuild only the split when the amplitude controller changes, so
          // the per-cathode mA labels track edits from typing, the steppers,
          // and the preset chips (all mutate side.amp) without rebuilding the
          // heavy electrode canvas.
          ListenableBuilder(
            listenable: side.amp,
            builder: (context, _) => AmplitudeSplit(
              cathodes: _cathodesFor(side, model),
              total: double.tryParse(side.amp.text.trim()) ?? 0,
              decimals: limits.amplitudeDecimals,
              onChanged: (pct) => side.ampSplit = pct,
            ),
          ),
        ],
      ),
    );
    // Deselecting a side's electrode dims its parameters as an "off" hint, but
    // they stay editable (locking input just blocked typing / preset chips).
    return Opacity(opacity: side.enabled ? 1 : 0.6, child: card);
  }

  /// Column 1: model (Step 1 only) + program + Left/Right param groups.
  Widget _paramsColumn(
    ElectrodeCatalog catalog,
    ElectrodeModel? model,
    StimLimits limits, {
    required bool withModel,
    required _SideInputs left,
    required _SideInputs right,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (withModel) ...[_modelCard(catalog), const SizedBox(height: 12)],
        _programCard(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Parameters',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings, size: 18),
              tooltip: 'Edit parameter presets',
              onPressed: () => _editStimPresets(limits),
            ),
          ],
        ),
        _paramsCard('Left', left, model, limits),
        const SizedBox(height: 12),
        _paramsCard('Right', right, model, limits),
      ],
    );
  }

  /// Edit + persist the stimulation quick-pick preset lists via the desktop
  /// "Edit Setting Presets" dialog (3 tabs: Frequency / Amplitude / Pulse
  /// width). Seeded from the effective [limits] presets; saved to [UserPrefs]
  /// so the StimParamsForm chips update live (via withPresets) and persist.
  Future<void> _editStimPresets(StimLimits limits) async {
    final result = await showSettingPresetsDialog(
      context,
      limits: limits,
      frequencies: limits.frequencyPresets,
      amplitudes: limits.amplitudePresets,
      pulseWidths: limits.pulseWidthPresets,
    );
    if (result == null) return;
    setState(() {
      _prefs.stimFrequencies = result.frequencies;
      _prefs.stimAmplitudes = result.amplitudes;
      _prefs.stimPulseWidths = result.pulseWidths;
    });
    await saveUserPrefs(_prefs);
  }

  /// Desktop validation box: green "valid" or a red-bordered "invalid".
  Widget _validationBox(_SideInputs side) {
    final ok = side.validationError.isEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: ok
          ? null
          : BoxDecoration(
              border: Border.all(color: DbsColors.invalid, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
      // An Icon, not a literal U+2713 in the string. A bare tick renders only
      // if the active font happens to carry that codepoint; on the platforms
      // this app targets it is often supplied by an OS fallback font, so it can
      // come out as an empty box. The icon font is bundled with the app.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 14,
            color: ok ? DbsColors.valid : DbsColors.invalid,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              ok ? 'Configuration valid' : 'Invalid: ${side.validationError}',
              style: TextStyle(
                color: ok ? DbsColors.valid : DbsColors.invalid,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One electrode pane: enable checkbox + the canvas (dimmed when disabled) +
  /// the validation box.
  Widget _electrodePane(String title, _SideInputs side, ElectrodeModel? model) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Checkbox(
              value: side.enabled,
              onChanged: (v) => setState(() => side.enabled = v ?? true),
            ),
            Text(title),
          ],
        ),
        SizedBox(
          // Grow with the window so maximizing enlarges the canvas (and its
          // contacts / ring caps, easing taps); floored for small screens.
          height: (MediaQuery.sizeOf(context).height * 0.55).clamp(
            320.0,
            900.0,
          ),
          child: model == null
              ? const Center(child: Text('Select an electrode model'))
              : Opacity(
                  opacity: side.enabled ? 1 : 0.3,
                  child: IgnorePointer(
                    ignoring: !side.enabled,
                    child: ElectrodeView(
                      model: model,
                      // Remounted on step switch; seed with captured config.
                      initialStates: side.states,
                      initialCaseState: side.caseState,
                      onChanged: (states, caseState) => setState(() {
                        side.states = states;
                        side.caseState = caseState;
                      }),
                      onValidation: (valid, error) => setState(
                        () => side.validationError = valid ? '' : error,
                      ),
                    ),
                  ),
                ),
        ),
        _validationBox(side),
      ],
    );
  }

  Widget _legend() {
    Widget swatch(Color base, Color border, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 12,
          decoration: BoxDecoration(
            color: base,
            border: Border.all(color: border),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 4,
      children: [
        swatch(DbsColors.offBase, DbsColors.offBorder, 'Off'),
        swatch(DbsColors.anodicBase, DbsColors.anodicBorder, 'Anodic (+)'),
        swatch(
          DbsColors.cathodicBase,
          DbsColors.cathodicBorder,
          'Cathodic (-)',
        ),
      ],
    );
  }

  /// Column 2: the two electrode canvases side by side + legend.
  Widget _electrodesColumn(
    ElectrodeModel? model,
    _SideInputs left,
    _SideInputs right,
  ) {
    return GroupCard(
      title: 'Electrodes',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _electrodePane('Left', left, model)),
              const SizedBox(width: 8),
              Expanded(child: _electrodePane('Right', right, model)),
            ],
          ),
          const SizedBox(height: 8),
          _legend(),
        ],
      ),
    );
  }

  /// Side effects for the configuration being rated (recording step only).
  ///
  /// A separate box because a side effect is not a note: it is the
  /// adverse-event record for that configuration, and a general Notes field
  /// buries the only tolerability data the session captures. Its own labelled
  /// field also lets the report lift it out.
  ///
  /// It is written into the `notes` COLUMN with a `Side effects:` prefix rather
  /// than a new TSV column, so the file stays readable by the desktop app
  /// unchanged. A dedicated column (with side, amplitude at onset, severity and
  /// whether it resolved) is the proper fix and needs a schema round.
  Widget _sideEffectsField(TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      maxLines: 3,
      minLines: 2,
      decoration: const InputDecoration(
        labelText: 'Side effects (if any)',
        hintText: 'e.g. paraesthesia left hand, resolved at 3.0 mA',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
        prefixIcon: Icon(Icons.warning_amber_outlined, size: 20),
      ),
    );
  }

  /// The `notes` cell for a recording insert: the side effects first, then the
  /// free notes, so the tolerability line is never lost at the end of a long
  /// paragraph. Either half may be empty.
  String _recordingNotes() {
    final effects = _sideEffectsCtrl.text.trim();
    final notes = _notesRecCtrl.text.trim();
    return [
      if (effects.isNotEmpty) 'Side effects: $effects',
      if (notes.isNotEmpty) notes,
    ].join('\n');
  }

  /// The Notes field, given a generous viewport-relative height so it has real
  /// room. The Stepper scrolls when the column is taller than the window, so
  /// this never overflows on short desktop windows (`expands` needs the bounded
  /// box the SizedBox provides).
  Widget _notesField(TextEditingController notesCtrl) {
    return SizedBox(
      height: (MediaQuery.sizeOf(context).height * 0.3).clamp(180.0, 600.0),
      child: TextField(
        controller: notesCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          labelText: 'Notes',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
    );
  }

  // ---- Step 0: File ----

  Widget _fileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                  labelText: 'Patient ID (sub-)',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _runCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Run',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _newSession,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open existing TSV'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _authoring.rows.isEmpty
              ? 'Empty session. The first insert is block 0.'
              : '${_authoring.rows.length} rows loaded; next block '
                    '${_authoring.blockId}, append ${_authoring.appendId}.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ---- Step 1: Initial configuration ----

  /// Replace the clinical rows with a disease preset's scale names, like
  /// the desktop Step-1 pills. If the same disease exists as a session preset,
  /// also preselect + load it so Step 2 arrives already configured (the user
  /// asked for clinical->session category sync).
  void _applyClinicalPreset(
    String preset,
    ScalePresets presets,
    StimLimits limits,
  ) {
    setState(() {
      _selectedClinicalPreset = preset;
      _removedClinical.addAll(_clinicalScales);
      _clinicalScales.clear();
      for (final name in clinicalRows(presets, preset)) {
        _clinicalScales.add(_ClinicalScaleEdit()..name.text = name);
      }
      if (presets.session.containsKey(preset)) {
        _loadSessionPresetRows(preset, presets, limits);
      }
    });
  }

  /// Edit + persist the clinical scale presets via the desktop-style group
  /// editor (all disease groups → scale names). [presets] is the effective
  /// (defaults + overrides) set; the result replaces `UserPrefs.clinical` and
  /// is merged live via mergeScalePresets in build().
  Future<void> _editClinicalPresets(ScalePresets presets) async {
    final edited = await showClinicalPresetsDialog(
      context,
      presets: presets.clinical,
    );
    if (edited == null) return;
    setState(() => _prefs.clinical = edited);
    await saveUserPrefs(_prefs);
    if (mounted) _snack('Clinical scale presets saved.');
  }

  /// Edit and persist the session scale presets via the group editor: all
  /// disease groups, (name,min,max) rows, report mode preserved.
  Future<void> _editSessionPresets(ScalePresets presets) async {
    final edited = await showSessionPresetsDialog(
      context,
      presets: presets.session,
    );
    if (edited == null) return;
    setState(() => _prefs.session = edited);
    await saveUserPrefs(_prefs);
    if (mounted) _snack('Session scale presets saved.');
  }

  /// Disease preset pill styled to match the desktop QSS: amber fill by
  /// default; selected = darker fill + 2px border + bold.
  Widget _presetChip(String preset, bool selected, VoidCallback onTap) {
    // Default = the plain Material chip look; selected = a light accent tint +
    // a bolder accent border + bold label (no full amber fill).
    return ChoiceChip(
      label: Text(preset),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: DbsColors.accent.withValues(alpha: 0.2),
      side: selected
          ? const BorderSide(color: DbsColors.accent, width: 2)
          : null,
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _clinicalScalesCard(ScalePresets presets, StimLimits limits) {
    return Card(
      // Warm fill + outline to match GroupCard (dark-safe; no M3 blue).
      color: DbsColors.cardFill(
        Theme.of(context).brightness == Brightness.dark,
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Clinical scales',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings clinical scales',
                  onPressed: () => _editClinicalPresets(presets),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add clinical scale',
                  onPressed: () =>
                      setState(() => _clinicalScales.add(_ClinicalScaleEdit())),
                ),
              ],
            ),
            if (presets.buttons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                // Desktop disease pills: tapping one REPLACES the rows with
                // that preset's clinical scale names.
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in presets.buttons)
                      _presetChip(
                        preset,
                        _selectedClinicalPreset == preset,
                        () => _applyClinicalPreset(preset, presets, limits),
                      ),
                  ],
                ),
              ),
            for (final scale in _clinicalScales)
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: scale.name,
                      decoration: const InputDecoration(
                        labelText: 'Scale name',
                        isDense: true,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: TextField(
                        controller: scale.score,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Score',
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove clinical scale',
                    onPressed: () => setState(() {
                      _clinicalScales.remove(scale);
                      _removedClinical.add(scale);
                    }),
                  ),
                ],
              ),
            if (_clinicalScales.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No scales. The insert writes one scale-less '
                  'row (like the desktop).',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _initialStep(
    ElectrodeCatalog catalog,
    StimLimits limits,
    ScalePresets presets,
    ElectrodeModel? model,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepBody(
          _paramsColumn(
            catalog,
            model,
            limits,
            withModel: true,
            left: _leftInit,
            right: _rightInit,
          ),
          _electrodesColumn(model, _leftInit, _rightInit),
          _clinicalScalesCard(presets, limits),
          _notesInitCtrl,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _insertBaseline(catalog, limits),
          icon: const Icon(Icons.add),
          label: const Text('Insert baseline'),
        ),
      ],
    );
  }

  // ---- Step 2: Session scales (definition only, no TSV write) ----

  /// Replace the session scale set with a disease preset's (name, min, max)
  /// rows, like the desktop Step-2 pills.
  void _applySessionPreset(
    String preset,
    ScalePresets presets,
    StimLimits limits,
  ) {
    setState(() => _loadSessionPresetRows(preset, presets, limits));
  }

  /// Mutating helper (call inside a setState): swap the session scale set to a
  /// preset's rows. Shared by the Step-2 pills and the clinical->session sync.
  void _loadSessionPresetRows(
    String preset,
    ScalePresets presets,
    StimLimits limits,
  ) {
    final fallback = limits.sessionScale;
    _selectedSessionPreset = preset;
    _removedSession.addAll(_sessionScales);
    _sessionScales.clear();
    for (final row in sessionRows(presets, preset)) {
      _sessionScales.add(
        _SessionScaleEdit(
          min: double.tryParse(row.min) ?? fallback.min,
          max: double.tryParse(row.max) ?? fallback.max,
          name: row.name,
          mode: scaleModeFromString(row.mode),
        ),
      );
    }
  }

  Widget _scalesStep(StimLimits limits, ScalePresets presets) {
    final range = limits.sessionScale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Session scales configuration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings session scales',
              onPressed: () => _editSessionPresets(presets),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add session scale',
              onPressed: () => setState(
                () => _sessionScales.add(
                  _SessionScaleEdit(min: range.min, max: range.max),
                ),
              ),
            ),
          ],
        ),
        if (presets.buttons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // Desktop disease pills: tapping one REPLACES the set with that
            // preset's (name, min, max) rows.
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in presets.buttons)
                  _presetChip(
                    preset,
                    _selectedSessionPreset == preset,
                    () => _applySessionPreset(preset, presets, limits),
                  ),
              ],
            ),
          ),
        for (final scale in _sessionScales)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: scale.name,
                  decoration: const InputDecoration(
                    labelText: 'Scale name',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: scale.minCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Min',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: scale.maxCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Max',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Remove session scale',
                onPressed: () => setState(() {
                  _sessionScales.remove(scale);
                  _removedSession.add(scale);
                }),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _sessionScales.isEmpty
                ? 'No session scales. Recording inserts write one '
                      'scale-less row (like the desktop).'
                : 'These scales are rated in the Recording step; nothing is '
                      'written to the TSV here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  // ---- Step 3: Recording ----

  /// One rating row: name, 0.5-step slider bounded by the Step-2 min/max,
  /// current value, and the omit ("not assessed") switch. Omitted rows are
  /// written as the contract literal ("NaN").
  Widget _ratingRow(_SessionScaleEdit scale, StimLimits limits) {
    final min = scale.minOr(limits.sessionScale.min);
    var max = scale.maxOr(limits.sessionScale.max);
    if (max <= min) max = min + 1;
    final name = scale.name.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(name.isEmpty ? '(unnamed scale)' : name),
          ),
          Expanded(
            flex: 5,
            // Desktop ScaleProgressWidget: bar, value, chevrons, X-omit. Any
            // move re-includes an omitted scale.
            child: ScaleSlider(
              value: scale.value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              omitted: scale.omitted,
              onChanged: (v) => setState(() {
                scale.value = v;
                scale.omitted = false;
              }),
              onOmitToggle: () =>
                  setState(() => scale.omitted = !scale.omitted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingsCard(StimLimits limits) {
    return Card(
      // Warm fill + outline to match GroupCard (dark-safe; no M3 blue).
      color: DbsColors.cardFill(
        Theme.of(context).brightness == Brightness.dark,
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Session scale ratings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_sessionScales.isEmpty)
              const Text(
                'No session scales defined. Add them in the '
                'Session scales step.',
              )
            else
              for (final scale in _sessionScales) _ratingRow(scale, limits),
          ],
        ),
      ),
    );
  }

  /// Review table of every inserted TSV row (one row per scale), so the user
  /// can check what has been recorded instead of only the transient snackbars.
  Widget _recordingStep(
    ElectrodeCatalog catalog,
    StimLimits limits,
    ElectrodeModel? model,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepBody(
          _paramsColumn(
            catalog,
            model,
            limits,
            withModel: false,
            left: _leftRec,
            right: _rightRec,
          ),
          _electrodesColumn(model, _leftRec, _rightRec),
          _ratingsCard(limits),
          _notesRecCtrl,
          sideEffectsCtrl: _sideEffectsCtrl,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _insertRecording(catalog, limits),
          icon: const Icon(Icons.add),
          label: const Text('Insert recording block'),
        ),
        const SizedBox(height: 8),
        if (_savePathIsSandboxCopy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              sandboxCopyNotice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        _exportMenu(model),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(
              child: Text(
                'Inserted entries (append ${_authoring.appendId})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _editScaleTargets,
              icon: const Icon(Icons.adjust, size: 18),
              label: const Text('Scale targets'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Charts are always visible and the table collapses beneath them: a
        // toggle would hide one view and make the user remember which mode they
        // are in, and the panels ARE the table's numeric columns plotted.
        EntryChartsView(
          data: _entryCharts(),
          order: _prefs.entryPanelOrder,
          onOrderChanged: (ids) {
            setState(() => _prefs.entryPanelOrder = ids);
            saveUserPrefs(_prefs);
          },
          visibleConfigs: _prefs.entryVisibleConfigs ?? kDefaultVisibleConfigs,
          onVisibleConfigsChanged: (n) {
            setState(() => _prefs.entryVisibleConfigs = n);
            saveUserPrefs(_prefs);
          },
          bestXs: _entryCharts().bestXs,
          secondXs: _entryCharts().secondXs,
        ),
        Theme(
          // Drop the ExpansionTile's default divider lines so it reads as part
          // of the figure above rather than a separate card.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            // Expanded by default: the table is what the user had before the
            // charts were added, so hiding it would be a silent removal. The
            // choice is persisted, so collapsing it sticks.
            initiallyExpanded: _prefs.entryTableExpanded ?? true,
            onExpansionChanged: (open) {
              _prefs.entryTableExpanded = open;
              saveUserPrefs(_prefs);
            },
            title: Text(
              'Table of all entries '
              '(${blockCount(_authoring.rows)} blocks)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [SessionEntriesTable(rows: _authoring.rows)],
          ),
        ),
      ],
    );
  }

  // ---- Wizard scaffold ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete workflow'),
        actions: const [TextSizeButtons(), HelpButton(), ThemeToggleButton()],
      ),
      body: FutureBuilder<(ElectrodeCatalog, StimLimits, ScalePresets)>(
        future: _contracts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load schema contracts: '
                '${snapshot.error}',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (catalog, rawLimits, rawPresets) = snapshot.data!;
          // Layer the user's saved overrides (F7) over the bundled contract so
          // edited presets show immediately and survive relaunch.
          final limits = rawLimits.withPresets(
            frequencies: _prefs.stimFrequencies,
            amplitudes: _prefs.stimAmplitudes,
            pulseWidths: _prefs.stimPulseWidths,
          );
          final presets = mergeScalePresets(rawPresets, _prefs);
          final model = _modelName == null ? null : catalog.models[_modelName];
          // Only the active step builds its (heavy) content: keeps one
          // ElectrodeView / one Notes field per side in the tree at a time,
          // so state lives in _SessionScreenState, not in step widgets.
          Widget when(int step, Widget Function() builder) =>
              _currentStep == step ? builder() : const SizedBox.shrink();
          return Stepper(
            currentStep: _currentStep,
            onStepTapped: (i) => setState(() => _goToStep(i)),
            onStepContinue: _currentStep < 3
                ? () => setState(() => _goToStep(_currentStep + 1))
                : null,
            onStepCancel: _currentStep > 0
                ? () => setState(() => _currentStep -= 1)
                : null,
            controlsBuilder: (context, details) {
              if (details.stepIndex != _currentStep) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    if (details.onStepContinue != null)
                      FilledButton.tonal(
                        onPressed: details.onStepContinue,
                        child: const Text('Next'),
                      ),
                    if (details.onStepContinue != null &&
                        details.onStepCancel != null)
                      const SizedBox(width: 8),
                    if (details.onStepCancel != null)
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: const Text('Back'),
                      ),
                  ],
                ),
              );
            },
            steps: [
              Step(
                title: const Text('File'),
                subtitle: const Text('Patient / run: new or open TSV'),
                isActive: _currentStep == 0,
                content: when(0, _fileStep),
              ),
              Step(
                title: const Text('Initial configuration'),
                subtitle: const Text(
                  'Baseline stimulation + clinical scales (is_initial 1)',
                ),
                isActive: _currentStep == 1,
                content: when(
                  1,
                  () => _initialStep(catalog, limits, presets, model),
                ),
              ),
              Step(
                title: const Text('Session scales configuration'),
                subtitle: const Text(
                  'Define the scale set rated during recording',
                ),
                isActive: _currentStep == 2,
                content: when(2, () => _scalesStep(limits, presets)),
              ),
              Step(
                title: const Text('Recording'),
                subtitle: const Text(
                  'Stimulation + ratings (is_initial 0), export',
                ),
                isActive: _currentStep == 3,
                content: when(3, () => _recordingStep(catalog, limits, model)),
              ),
            ],
          );
        },
      ),
    );
  }
}
