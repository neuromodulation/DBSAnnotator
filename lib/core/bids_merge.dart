/// Fold new recordings into a BIDS dataset that already exists.
///
/// [buildBidsDataset] is a CREATE function: it regenerates `participants.tsv`
/// with its own single column and rewrites `dataset_description.json` and the
/// `README` from its own templates. Dropped onto a curated dataset that would
/// silently delete the study's demographic columns, its `Authors` and its
/// `DatasetDOI`, and the result is valid BIDS that passes the validator with no
/// error at all. So a merge classifies every path instead of writing them all,
/// and the classification is the whole feature.
library;

import 'bids_dataset.dart';
import 'tsv.dart';

/// What a merge will do, computed before anything is written.
typedef MergePlan = ({
  /// The files to write, path and final content.
  List<DatasetFile> write,

  /// Paths that did not exist in the target.
  List<String> added,

  /// Index files gaining rows, with the rows they gain.
  List<String> rowMerged,

  /// Paths the target already has that the merge leaves exactly as they are.
  List<String> keptAsIs,

  /// Incoming files refused because the target already holds that path, which
  /// would mean overwriting recorded clinical data.
  List<String> refused,
});

/// Dataset-level files the app generates but must never overwrite: they carry
/// what the lab wrote, not what this app knows.
const Set<String> kCuratedPaths = {
  'dataset_description.json',
  'README',
  'participants.json',
};

bool _isScans(String path) => path.endsWith('_scans.tsv');

/// Plan the merge of [incoming] into the dataset described by [existing].
///
/// Both are whole-dataset file lists, so the caller can read the target from a
/// directory or from a zip and this stays the same function.
MergePlan planBidsMerge(
  List<DatasetFile> existing,
  List<DatasetFile> incoming,
) {
  final have = {for (final f in existing) f.path: f.content};
  final write = <DatasetFile>[];
  final added = <String>[];
  final rowMerged = <String>[];
  final keptAsIs = <String>[];
  final refused = <String>[];

  for (final file in incoming) {
    final path = file.path;
    final current = have[path];

    // Curated: the lab's, so written only when the dataset has none.
    if (kCuratedPaths.contains(path)) {
      if (current == null) {
        write.add(file);
        added.add(path);
      } else {
        keptAsIs.add(path);
      }
      continue;
    }

    // Index files: unioned, never replaced, so columns this app knows nothing
    // about survive.
    if (path == 'participants.tsv' || _isScans(path)) {
      if (current == null) {
        write.add(file);
        added.add(path);
        continue;
      }
      final key = path == 'participants.tsv' ? 'participant_id' : 'filename';
      final merged = _mergeRows(current, file.content, key);
      if (merged == null) {
        keptAsIs.add(path);
      } else {
        write.add((path: path, content: merged));
        rowMerged.add(path);
      }
      continue;
    }

    // Everything else is recorded data. An existing path means this visit is
    // already filed, and overwriting it would replace archived clinical data
    // with whatever was just uploaded.
    if (current == null) {
      write.add(file);
      added.add(path);
    } else if (current == file.content) {
      keptAsIs.add(path);
    } else {
      refused.add(path);
    }
  }

  // Anything the incoming set does not mention is untouched by construction:
  // other datatypes, derivatives, and whatever else the lab keeps here.
  return (
    write: write,
    added: added,
    rowMerged: rowMerged,
    keptAsIs: keptAsIs,
    refused: refused,
  );
}

/// Union two TSV tables on [key], keeping every column either side declares and
/// every row the target already had. Returns null when nothing would change.
///
/// The target's column order leads, so a lab's `participant_id, age, sex` stays
/// in that order and gains nothing but rows. A new row supplies only the
/// columns it knows; the rest are written as the missing-value code by
/// [writeTsvRecords].
String? _mergeRows(String existing, String incoming, String key) {
  final have = parseTsvRecords(existing);
  final want = parseTsvRecords(incoming);
  if (want.isEmpty) return null;

  final columns = <String>[
    ...(_headerOf(existing) ?? const []),
    for (final c in _headerOf(incoming) ?? const [])
      if (!(_headerOf(existing) ?? const []).contains(c)) c,
  ];
  if (columns.isEmpty) return null;

  final seen = {for (final r in have) r[key] ?? ''};
  final extra = [
    for (final r in want)
      if (!seen.contains(r[key] ?? '')) r,
  ];
  if (extra.isEmpty) return null;
  return writeTsvRecords(columns, [...have, ...extra]);
}

/// The column names of a TSV, or null when it has no header row.
List<String>? _headerOf(String tsv) {
  final rows = parseTsv(tsv);
  if (rows.isEmpty || rows.first.isEmpty) return null;
  return [for (final c in rows.first) c.trim()];
}

/// One line describing [plan], for the confirmation shown before it runs.
String describeMergePlan(MergePlan plan) {
  final parts = <String>[
    '${plan.added.length} file${plan.added.length == 1 ? '' : 's'} added',
    if (plan.rowMerged.isNotEmpty)
      '${plan.rowMerged.length} index file'
          '${plan.rowMerged.length == 1 ? '' : 's'} gaining rows',
    if (plan.keptAsIs.isNotEmpty) '${plan.keptAsIs.length} left as is',
    if (plan.refused.isNotEmpty) '${plan.refused.length} refused',
  ];
  return parts.join(' - ');
}
