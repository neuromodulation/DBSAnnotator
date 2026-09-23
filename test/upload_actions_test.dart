/// One case per row of the enablement matrix, which is the feature: the
/// reports screen offers every action and greys out what the upload cannot
/// support, so a wrong answer here is a control that lies.
library;

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/report/upload_actions.dart';
import 'package:flutter_test/flutter_test.dart';

const _row = SessionRow(
  blockId: '1',
  isInitial: '0',
  acqTime: '2026-02-03T09:00:00',
);

Uploaded session(String name) => (
  name: name,
  kind: TsvKind.programming,
  rows: const [_row],
  notes: const <Annotation>[],
);

Uploaded notes(String name) => (
  name: name,
  kind: TsvKind.notes,
  rows: const <SessionRow>[],
  notes: const [Annotation(acqTime: '2026-02-03T09:00:00', notes: 'n')],
);

void main() {
  const a = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
  const b = 'sub-01_ses-20260310_task-programming_run-01_beh.tsv';
  const other = 'sub-02_ses-20260310_task-programming_run-01_beh.tsv';

  test('nothing uploaded leaves every action off', () {
    expect(availableActions(const []), isEmpty);
    for (final action in ReportAction.values) {
      expect(unavailableReason(action, const []), 'Upload a TSV first.');
    }
  });

  test('one session: report and dataset, but not the aggregate', () {
    expect(availableActions([session(a)]), {
      ReportAction.sessionReport,
      ReportAction.bidsDataset,
      ReportAction.addToDataset,
    });
  });

  test('one notes file: the annotations report and a dataset', () {
    expect(
      availableActions([
        notes('sub-01_ses-20260203_task-notes_run-01_beh.tsv'),
      ]),
      {
        ReportAction.sessionReport,
        ReportAction.bidsDataset,
        ReportAction.addToDataset,
      },
    );
  });

  test('two sessions of one patient: everything', () {
    expect(availableActions([session(a), session(b)]), {
      ReportAction.longitudinalReport,
      ReportAction.aggregateTsv,
      ReportAction.bidsDataset,
      ReportAction.addToDataset,
    });
  });

  test(
    'two patients: aggregate and dataset, never the longitudinal report',
    () {
      final files = [session(a), session(other)];
      expect(availableActions(files), {
        ReportAction.aggregateTsv,
        ReportAction.bidsDataset,
        ReportAction.addToDataset,
      });
      // Combining two people into one longitudinal report is a safety problem.
      expect(
        unavailableReason(ReportAction.longitudinalReport, files),
        'These sessions name different patients.',
      );
    },
  );

  test('a session and its notes still count as one session', () {
    final files = [
      session(a),
      notes('sub-01_ses-20260203_task-notes_run-01_beh.tsv'),
    ];
    expect(availableActions(files), contains(ReportAction.sessionReport));
    expect(
      availableActions(files),
      isNot(contains(ReportAction.longitudinalReport)),
    );
  });

  test('several sessions turn the single report off, with a reason', () {
    expect(
      unavailableReason(ReportAction.sessionReport, [session(a), session(b)]),
      'Upload one session TSV; several give a longitudinal report.',
    );
  });

  test('a tablet cannot write into a chosen folder', () {
    expect(
      unavailableReason(ReportAction.addToDataset, [
        session(a),
      ], canWriteFolder: false),
      startsWith('Only on desktop'),
    );
    expect(
      unavailableReason(ReportAction.bidsDataset, [
        session(a),
      ], canWriteFolder: false),
      isNull,
      reason: 'a zip still works everywhere',
    );
  });

  test('a filename with no sub- entity cannot become a dataset path', () {
    final files = [session('my notes export.tsv')];
    expect(
      unavailableReason(ReportAction.bidsDataset, files),
      'No uploaded filename carries a sub- entity.',
    );
    expect(
      unavailableReason(ReportAction.sessionReport, files),
      isNull,
      reason: 'a report needs no entities, it names itself after the file',
    );
  });

  test('the summary names what was uploaded', () {
    expect(uploadSummary(const []), 'No files uploaded.');
    expect(uploadSummary([session(a)]), '1 session');
    expect(uploadSummary([session(a), session(b)]), '2 sessions');
    expect(
      uploadSummary([session(a), notes('sub-01_task-notes_beh.tsv')]),
      '1 session and 1 notes file',
    );
  });
}
