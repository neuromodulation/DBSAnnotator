/// Reading an existing BIDS dataset, showing what a merge would do, and
/// writing it.
///
/// The plan itself is pure and lives in `core/bids_merge.dart`; this is the two
/// ways in and out of it. A folder on the desktop, a zip everywhere, over one
/// merge function, because the danger is in what gets overwritten and that must
/// not have two implementations.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/bids_dataset.dart';
import '../core/bids_merge.dart';
import '../core/safe_file.dart';

/// A dataset bigger than this is not something to round-trip through a tablet's
/// memory. Real DBS datasets carry imaging and run to gigabytes.
const int kMaxMergeZipBytes = 200 * 1024 * 1024;

/// Content recorded for a file whose bytes were not read: it exists, so a path
/// collision is still detected, but it can never compare equal to anything the
/// app would write.
const String kUnreadContent = '\u0000unread';

bool _isTextPath(String path) =>
    path.endsWith('.tsv') ||
    path.endsWith('.json') ||
    path.endsWith('.md') ||
    path.endsWith('README');

/// Every file of the dataset rooted at [root], paths relative to it.
///
/// Only the text files the merge can reason about are decoded. Imaging and
/// anything else is recorded by path alone, which is all that is needed: those
/// paths are never written, and knowing they exist is what stops a collision.
Future<List<DatasetFile>> readDatasetDirectory(String root) async {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final out = <DatasetFile>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = entity.path
        .substring(root.length)
        .replaceAll(r'\', '/')
        .replaceAll(RegExp('^/+'), '');
    if (rel.isEmpty) continue;
    if (!_isTextPath(rel)) {
      out.add((path: rel, content: kUnreadContent));
      continue;
    }
    try {
      out.add((path: rel, content: await entity.readAsString()));
    } catch (_) {
      out.add((path: rel, content: kUnreadContent));
    }
  }
  return out;
}

/// The same, out of an exported `.zip`.
List<DatasetFile> readDatasetZip(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = <DatasetFile>[];
  for (final file in archive.files) {
    if (!file.isFile) continue;
    if (!_isTextPath(file.name)) {
      out.add((path: file.name, content: kUnreadContent));
      continue;
    }
    try {
      out.add((path: file.name, content: utf8.decode(file.readBytes()!)));
    } catch (_) {
      out.add((path: file.name, content: kUnreadContent));
    }
  }
  return out;
}

/// Write [plan] into the dataset at [root].
///
/// Ordered so an interruption can never leave the dataset claiming files that
/// do not exist: the index files are backed up first, then the new leaf files
/// (a pure addition, where a half-done write leaves an unreferenced file the
/// validator will see and nothing is destroyed), then the indexes themselves.
Future<void> applyMergeToDirectory(String root, MergePlan plan) async {
  String full(String rel) => '$root/$rel';

  final stamp = DateTime.now().millisecondsSinceEpoch;
  for (final path in plan.rowMerged) {
    final file = File(full(path));
    if (file.existsSync()) await file.copy('${full(path)}.bak-$stamp');
  }

  final indexes = {...plan.rowMerged};
  for (final pass in [false, true]) {
    for (final file in plan.write) {
      if (indexes.contains(file.path) != pass) continue;
      final target = File(full(file.path));
      await target.parent.create(recursive: true);
      await writeStringAtomic(target.path, file.content);
    }
  }
}

/// The merged dataset as a new zip, leaving the original untouched.
Uint8List mergedZip(List<DatasetFile> existing, MergePlan plan) {
  final byPath = {for (final f in existing) f.path: f.content};
  for (final f in plan.write) {
    byPath[f.path] = f.content;
  }
  final archive = Archive();
  for (final path in byPath.keys.toList()..sort()) {
    final content = byPath[path]!;
    // A file whose bytes were never read cannot be re-emitted, and writing a
    // placeholder in its place would corrupt it.
    if (content == kUnreadContent) continue;
    archive.addFile(ArchiveFile.bytes(path, utf8.encode(content)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Show exactly what the merge will do and wait for a yes.
///
/// This is a gate, not a courtesy: writing into a dataset the app did not
/// create is the one operation here with no undo.
Future<bool> confirmMerge(
  BuildContext context,
  MergePlan plan,
  String target,
) async {
  final theme = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add to this dataset?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(target, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              for (final (label, paths) in [
                ('Added', plan.added),
                ('Gaining rows', plan.rowMerged),
                ('Left unchanged', plan.keptAsIs),
                ('Refused: already recorded', plan.refused),
              ])
                if (paths.isNotEmpty) ...[
                  Text(
                    '$label (${paths.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final p in paths.take(12))
                    Text('  $p', style: theme.textTheme.bodySmall),
                  if (paths.length > 12)
                    Text(
                      '  and ${paths.length - 12} more',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                ],
              Text(
                'Your dataset_description.json, README and participants.json '
                'are not rewritten, and participants.tsv keeps every column '
                'and row it already has.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: plan.write.isEmpty
              ? null
              : () => Navigator.pop(context, true),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Ask for the dataset folder. Null when cancelled or unavailable.
Future<String?> pickDatasetFolder() async {
  try {
    return await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose the BIDS dataset folder',
    );
  } catch (_) {
    return null;
  }
}
