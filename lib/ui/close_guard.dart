/// Leaving a session: whether to keep its recovery copy.
///
/// The working copy is what brings a session back after a crash, so it is
/// only ever deleted when the user says so. Leaving the workflow and closing
/// the desktop window both ask; a crash, or a phone or tablet app being swiped
/// away, asks nothing and keeps it.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import 'save_target.dart';

/// Asked before the desktop window closes, set by the open session screen.
/// Returns whether the window may close.
Future<bool> Function()? activeSessionGuard;

/// Ask whether to keep the recovery copy at [workingPath], and discard it if
/// told to. Returns whether leaving may go ahead: false when the user cancels.
Future<bool> confirmLeaveSession(
  BuildContext context,
  String? workingPath,
) async {
  // Nothing recorded yet, so there is no copy to keep or discard.
  if (workingPath == null || !File(workingPath).existsSync()) return true;
  final keep = await askKeepRecoveryCopy(context);
  if (keep == null) return false;
  if (!keep) await discardWork(workingPath);
  return true;
}

/// True to keep the recovery copy, false to discard it, null to cancel.
Future<bool?> askKeepRecoveryCopy(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Keep a recovery copy of this session?'),
    content: const SizedBox(
      width: 460,
      child: Text(
        'The app keeps a copy of this session so it can offer it back if the '
        'app closes unexpectedly. Keep it to be offered the session again '
        'next time; discard it if you are done. Your saved file is not '
        'changed either way.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Discard copy'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Keep copy'),
      ),
    ],
  ),
);
