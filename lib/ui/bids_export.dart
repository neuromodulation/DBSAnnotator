/// "Export BIDS dataset": the whole tree, as one zip.
///
/// A new dataset is always a zip: it is the one shape that works identically on
/// all five platforms, and `exportFile` already hands a single file to a
/// desktop Save-As dialog or an iPad share sheet. Writing a directory needs its
/// own permissions and has mobile failure modes, which is why only the merge
/// does it, and only on the desktop. See `bids_merge_ui.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/bids_sidecar.dart';
import 'share_util.dart';

/// Zip the dataset built from [entries] and deliver it.
///
/// [anchor] is the export button, for the iPad share popover.
Future<void> exportBidsDataset(
  BuildContext context, {
  required List<DatasetEntry> entries,
  List<DatasetFile> extraFiles = const <DatasetFile>[],
  GlobalKey? anchor,
}) async {
  if (entries.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Nothing to export yet.')));
    return;
  }
  // Naming only the first of several subjects would be worse than generic.
  final subjects = {for (final e in entries) BidsName.label(e.name.subject)};
  final stem = subjects.length == 1
      ? 'sub-${subjects.first}_bids'
      : 'bids-dataset';

  await exportFile(
    context,
    filename: '$stem.zip',
    anchor: anchor,
    failureLabel: 'BIDS export failed',
    build: () async {
      final files = buildBidsDataset(
        entries,
        appName: appName,
        appVersion: appVersion,
        repoUrl: repoUrl,
      );
      final archive = Archive();
      // [extraFiles] carries derivatives, kept out of buildBidsDataset so the
      // raw tree's layout never depends on what a caller is deriving.
      for (final file in [...files, ...extraFiles]) {
        archive.addFile(
          ArchiveFile.bytes(file.path, utf8.encode(file.content)),
        );
      }
      return (
        bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
        warning: null,
      );
    },
  );
}

/// A [DatasetEntry] for one recorded file.
///
/// [kind] is `session_tsv` or `annotation_tsv`. The sidecar comes from the
/// same contract that documents the columns, so the two cannot disagree.
DatasetEntry datasetEntry({
  required BidsName name,
  required String tsv,
  required Map<String, dynamic> contract,
  required String kind,
  required String acqTime,
}) => (
  name: name,
  tsv: tsv,
  sidecar: _encode(buildSidecar(contract, kind, appVersion: appVersion)),
  acqTime: acqTime.isEmpty ? 'n/a' : acqTime,
);

String _encode(Map<String, dynamic> sidecar) =>
    '${const JsonEncoder.withIndent('  ').convert(sidecar)}\n';
