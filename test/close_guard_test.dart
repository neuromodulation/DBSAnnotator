/// Leaving a session asks about its recovery copy, and never deletes it
/// unasked.
library;

import 'dart:io';

import 'package:dbs_annotator/ui/close_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dbs_guard'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Future<bool>> leave(WidgetTester tester, String? path) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = confirmLeaveSession(context, path),
            child: const Text('leave'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('nothing recorded: leaving asks nothing', (tester) async {
    final result = await leave(tester, '${dir.path}/absent.tsv');
    expect(find.byType(AlertDialog), findsNothing);
    expect(await result, isTrue);
  });

  testWidgets('keep leaves the copy in place', (tester) async {
    final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
    final result = await leave(tester, copy.path);
    expect(find.text('Keep a recovery copy of this session?'), findsOneWidget);
    await tester.tap(find.text('Keep copy'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(copy.existsSync(), isTrue);
  });

  testWidgets('cancel stays in the session and keeps the copy', (tester) async {
    final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
    final result = await leave(tester, copy.path);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(copy.existsSync(), isTrue);
  });

  testWidgets('discard is an explicit answer, distinct from cancel', (
    tester,
  ) async {
    // The deletion itself is discardWork, covered in durable_autosave_test.
    late Future<bool?> answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => answer = askKeepRecoveryCopy(context),
            child: const Text('leave'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard copy'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });
}
