/// What can be produced from a set of uploaded TSVs, and why not when not.
///
/// The reports screen offers every action at once and greys out the ones the
/// upload cannot support, so this decides both the enabled set and the sentence
/// shown in place of a disabled action. Pure, because that table is the
/// feature and it is what the tests pin.
library;

import '../core/annotation.dart';
import '../core/bids.dart';
import '../core/session/longitudinal.dart' show patientIdsMatch;
import '../core/session/session_row.dart';
import '../core/session/tsv_kind.dart';

/// One uploaded file, classified by its header rather than its name.
typedef Uploaded = ({
  String name,
  TsvKind kind,
  List<SessionRow> rows,
  List<Annotation> notes,
});

/// The earliest instant recorded in [file], or null when none parses.
DateTime? earliestRecorded(Uploaded file) {
  DateTime? first;
  for (final at in [
    for (final r in file.rows) r.timestamp,
    for (final n in file.notes) DateTime.tryParse(n.acqTime),
  ]) {
    if (at != null && (first == null || at.isBefore(first))) first = at;
  }
  return first;
}

/// [files] ordered by patient, then from the earliest visit to the most
/// recent, so every preview, report and combined table reads the same way
/// whatever order the files were picked in. A file with no readable time goes
/// last within its patient.
List<Uploaded> chronological(Iterable<Uploaded> files) {
  String patient(Uploaded f) =>
      BidsName.label(BidsName.parse(f.name)?.subject ?? '');
  final keyed = [
    for (final (i, f) in files.indexed) (i: i, f: f, at: earliestRecorded(f)),
  ];
  keyed.sort((a, b) {
    final byPatient = patient(a.f).compareTo(patient(b.f));
    if (byPatient != 0) return byPatient;
    if (a.at != null && b.at != null && a.at != b.at) {
      return a.at!.compareTo(b.at!);
    }
    if ((a.at == null) != (b.at == null)) return a.at == null ? 1 : -1;
    return a.i.compareTo(b.i);
  });
  return [for (final k in keyed) k.f];
}

enum ReportAction {
  sessionReport('Single session report', 'One visit, as PDF or Word.'),
  longitudinalReport('Longitudinal report', 'Change across visits.'),
  aggregateTsv('Combined table (TSV)', 'Every visit in one analysis table.'),
  bidsDataset('BIDS dataset (zip)', 'The files laid out as a dataset.'),
  addToDataset(
    'Add to an existing dataset',
    'File these into a dataset you already have.',
  );

  const ReportAction(this.label, this.description);

  final String label;
  final String description;

  /// What the button says. The merge does not export anything: it writes into
  /// a dataset the user already has, and a button that says otherwise invites
  /// the tap it should not get.
  String get verb => this == ReportAction.addToDataset ? 'Add' : 'Export';
}

List<Uploaded> _programming(List<Uploaded> files) =>
    files.where((f) => f.kind == TsvKind.programming).toList();

List<Uploaded> _notes(List<Uploaded> files) =>
    files.where((f) => f.kind == TsvKind.notes).toList();

/// Files whose name carries the `sub-` entity a dataset path is built from.
List<Uploaded> withBidsEntities(List<Uploaded> files) =>
    files.where((f) => BidsName.parse(f.name) != null).toList();

/// Why [action] cannot run on [files], or null when it can.
///
/// [canWriteFolder] is false on iPadOS and Android, where a picked directory is
/// a security-scoped path or a `content://` URI that `dart:io` cannot write.
/// It changes how a dataset is merged, not whether it can be: those platforms
/// take the existing dataset as a zip and give a new one back.
String? unavailableReason(
  ReportAction action,
  List<Uploaded> files, {
  bool canWriteFolder = true,
}) {
  if (files.isEmpty) return 'Upload a TSV first.';
  final sessions = _programming(files);
  final notes = _notes(files);

  switch (action) {
    case ReportAction.sessionReport:
      if (sessions.length > 1) {
        return 'Upload one session TSV; several give a longitudinal report.';
      }
      if (sessions.isEmpty && notes.isEmpty) {
        return 'Upload a session or notes TSV.';
      }
      return null;

    case ReportAction.longitudinalReport:
      if (sessions.length < 2) return 'Needs two or more session TSVs.';
      if (!patientIdsMatch(sessions.map((f) => f.name).toList())) {
        return 'These sessions name different patients.';
      }
      return null;

    case ReportAction.aggregateTsv:
      if (sessions.length < 2) return 'Needs two or more session TSVs.';
      return null;

    case ReportAction.bidsDataset:
    case ReportAction.addToDataset:
      if (withBidsEntities(files).isEmpty) {
        return 'No uploaded filename carries a sub- entity.';
      }
      return null;
  }
}

/// The actions [files] can produce, in menu order.
Set<ReportAction> availableActions(
  List<Uploaded> files, {
  bool canWriteFolder = true,
}) => {
  for (final a in ReportAction.values)
    if (unavailableReason(a, files, canWriteFolder: canWriteFolder) == null) a,
};

/// One line describing what was uploaded, for the header.
String uploadSummary(List<Uploaded> files) {
  if (files.isEmpty) return 'No files uploaded.';
  final sessions = _programming(files).length;
  final notes = _notes(files).length;
  final parts = <String>[
    if (sessions > 0) '$sessions session${sessions == 1 ? '' : 's'}',
    if (notes > 0) '$notes notes file${notes == 1 ? '' : 's'}',
  ];
  return parts.join(' and ');
}
