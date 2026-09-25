/// Notes recorded alongside a session appear in its data table, placed by
/// their own clock time.
///
/// A note carries no configuration, so it gets its own row with only the Time
/// and Notes cells filled: writing it into a block's row would assert it was
/// recorded against that configuration, which the file does not say.
library;

import 'dart:io';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixture =
    'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv';

List<String> _timeColumn(SessionReportData d) => [
  for (final row in d.tableData) row[1].split('\n').first.trim(),
];

int _notesIndex = sessionTableHeaders.length - 1;

void main() {
  final rows = parseSessionTsv(File(_fixture).readAsStringSync());

  test('the last column is Notes, which is where a note belongs', () {
    expect(sessionTableHeaders.last, 'Notes');
  });

  test('with no notes file the table is unchanged', () {
    final without = buildSessionReportData(rows: rows);
    final withEmpty = buildSessionReportData(rows: rows, notes: const []);
    expect(withEmpty.tableData, without.tableData);
  });

  test('a note becomes its own row, time and note only', () {
    final data = buildSessionReportData(
      rows: rows,
      notes: const [
        Annotation(
          acqTime: '2026-02-03T09:06:00+00:00',
          notes: 'patient asked for a break',
        ),
      ],
    );
    final row = data.tableData.firstWhere(
      (r) => r[_notesIndex] == 'patient asked for a break',
    );
    expect(row[1], '09:06:00');
    // Every stimulation and scale cell is blank: the note is not attributed to
    // a configuration it was not recorded against.
    for (final i in [0, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      expect(row[i], isEmpty, reason: 'column $i of ${sessionTableHeaders[i]}');
    }
  });

  test('notes land between the blocks they fall between', () {
    // The fixture records blocks at 09:03:20, 09:05:05, 09:07:40, ...
    final data = buildSessionReportData(
      rows: rows,
      notes: const [
        Annotation(acqTime: '2026-02-03T09:06:00+00:00', notes: 'mid note'),
      ],
    );
    final times = _timeColumn(data);
    final at = data.tableData.indexWhere((r) => r[_notesIndex] == 'mid note');
    expect(at, greaterThan(0));
    // Ordered by the clock, which is the only relation the two files record.
    final before = times.sublist(0, at).where((t) => t.isNotEmpty).last;
    final after = times.sublist(at + 1).firstWhere((t) => t.isNotEmpty);
    expect(before.compareTo('09:06:00'), lessThan(0));
    expect(after.compareTo('09:06:00'), greaterThan(0));
  });

  test('a note with no readable time or no text is dropped', () {
    final data = buildSessionReportData(
      rows: rows,
      notes: const [
        Annotation(acqTime: 'n/a', notes: 'unplaceable'),
        Annotation(acqTime: '2026-02-03T09:06:00+00:00', notes: '   '),
      ],
    );
    expect(
      data.tableData.any((r) => r[_notesIndex] == 'unplaceable'),
      isFalse,
      reason: 'a note with no instant cannot be placed on a time axis',
    );
    expect(
      data.tableData,
      hasLength(buildSessionReportData(rows: rows).tableData.length),
    );
  });

  test('every block row survives the interleave', () {
    final plain = buildSessionReportData(rows: rows).tableData;
    final mixed = buildSessionReportData(
      rows: rows,
      notes: const [
        Annotation(acqTime: '2026-02-03T09:06:00+00:00', notes: 'one'),
        Annotation(acqTime: '2026-02-03T09:20:00+00:00', notes: 'two'),
      ],
    ).tableData;
    expect(mixed, hasLength(plain.length + 2));
    // Each L row keeps its R row directly under it: the Word builder merges
    // the pair vertically, so a note between them would break the merge.
    for (var i = 0; i < mixed.length - 1; i++) {
      if (mixed[i][2] == 'L') expect(mixed[i + 1][2], 'R', reason: 'row $i');
    }
  });
}
