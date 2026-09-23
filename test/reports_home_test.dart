/// The unified reports screen, and the home screen that reaches it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/ui/home_screen.dart';
import 'package:dbs_annotator/ui/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ElectrodeCatalog> _catalog() async => ElectrodeCatalog.fromJson(
  jsonDecode(File('assets/schema/electrode_models.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('home screen', () {
    testWidgets('groups the three entries under Record and Read', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

      expect(find.text('RECORD'), findsOneWidget);
      expect(find.text('READ'), findsOneWidget);
      for (final title in [
        'Complete workflow',
        'Annotations only',
        'Reports and datasets',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      // The two report cards became one: which you needed depended on how
      // many files you had, which you could not say before choosing.
      expect(find.text('Single session report'), findsNothing);
      expect(find.text('Longitudinal review'), findsNothing);
    });

    testWidgets('recording comes before reporting on screen', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      // A flat list put "review last year's visits" next to "start seeing a
      // patient now"; the order now follows the two questions.
      expect(y('RECORD'), lessThan(y('Complete workflow')));
      expect(y('Annotations only'), lessThan(y('READ')));
      expect(y('READ'), lessThan(y('Reports and datasets')));
    });

    testWidgets('both recording entries share the annotate icon', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      // They differ by how much they capture, not by what kind of act they are.
      expect(find.byIcon(Icons.edit_note), findsNWidgets(2));
    });
  });

  group('reports screen', () {
    testWidgets('opens on a prompt, with every action disabled', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: ReportsScreen(catalog: await _catalog())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reports and datasets'), findsOneWidget);
      expect(find.text('Upload TSVs'), findsOneWidget);
      expect(find.text('No files uploaded.'), findsOneWidget);
    });

    test('the screen composes rather than reimplements', () {
      // This screen legitimately owns file-kind detection, the enablement
      // matrix, the targets and section choice, and four output families. What
      // it must not do is reimplement anything shared, and the line bound is
      // what makes a slide back into that visible.
      final src = File('lib/ui/reports_screen.dart').readAsLinesSync();
      final code = src.where((l) {
        final t = l.trim();
        return t.isNotEmpty && !t.startsWith('//') && !t.startsWith('///');
      }).length;
      // Deliberately loose: `dart format` decides where lines wrap, so the
      // count moves by a few whenever the formatter's style does. A limit
      // that fails on a reformat only teaches people to raise the limit. This
      // one screen replaced two totalling ~920 code lines, so the bound is
      // set above what it is, not below what it replaced.
      expect(
        code,
        lessThan(760),
        reason: 'code lines excluding comments and blanks: $code',
      );

      // The composition itself: these must come from elsewhere.
      final text = src.join(String.fromCharCode(10));
      for (final shared in [
        'SessionEntriesTable(',
        'EntryChartsView(',
        'showScaleTargetsDialog(',
        'showReportSectionsDialog(',
        'renderReportGraphics(',
        'exportFile(',
        'buildSessionReportData(',
        'buildAnnotationsReportData(',
        'buildLongitudinalReportData(',
        'buildAggregate(',
        'exportBidsDataset(',
        'unavailableReason(',
      ]) {
        expect(text, contains(shared), reason: shared);
      }
    });
  });
}
