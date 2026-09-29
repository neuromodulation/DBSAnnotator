import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'save_target.dart';

/// Global bounds of the widget at [context], for [shareOrSaveFile]'s `origin`.
///
/// Pass the export button's `currentContext` before the first await; after
/// one the widget may be gone. Null when it is not laid out.
Rect? shareOriginFrom(BuildContext? context) {
  final box = context?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

bool get _isMobile => Platform.isAndroid || Platform.isIOS;

/// MIME type for the file kinds we export. Android's `MimeTypeMap` does not
/// know `.docx`, and without an explicit type some target apps refuse it.
String? mimeTypeFor(String filename) {
  final ext = _ext(filename).toLowerCase();
  return switch (ext) {
    '.pdf' => 'application/pdf',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.tsv' => 'text/tab-separated-values',
    '.zip' => 'application/zip',
    _ => null,
  };
}

/// A non-empty popover anchor for the iPad share sheet. share_plus's iOS
/// plugin throws when a popover is required and the origin is null or empty
/// (`FPPSharePlusPlugin.m`), sending the export into the app container.
Rect safeOrigin(Rect? origin, Size screen) {
  if (origin != null && !origin.isEmpty) return origin;
  return Rect.fromCenter(
    center: Offset(screen.width / 2, screen.height / 2),
    width: 1,
    height: 1,
  );
}

/// Deliver [file] to the user: the OS share sheet on mobile, or a saved copy
/// on desktop, where `share_plus` has none. Never throws, and always reports
/// the outcome via [messenger], so an export cannot fail silently.
///
/// [messenger] must be resolved before the first await, so the snackbar is
/// safe across the async gap. [origin] anchors the iPadOS share popover and
/// [screen] supplies its fallback.
Future<void> shareOrSaveFile(
  ScaffoldMessengerState messenger,
  File file,
  String filename, {
  Rect? origin,
  Size screen = const Size(768, 1024),
}) async {
  if (_isMobile) {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mimeTypeFor(filename))],
          subject: filename,
          sharePositionOrigin: safeOrigin(origin, screen),
        ),
      );
      // Confirm on mobile too, so a dismissed sheet is distinguishable.
      if (result.status != ShareResultStatus.unavailable) {
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(
              result.status == ShareResultStatus.success
                  ? 'Shared $filename'
                  : 'Export ready: $filename',
            ),
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('Share sheet unavailable for $filename: $e');
      // Fall through to a disk save.
    }
  }
  final saved = await _saveToDisk(file, filename);
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(
        saved != null ? 'Saved to $saved' : 'Could not save $filename',
      ),
    ),
  );
}

/// An export's bytes, plus an optional warning to show once it is delivered.
typedef ExportPayload = ({List<int> bytes, String? warning});

/// Build a file and deliver it, reporting every failure.
///
/// The messenger, screen size and share anchor are captured before the first
/// await, because a menu item is unmounted by the time the iPad share sheet
/// needs its anchor. So [anchor] should key the enclosing button, not a menu
/// item that is about to disappear.
Future<void> exportFile(
  BuildContext context, {
  required String filename,
  required Future<ExportPayload> Function() build,
  GlobalKey? anchor,
  String failureLabel = 'Export failed',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final screen = MediaQuery.sizeOf(context);
  final origin = shareOriginFrom(anchor?.currentContext);
  try {
    final payload = await build();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(payload.bytes);
    await shareOrSaveFile(
      messenger,
      file,
      filename,
      origin: origin,
      screen: screen,
    );
    final warning = payload.warning;
    if (warning != null) {
      messenger.showSnackBar(
        SnackBar(duration: const Duration(seconds: 6), content: Text(warning)),
      );
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$failureLabel: $e')));
  }
}

/// Save [file] to a user-visible location: a native Save-As dialog first, then
/// the first writable well-known directory. Never throws.
Future<String?> _saveToDisk(File file, String filename) async {
  if (debugSaveDir case final dir?) {
    return (await file.copy('${dir.path}/$filename')).path;
  }
  // 1) Native Save-As dialog. It returns a Uri, and a non-`file` one has no
  //    path to report, so fall through rather than name an unopenable place.
  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save $filename',
      fileName: filename,
      bytes: await file.readAsBytes(),
      mimeType: mimeTypeFor(filename) ?? 'application/octet-stream',
    );
    final saved = pickerUriToPath(uri);
    if (saved != null) return saved;
  } catch (_) {
    // No dialog available; auto-save below.
  }

  // 2) First writable well-known directory. Application-support resolves even
  //    on a minimal Linux box where XDG Downloads/Documents are unset.
  final getters = <Future<Directory?> Function()>[
    getDownloadsDirectory,
    getApplicationDocumentsDirectory,
    getApplicationSupportDirectory,
  ];
  for (final getDir in getters) {
    try {
      final dir = await getDir();
      if (dir == null) continue;
      await Directory(dir.path).create(recursive: true);
      final dest = '${dir.path}/$filename';
      await file.copy(dest);
      return dest;
    } catch (_) {
      // Unwritable; try the next location.
    }
  }

  // 3) The temp file already exists; report its path as a last resort.
  return file.path;
}

/// The extension of [filename] including the dot ('' when there is none).
String _ext(String filename) {
  final i = filename.lastIndexOf('.');
  return i < 0 ? '' : filename.substring(i);
}
