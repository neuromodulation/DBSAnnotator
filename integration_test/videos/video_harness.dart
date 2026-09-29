import 'dart:io';

import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/ui/save_target.dart';
import 'package:dbs_annotator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

/// Repo root, passed by `tool/record_video.ps1`, for the committed fixtures.
const videoRoot = String.fromEnvironment('VIDEO_ROOT', defaultValue: '.');

final _tap = ValueNotifier<Offset?>(null);

void initVideoBinding() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
}

/// Shows [home] in the real window, with preferences and the working copy
/// in a temp folder so a recording never touches the user's own.
Future<void> startVideo(WidgetTester tester, Widget home) async {
  final tmp = Directory.systemTemp.createTempSync('dbs_video_');
  debugPrefsDir = tmp;
  debugWorkingDir = tmp;
  debugSaveDir = tmp;
  await windowManager.ensureInitialized();
  // Its own title, so ffmpeg never records another open copy of the app.
  await windowManager.setTitle('DBS Annotator video');
  await windowManager.setSize(const Size(1280, 800));
  await windowManager.center();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dbsTheme(Brightness.light),
      builder: (context, child) => Stack(
        children: [
          child!,
          IgnorePointer(
            child: ValueListenableBuilder<Offset?>(
              valueListenable: _tap,
              builder: (_, at, _) =>
                  CustomPaint(size: Size.infinite, painter: _TapPainter(at)),
            ),
          ),
        ],
      ),
      home: home,
    ),
  );
  await pause(tester, 500);
  _mark('ready');
  await pause(tester, 1000);
}

/// Tells the recorder to stop, then holds the last frame briefly.
Future<void> endVideo(WidgetTester tester) async {
  await pause(tester, 1500);
  _mark('done');
  await pause(tester, 1000);
}

/// Marker files `tool/record_video.ps1` waits on to start and stop ffmpeg.
void _mark(String name) {
  const dir = String.fromEnvironment('VIDEO_MARKS');
  if (dir.isNotEmpty) File('$dir/$name').writeAsStringSync('');
}

Future<void> pause(WidgetTester tester, [int ms = 700]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pumpAndSettle();
}

/// Scrolls [finder] to the middle of the window, so what it changes is in view.
Future<void> center(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder.first),
    alignment: 0.5,
    duration: const Duration(milliseconds: 400),
  );
  await tester.pumpAndSettle();
}

/// Taps [at] with a visible marker; [fast] for runs of taps in one place.
Future<void> tapAt(WidgetTester tester, Offset at, {bool fast = false}) async {
  _tap.value = at;
  await pause(tester, fast ? 100 : 250);
  await tester.tapAt(at);
  await pause(tester, fast ? 100 : 250);
  _tap.value = null;
  await pause(tester, fast ? 150 : 700);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await center(tester, finder);
  await tapAt(tester, tester.getCenter(finder.first));
}

Future<void> tapText(WidgetTester tester, String text) =>
    tap(tester, find.text(text));

/// Types [text] into the [at]th field labelled [label], one key at a time.
Future<void> typeInto(
  WidgetTester tester,
  String label,
  String text, {
  int at = 0,
}) async {
  final field = find.widgetWithText(TextField, label).at(at);
  await tap(tester, field);
  for (var i = 1; i <= text.length; i++) {
    await tester.enterText(field, text.substring(0, i));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
  }
  await pause(tester, 400);
}

class _TapPainter extends CustomPainter {
  const _TapPainter(this.at);
  final Offset? at;

  @override
  void paint(Canvas canvas, Size size) {
    if (at == null) return;
    canvas.drawCircle(at!, 18, Paint()..color = const Color(0x55F59E0B));
    canvas.drawCircle(
      at!,
      18,
      Paint()
        ..color = const Color(0xFFB45309)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TapPainter old) => old.at != at;
}
