import 'dart:io';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/report/upload_actions.dart';

const exampleFixture =
    'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv';

/// The follow-up visit: the example months later, with lower clinical totals
/// and a few session ratings moved, so the longitudinal figures and the
/// change column show a real change rather than a copy.
const _followUp = {
  '2026-02-03': '2026-09-18',
  '\tY-BOCS\t28\t': '\tY-BOCS\t21\t',
  '\tY-BOCS-o\t15\t': '\tY-BOCS-o\t11\t',
  '\tY-BOCS-c\t13\t': '\tY-BOCS-c\t10\t',
  '\tMADRS\t24\t': '\tMADRS\t17\t',
  '\tObsessions\t8.00\t': '\tObsessions\t6.00\t',
  '\tCompulsions\t7.50\t': '\tCompulsions\t5.50\t',
  '\tObsessions\t7.00\t': '\tObsessions\t5.25\t',
  '\tObsessions\t2.75\t': '\tObsessions\t2.00\t',
};

/// The two visits as they would be on disk: filename to TSV text.
Map<String, String> exampleVisitTexts({
  bool mismatchedPatients = false,
  String root = '.',
}) {
  final source = File('$root/$exampleFixture').readAsStringSync();
  return {
    'sub-01_ses-20260203_task-programming_run-01_beh.tsv': source,
    mismatchedPatients
        ? 'sub-04_ses-20260918_task-programming_run-01_beh.tsv'
        : 'sub-01_ses-20260918_task-programming_run-02_beh.tsv': _followUp
        .entries
        .fold(source, (text, e) => text.replaceAll(e.key, e.value)),
  };
}

/// The committed example, and for more than one visit the follow-up above.
List<Uploaded> exampleVisits({
  bool mismatchedPatients = false,
  int count = 2,
  String root = '.',
}) => [
  for (final e in exampleVisitTexts(
    mismatchedPatients: mismatchedPatients,
    root: root,
  ).entries.take(count))
    (
      name: e.key,
      kind: TsvKind.programming,
      rows: parseSessionTsv(e.value),
      notes: const <Annotation>[],
    ),
];
