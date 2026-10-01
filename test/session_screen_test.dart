import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless tests for the Complete-Workflow 4-step wizard. Contracts are
/// injected from the repo-root schema files (like electrode_catalog_test),
/// so no asset bundle or platform channel is touched; Open/Export are never
/// tapped. A [SessionAuthoring] is injected so inserted rows can be
/// asserted directly.
void main() {
  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  final catalog = ElectrodeCatalog.fromJson(
    readJson('schema/electrode_models.json'),
  );
  final limits = StimLimits.fromJson(readJson('schema/limits.json'));
  final scalePresets = ScalePresets.fromJson(
    readJson('schema/scale_presets.json'),
  );

  /// Tall surface so the current step's content is mostly on-screen (the
  /// Stepper is scrollable; taps still use ensureVisible), then pump the
  /// wizard with all contracts injected.
  Future<void> pumpWizard(
    WidgetTester tester, {
    SessionAuthoring? authoring,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SessionScreen(
          catalog: catalog,
          limits: limits,
          scalePresets: scalePresets,
          authoring: authoring,
        ),
      ),
    );
    // Let the injected-contracts future resolve.
    await tester.pump();
    await tester.pump();
  }

  /// Advance the wizard by tapping the current step's Next button [steps]
  /// times (only the active step renders controls, so 'Next' is unique).
  Future<void> tapNext(WidgetTester tester, [int steps = 1]) async {
    for (var i = 0; i < steps; i++) {
      final next = find.text('Next');
      expect(next, findsOneWidget);
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('wizard: file step, then baseline insert lands in the '
      'recording-step blocks list', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);

    // All four desktop-style step headers are visible.
    expect(find.text('Complete workflow'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Initial configuration'), findsOneWidget);
    expect(find.text('Session scales configuration'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);

    // Step 0: patient/run plus New / Open actions; no stim UI yet.
    expect(find.text('Patient ID (sub-)'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Open existing TSV'), findsOneWidget);
    expect(find.text('Insert baseline'), findsNothing);

    // Step 1: L/R stim + electrode, clinical pills, Insert baseline.
    await tapNext(tester);
    // The default model (Medtronic SenSight B33005) is preselected, so both
    // canvases render immediately instead of the "select a model" placeholder.
    expect(find.byType(ElectrodeView), findsNWidgets(2));
    expect(find.text('Select an electrode model'), findsNothing);
    expect(find.text('Frequency'), findsNWidgets(2));
    expect(find.text('Amplitude'), findsNWidgets(2));
    expect(find.text('Pulse width'), findsNWidgets(2));
    expect(find.text('Insert baseline'), findsOneWidget);
    for (final name in scalePresets.buttons) {
      expect(find.widgetWithText(ChoiceChip, name), findsOneWidget);
    }

    // A clinical pill REPLACES the rows with that preset's scale names.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'OCD'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'OCD'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Y-BOCS'), findsOneWidget);
    expect(
      find.text('Score'),
      findsNWidgets(scalePresets.clinical['OCD']!.length),
    );
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'MDD'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'MDD'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Y-BOCS'), findsNothing);
    expect(
      find.text('Score'),
      findsNWidgets(scalePresets.clinical['MDD']!.length),
    );

    // Type one score and insert the baseline: ONE is_initial=1 block, one
    // row per scored clinical scale (blank scores are dropped, desktop
    // ClinicalScale.is_valid).
    await tester.enterText(find.widgetWithText(TextField, 'Score').first, '12');
    final insert = find.text('Insert baseline');
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    await tester.pump();
    expect(authoring.rows, hasLength(1));
    expect(authoring.rows.single.isInitial, '1');
    expect(authoring.rows.single.scaleName, 'MADRS');
    expect(authoring.rows.single.scaleValue, '12');
    expect(authoring.rows.single.blockId, '0');

    // Step 3 shows the inserted entry in the review table (Type "Initial",
    // scale MADRS/12).
    await tapNext(tester, 2);
    expect(find.text('Initial'), findsWidgets);
    expect(find.text('MADRS'), findsWidgets);
    expect(find.text('No entries inserted yet.'), findsNothing);
    expect(find.text('Insert recording block'), findsOneWidget);
    // Four separate controls collapsed into one Export menu; the formats are
    // now menu items, so they only exist once it is opened.
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Export report (PDF)'), findsNothing);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Export report (PDF)'), findsOneWidget);
    expect(find.text('Export report (Word)'), findsOneWidget);
    expect(find.text('Export TSV'), findsOneWidget);
    expect(find.text('Paper size: A4'), findsOneWidget);
  });

  testWidgets('stim - / + steppers move by step1 and the clear X empties '
      'the field', (tester) async {
    await pumpWizard(tester);
    await tapNext(tester); // Step 1.

    String leftFreqText() => tester
        .widget<TextField>(
          find.descendant(
            of: find.widgetWithText(TextFormField, 'Frequency').first,
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    String leftAmpText() => tester
        .widget<TextField>(
          find.descendant(
            of: find.widgetWithText(TextFormField, 'Amplitude').first,
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

    Future<void> tapButton(String tooltip) async {
      final button = find.byTooltip(tooltip).first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
    }

    // Frequency: step1 = 10.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Frequency').first,
      '100',
    );
    await tapButton('Increase Frequency');
    expect(leftFreqText(), '110');
    await tapButton('Decrease Frequency');
    expect(leftFreqText(), '100');

    // Amplitude: step1 = 1, keeping the contract decimals (1.5 -> 2.5).
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amplitude').first,
      '1.5',
    );
    await tapButton('Increase Amplitude');
    expect(leftAmpText(), '2.5');

    // Clear X empties the field; stepping from blank starts at min.
    await tapButton('Clear Frequency');
    expect(leftFreqText(), '');
    await tapButton('Increase Frequency');
    expect(leftFreqText(), presetLabel(limits.frequency.min));

    // Clamped at max: repeated + never exceeds the limit.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Frequency').first,
      presetLabel(limits.frequency.max),
    );
    await tapButton('Increase Frequency');
    expect(leftFreqText(), presetLabel(limits.frequency.max));
  });

  testWidgets('out-of-range stimulation value blocks the baseline insert', (
    tester,
  ) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);
    await tapNext(tester); // Step 1.

    // First TextFormField with the "Hz" suffix is the Left frequency.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Frequency').first,
      '${limits.frequency.max + 1}',
    );
    await tester.pump();

    final insert = find.text('Insert baseline');
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    await tester.pump();

    expect(
      find.text('Fix out-of-range stimulation values before inserting.'),
      findsOneWidget,
    );
    expect(authoring.rows, isEmpty);
  });

  testWidgets('tapping a stimulation quick-pick chip fills the field', (
    tester,
  ) async {
    await pumpWizard(tester);
    await tapNext(tester); // Step 1.

    // One 125 Hz chip per side; tap the Left one.
    final chip = find.widgetWithText(ActionChip, '125').first;
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();

    final leftFreq = tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Frequency').first,
        matching: find.byType(TextField),
      ),
    );
    expect(leftFreq.controller!.text, '125');
    // In range, so the insert is not blocked by validation.
    expect(find.text('Not a number'), findsNothing);
  });

  testWidgets('session scales defined in Step 2 become Step-3 rating rows; '
      'an omitted scale is inserted as "n/a"', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);
    await tapNext(tester, 2); // Step 2.

    // The session pills define the (name, min, max) scale set; PD REPLACES
    // the rows with its preset.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'PD'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'PD'));
    await tester.pump();
    final pdRows = scalePresets.session['PD']!;
    expect(find.widgetWithText(TextField, 'Tremor'), findsOneWidget);
    expect(find.text('Min'), findsNWidgets(pdRows.length));
    expect(find.text('Max'), findsNWidgets(pdRows.length));

    // Step 3: one rating row per Step-2 scale, each with a slider and an
    // omit ("not assessed") toggle. Navigate via the step header (robust when
    // the tall Step-2 content pushes the Next control under the Stepper's
    // transition-animation layers).
    await tester.ensureVisible(find.text('Recording'));
    await tester.tap(find.text('Recording'));
    await tester.pumpAndSettle();
    // One custom ScaleSlider (bar + chevrons + X-omit) per Step-2 scale.
    expect(find.byType(ScaleSlider), findsNWidgets(pdRows.length));
    expect(find.text('Tremor'), findsOneWidget);

    // Omit the first scale (Tremor) via its X toggle; the rest keep values.
    final omitTremor = find.byTooltip('Omit (not assessed)').first;
    await tester.ensureVisible(omitTremor);
    await tester.tap(omitTremor);
    await tester.pump();

    final insert = find.text('Insert recording block');
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    await tester.pump();

    // One is_initial=0 block, one row per scale: the omitted one carries
    // the limits.json session_scale.omitted_tsv literal, the others the
    // slider value (untouched sliders sit at their own min).
    expect(authoring.rows, hasLength(pdRows.length));
    expect(authoring.rows.first.isInitial, '0');
    expect(authoring.rows.first.scaleName, 'Tremor');
    expect(authoring.rows.first.scaleValue, limits.sessionScaleOmittedTsv);
    expect(authoring.rows.first.scaleValue, 'n/a');
    expect(authoring.rows[1].scaleName, 'Rigidity');
    expect(authoring.rows[1].scaleValue, '0');
    expect(authoring.serialize(), contains('n/a'));

    // The recording rows appear in the inserted-entries review table.
    expect(find.text('Rec'), findsWidgets);
    expect(find.text('No entries inserted yet.'), findsNothing);
  });
}
