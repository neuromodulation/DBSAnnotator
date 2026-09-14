import 'package:flutter/material.dart';

/// App identity, mirroring the desktop `config.py` values.
const String appName = 'DBS Annotator';

/// Restates `version:` from pubspec.yaml, the source of truth; reading the
/// pubspec at runtime would need a native plugin. The value reaches report
/// footers and document metadata, so `version_parity_test.dart` guards it
/// against drift.
const String appVersion = '0.5.0';
const String repoUrl = 'https://github.com/neuromodulation/DBSAnnotator';
const String issuesUrl = '$repoUrl/issues';
const String contactEmail = 'lucia.poma@wysscenter.ch';
const String publisher = 'Wyss Center for Bio and Neuroengineering';
const String copyrightHolders =
    'Massachusetts General Hospital, Harvard Medical School, and the Wyss '
    'Center for Bio and Neuroengineering';

/// The app mark, bundled from `icons/logosimple/`. Declared in pubspec assets.
const String appIconAsset = 'assets/icon/app_icon.png';

/// The app mark as a widget, for AppBars and dialogs. [size] is the logical
/// height; the mark is square. A missing asset degrades to a Material glyph
/// rather than a red error box.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    appIconAsset,
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => Icon(Icons.psychology_outlined, size: size),
  );
}

/// Help/About dialog. URLs are SelectableText rather than tappable links,
/// which avoids a url_launcher dependency.
void showAppAbout(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: appName,
    applicationVersion: 'v$appVersion',
    applicationIcon: const AppLogo(size: 48),
    children: const [
      SizedBox(height: 8),
      Text(
        'Document DBS programming visits, the appointments at which '
        'stimulation configurations are tested and optimised. The complete '
        'workflow runs in four steps: file setup, initial configuration, '
        'session-scales configuration, active recording. Writes BIDS '
        'behavioural TSV with a JSON sidecar documenting every column, and '
        'exports PDF and Word reports.',
      ),
      SizedBox(height: 12),
      Text(
        'Links (select to copy):',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      SelectableText('Repository: $repoUrl'),
      SelectableText('Issues: $issuesUrl'),
      SelectableText('Contact: $contactEmail'),
      SizedBox(height: 12),
      Text('© 2026 $copyrightHolders'),
      Text('MIT License. Publisher: $publisher.'),
    ],
  );
}

/// Shared AppBar action opening [showAppAbout].
class HelpButton extends StatelessWidget {
  const HelpButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.help_outline),
    iconSize: 28,
    tooltip: 'Help / about',
    onPressed: () => showAppAbout(context),
  );
}
