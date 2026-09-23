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
      if (action == ReportAction.addToDataset && !canWriteFolder) {
        return 'Only on desktop: a tablet cannot write into a chosen folder.';
      }
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
