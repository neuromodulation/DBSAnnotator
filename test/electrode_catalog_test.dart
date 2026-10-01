import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the catalog against the contract: it MUST parse
/// schema/electrode_models.json, the committed source of truth for lead
/// geometry. Run `flutter test` from the repo root.
void main() {
  ElectrodeCatalog loadCatalog() {
    final file = File('schema/electrode_models.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'schema/*.json is a committed contract; restore it from git.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return ElectrodeCatalog.fromJson(json);
  }

  test('Boston Scientific Vercise Directed parses with correct geometry', () {
    final catalog = loadCatalog();
    expect(catalog.models, contains('Boston Scientific Vercise Directed'));
    final model = catalog.models['Boston Scientific Vercise Directed']!;

    expect(model.numContacts, 4);
    expect(model.contactHeight, 1.5);
    expect(model.contactSpacing, 0.5);
    expect(model.leadDiameter, 1.3);
    expect(model.isDirectional, isTrue);
    expect(model.tipContact, isTrue);
    expect(model.segmentsPerLevel, 3);
    expect(model.directionalLevels, [1, 2]);
    expect(model.levelDirectional, [false, true, true, false]);

    expect(model.isLevelDirectional(0), isFalse);
    expect(model.isLevelDirectional(1), isTrue);
    expect(model.isLevelDirectional(2), isTrue);
    expect(model.isLevelDirectional(3), isFalse);
  });

  test('non-directional model has no directional levels', () {
    final catalog = loadCatalog();
    expect(catalog.models, contains('Medtronic 3389'));
    final model = catalog.models['Medtronic 3389']!;

    expect(model.isDirectional, isFalse);
    expect(model.tipContact, isFalse);
    expect(model.segmentsPerLevel, 1);
    expect(model.directionalLevels, isNull);
    expect(model.levelDirectional, [false, false, false, false]);
  });

  test('manufacturers grouping matches the desktop app', () {
    final catalog = loadCatalog();
    expect(catalog.manufacturers.keys.toSet(), {
      'Medtronic',
      'Boston Scientific',
      'Abbott',
      'PINS Medical',
      'ALEVA',
    });
    expect(
      catalog.manufacturers['Boston Scientific'],
      contains('Boston Scientific Vercise Directed'),
    );

    // Every model listed under a manufacturer resolves in the catalog.
    for (final names in catalog.manufacturers.values) {
      for (final name in names) {
        expect(catalog.models, contains(name));
      }
    }
  });
}
