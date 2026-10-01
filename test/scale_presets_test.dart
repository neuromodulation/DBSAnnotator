import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the presets against the contract: they MUST parse
/// schema/scale_presets.json, the committed source of truth for the
/// bundled scale sets. Run `flutter test` from the repo root.
void main() {
  ScalePresets loadPresets() {
    final file = File('schema/scale_presets.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'schema/*.json is a committed contract; restore it from git.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return ScalePresets.fromJson(json);
  }

  test('button bar carries the six desktop disease presets, in order', () {
    final p = loadPresets();
    expect(p.buttons, ['OCD', 'MDD', 'PD', 'ET', 'Dystonia', 'TS']);

    // Every button resolves in both tables (no dangling pill).
    for (final name in p.buttons) {
      expect(p.clinical, contains(name));
      expect(p.session, contains(name));
    }
  });

  test('clinicalRows returns the desktop Step-1 scale names', () {
    final p = loadPresets();
    final ocd = clinicalRows(p, 'OCD');
    expect(ocd, contains('Y-BOCS'));
    expect(ocd, ['Y-BOCS', 'Y-BOCS-o', 'Y-BOCS-c', 'MADRS', 'OCI-R']);
    expect(clinicalRows(p, 'MDD'), ['MADRS', 'HAM-D', 'BDI-II']);
  });

  test('sessionRows returns the desktop (name, min, max, mode) rows', () {
    final p = loadPresets();
    final pd = sessionRows(p, 'PD');
    expect(pd, contains((name: 'Tremor', min: '0', max: '10', mode: 'min')));
    expect(pd.first, (name: 'Tremor', min: '0', max: '10', mode: 'min'));
    expect(pd.map((r) => r.name), contains('Bradykinesia'));
    for (final row in pd) {
      expect(row.min, '0');
      expect(row.max, '10');
      expect(scaleOptimizationModes, contains(row.mode));
    }
  });

  test('a preset row without a mode cell falls back to the default', () {
    // Contracts generated before optimization_mode existed carry 3 cells.
    final p = ScalePresets.fromJson({
      'buttons': ['X'],
      'clinical': {'X': <String>[]},
      'session': {
        'X': [
          ['Legacy', '0', '7'],
        ],
      },
    });
    expect(sessionRows(p, 'X').single, (
      name: 'Legacy',
      min: '0',
      max: '7',
      mode: defaultScaleOptimizationMode,
    ));
  });

  test('an unrecognised mode cell falls back to the default', () {
    final p = ScalePresets.fromJson({
      'buttons': ['X'],
      'clinical': {'X': <String>[]},
      'session': {
        'X': [
          ['Odd', '0', '7', 'sideways'],
        ],
      },
    });
    expect(sessionRows(p, 'X').single.mode, defaultScaleOptimizationMode);
  });

  test('unknown presets return empty lists (never throw)', () {
    final p = loadPresets();
    expect(clinicalRows(p, 'nope'), isEmpty);
    expect(sessionRows(p, 'nope'), isEmpty);
  });
}
