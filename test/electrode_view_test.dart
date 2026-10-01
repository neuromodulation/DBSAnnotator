import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/contact_state.dart';
import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/electrode/geometry.dart';
import 'package:dbs_annotator/core/electrode/stimulation_rule.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless smoke test: pumps ElectrodeView in a fixed-size box, taps shapes
/// at coordinates derived from the SAME pure `computeLayout` the widget uses,
/// and asserts the desktop-compatible state machine via the callbacks.
void main() {
  const viewSize = Size(300, 560);

  ElectrodeModel loadModel(String name) {
    final file = File('schema/electrode_models.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'schema/*.json is a committed contract; restore it from git.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final catalog = ElectrodeCatalog.fromJson(json);
    expect(catalog.models, contains(name));
    return catalog.models[name]!;
  }

  testWidgets('taps drive the OFF/ANODIC/CATHODIC cycle and callbacks', (
    tester,
  ) async {
    final model = loadModel('Boston Scientific Vercise Directed');

    Map<ContactKey, ContactState>? lastStates;
    ContactState? lastCaseState;
    final validations = <({bool valid, String error})>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: viewSize.width,
            height: viewSize.height,
            child: ElectrodeView(
              model: model,
              onChanged: (states, caseState) {
                lastStates = states;
                lastCaseState = caseState;
              },
              onValidation: (valid, error) =>
                  validations.add((valid: valid, error: error)),
            ),
          ),
        ),
      ),
    );

    // The widget computes its layout from the same pure function, so tap
    // coordinates can be derived headlessly.
    final origin = tester.getTopLeft(find.byType(ElectrodeView));
    final layout = computeLayout(model, viewSize);
    final e0Center =
        layout.levels.last.contactRects[const ContactKey(0, 0)]!.center;

    Future<void> tapLocal(Offset local) async {
      await tester.tapAt(origin + local);
      await tester.pump();
    }

    // Contact tap: OFF -> ANODIC, onChanged fired.
    await tapLocal(e0Center);
    expect(lastStates, {const ContactKey(0, 0): ContactState.anodic});
    expect(lastCaseState, ContactState.off);
    expect(validations.last.valid, isTrue);

    // ANODIC -> CATHODIC. A lone cathode has no anode: applied anyway
    // (desktop behaviour) but reported invalid.
    await tapLocal(e0Center);
    expect(lastStates, {const ContactKey(0, 0): ContactState.cathodic});
    expect(validations.last.valid, isFalse);

    // CATHODIC -> OFF removes the key entirely.
    await tapLocal(e0Center);
    expect(lastStates, isEmpty);
    expect(validations.last.valid, isTrue);

    // Ring-cap tap on directional level E2: all OFF -> all ANODIC.
    final level2 = layout.levels.firstWhere((l) => l.levelIdx == 2);
    await tapLocal(level2.ringCapRect!.center);
    expect(lastStates, {
      const ContactKey(2, 0): ContactState.anodic,
      const ContactKey(2, 1): ContactState.anodic,
      const ContactKey(2, 2): ContactState.anodic,
    });
    expect(validations.last.valid, isTrue);

    // Ring-cap tap again: all ANODIC -> all CATHODIC.
    await tapLocal(level2.ringCapRect!.center);
    expect(lastStates!.values.every((s) => s == ContactState.cathodic), isTrue);

    // Ring-cap tap again: uniform CATHODIC (not all-OFF/all-ANODIC) -> OFF.
    await tapLocal(level2.ringCapRect!.center);
    expect(lastStates, isEmpty);

    // Case tap: OFF -> ANODIC.
    await tapLocal(layout.caseRect.center);
    expect(lastCaseState, ContactState.anodic);
    expect(validations.last.valid, isTrue);

    // Anodic case + anodic contact violates rule 2: applied, but the error
    // is surfaced through the validation callback.
    await tapLocal(e0Center);
    expect(lastStates, {const ContactKey(0, 0): ContactState.anodic});
    expect(lastCaseState, ContactState.anodic);
    expect(validations.last.valid, isFalse);
    expect(
      validations.last.error,
      'When CASE is anodic, no other contacts can be anodic',
    );
  });
}
