/// The recording step's side-effects field, and how it reaches the TSV.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> readJson(String p) =>
      jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

  final catalog = ElectrodeCatalog.fromJson(
    readJson('schema/electrode_models.json'),
  );
  final limits = StimLimits.fromJson(readJson('schema/limits.json'));
  final presets = ScalePresets.fromJson(readJson('schema/scale_presets.json'));

  Future<void> pump(WidgetTester tester, SessionAuthoring authoring) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SessionScreen(
          catalog: catalog,
          limits: limits,
          scalePresets: presets,
          authoring: authoring,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> next(WidgetTester tester, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      final n = find.text('Next');
      await tester.ensureVisible(n);
      await tester.tap(n);
      await tester.pumpAndSettle();
    }
  }

  const label = 'Side effects (if any)';

  testWidgets('only the recording step offers it', (tester) async {
    await pump(tester, SessionAuthoring());
    await next(tester); // -> Initial configuration
    expect(find.text('Notes'), findsOneWidget);
    expect(
      find.text(label),
      findsNothing,
      reason: 'a baseline has no configuration to have a side effect to',
    );

    await next(tester, 2); // -> Recording
    expect(find.text(label), findsOneWidget);
  });

  testWidgets('it is written into the notes cell, prefixed and first', (
    tester,
  ) async {
    final authoring = SessionAuthoring();
    await pump(tester, authoring);
    await next(tester, 3);

    await tester.enterText(
      find.widgetWithText(TextField, label),
      'paraesthesia left hand',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes'),
      'patient tolerated well',
    );
    await tester.pump();

    final insert = find.text('Insert recording block');
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    await tester.pumpAndSettle();

    // One `notes` column, so the two fields are joined; side effects come
    // first, so a tolerability line is never lost at the end of a long
    // paragraph. No new TSV column, so the desktop app still reads the file.
    expect(authoring.rows, isNotEmpty);
    expect(
      authoring.rows.first.notes,
      'Side effects: paraesthesia left hand\npatient tolerated well',
    );
  });

  testWidgets('either half may be empty, with no stray prefix or newline', (
    tester,
  ) async {
    final authoring = SessionAuthoring();
    await pump(tester, authoring);
    await next(tester, 3);

    await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'nothing');
    await tester.pump();
    final insert = find.text('Insert recording block');
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    await tester.pumpAndSettle();
    expect(authoring.rows.first.notes, 'nothing');

    // And it clears after an insert, so a side effect cannot be attributed to
    // the next configuration too.
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, label))
          .controller!
          .text,
      isEmpty,
    );
  });
}
