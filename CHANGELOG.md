# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## Qt app, after 0.4.0 (never released)

Work on the PySide6/Qt desktop app after its last release. It never shipped: the app
was rewritten in Flutter, whose first release is 0.6.0 above. The Qt code is kept on
the `qt-legacy` branch.

### Added

- Step 1: preset combo boxes for frequency, amplitude, and pulse width on left and
  right stimulation rows; gear button edits preset lists (stored in
  ``setting_presets.json``).
- Documentation screenshots for **Edit Setting Presets** and **Edit Program Names**
  dialogs on Step 1.
- Read the Docs: **Help**, **Update available**, and **Release notes** dialog
  screenshots in ``quickstart.rst`` (Interface Overview).
- Read the Docs: single-session report walkthrough on ``output_format.rst``: per-section
  Word export screenshots (title, clinical scores, session scales chart/table,
  electrode diagrams, programming summary), downloadable example
  ``task-programming`` TSV under ``docs/_static/session_report_example/``, and a
  generated data table (``scripts/generate_session_report_example_docs.py``).
- Read the Docs: longitudinal report walkthrough on ``output_format.rst`` and
  ``longitudinal_report.rst``: per-section export screenshots (title, sessions
  overview chart/table, combined session-scale figure, programming summary); session
  data table and per-session electrode pages cross-reference the single-session
  examples where layouts match.
- Docs screenshot pipeline: capture Help, update-available, and release-notes
  dialogs (``WizardWindow._build_*`` helpers for non-blocking capture).

### Changed

- Read the Docs: standard sphinx-rtd-theme palette (dark grey sidebar frame,
  light content panel, default blue links/headings); explicit table/body text
  contrast on the light panel; browser tab favicon uses the app icon on an opaque
  white background (``scripts/generate_docs_favicon.py``); the landing-page logo
  keeps a transparent background; screenshots and figures
  capped at 65% width (centered) via ``docs/_static/custom.css``.
- Docs screenshot pipeline: wizard captures use 65% of the app's normal step window
  size (``WIZARD_SCREENSHOT_SIZE_RATIO`` in ``tests/docs/screenshot_helpers.py``)
  for denser, balanced full-window PNGs on RTD.
- ``output_format.rst``: session report sections illustrated step-by-step instead of
  a single composite screenshot.
- ``workflow_complete.rst`` and ``longitudinal_report.rst``: remove overview video
  links (media files were not shipped in the repository).
- Read the Docs: note on ``output_format.rst`` and ``longitudinal_report.rst`` that
  session and longitudinal report screenshots and example files are synthetic
  documentation only (not real clinical data).
- Read the Docs: new ``overview.rst`` (Getting Started): motivation and
  design; ``quickstart`` moved to User Guide; workflow-choice table shown
  without horizontal scroll.
- Read the Docs: ``faq`` contact section simplified; ``quickstart`` Help button
  label aligned with the UI; minor punctuation in ``output_format.rst``.

### Fixed

- Wizard window: top bar and native title bar no longer clip off-screen when the
  window is moved or resized on a smaller monitor; geometry clamping releases
  layout minimums so content scrolls inside the step area instead of forcing
  window height.
- Step 1: clinical scale scores are preserved when switching between clinical
  preset buttons and returning to a preset you already filled in.
- Read the Docs: replace removed Sphinx ``download`` directive (Sphinx 9) with a
  normal hyperlink for the example programming-session TSV download.
- In-app **Update now** on Windows: download ``install.ps1`` into a stable folder
  (``%TEMP%\dbs_annotator_update\``) instead of a short-lived temp file deleted
  immediately after launch, so PowerShell can run the script (fixes flash-and-close
  with no install when upgrading, e.g. from ``0.4.0b2`` to ``0.4.0``); pause the
  console when the installer fails so the error stays visible.
- Dependency audit: pin ``uv>=0.11.15`` (GHSA-4gg8-gxpx-9rph); upgrade ``pip`` to
  26.1.2 (PYSEC-2026-196, Briefcase transitive dep).
- Update checker: cache the certifi SSL context; unit tests stub SSL setup to
  avoid Windows CI timeouts in ``test_updater.py``.

## [0.4.0] - 2026-06-01

### Changed

- Step 1 clinical preset buttons scroll horizontally when they do not fit on one row.

### Fixed

- Wizard window: title-bar maximize and resize on steps 1+ (step 0 stays compact).
- Step 1 initial settings: vertical scrollbar in its own column; no overlap with electrode canvases.

## [0.4.0b2] - 2026-05-21

### Added

- In-app **Update now** on the update-available dialog: downloads and runs the
  platform install scripts (``install.ps1`` on Windows, ``install.sh`` on macOS /
  Linux) for the selected GitHub release tag, then prompts you to restart the
  app from the Start menu or applications launcher.
- **View release notes** on the same dialog opens full release notes (and a
  GitHub link) in a separate window.
- ``dbs_annotator.utils.auto_update`` with optional ``dry_run=True`` (PowerShell
  ``-WhatIf`` / ``install.sh --dry-run``) for maintainers to preview an install.
- Read the Docs: dark outer page background (matching the sidebar); browser tab
  favicon uses the application icon.
- Read the Docs screenshot pipeline: home screen (light and dark theme), clinical
  and session scales settings dialogs, and regenerated workflow captures at
  native resolution (HiDPI-aware screen grab, improved PNG settings).
- ``docs/_static/custom.css``: full-width RTD content; ``screenshot-full`` (wizard
  steps) and ``screenshot-native`` (home, dialogs) capped at each PNG's intrinsic
  width so dialogs are not upscaled on wide screens.
- ``COPYRIGHT_HOLDERS`` and ``APP_LICENSE_NAME`` in ``config.py`` (shared with
  documentation).
- ``APP_MAINTAINER`` in ``config.py``; **Help** dialog lists **Maintainer: Richard
  Köhler** under lead developer.

### Changed

- Clinical and session preset pill buttons grow to fit their full label (theme
  ``max-width`` cap removed).
- Step 1 and Step 2 scale name/value fields widen as needed to show the full text.
- **Help** dialog rewritten around the standard **Complete Workflow** programming
  pipeline, timestamped ``task-programming`` TSV output, and Word/PDF reports;
  notes that each stimulation configuration is saved and summarised in reports;
  copyright lists MGH, Wyss Center, and Charité; MIT license noted.
- Update-available dialog: removed the extra “don't notify automatically”
  checkbox (that preference stays under **Help** only); release notes are no
  longer inlined; use **View release notes**; **Open download page** removed in
  favour of **Update now**.
- Pre-release update notice: “If you encounter issues, please report them to …”.
- Annotations-only file step header title: **Clinical Annotations Setup** (was
  "Output File").
- Home screen buttons: **Complete Workflow** and **Annotations-only Workflow**.
- Annotations-only TSV column ``annotation`` renamed to ``notes`` (aligned with
  the Complete Workflow); legacy files with an ``annotation`` header remain
  readable and appendable.
- Read the Docs: ``workflow_session.rst`` renamed to ``workflow_complete.rst``;
  ``quickstart.rst`` documents launching the installed app (Start Menu / MSI /
  install script), all three workflows in home-screen order, and links to the
  full guides; ``index.rst`` Quick Overview matches the same order.
- ``workflow_complete.rst``: Step 0 file setup (**Open** / **New**, Session ID /
  Run ID); UI actions documented as **Insert** and **Close session**; only one
  overview video at the top of the page.
- ``workflow_annotations.rst``: dedicated ``task-notes`` schema (``date``, ``time``,
  ``timezone``, ``notes``); no merge of multiple TSV files; **Insert** /
  **Close Session**; overview video removed.
- ``longitudinal_report.rst``: single overview video at the top; **Create
  Longitudinal Report** button naming.
- ``output_format.rst``: ``task-programming`` vs ``task-notes`` / annotations
  workflow called out in filename convention; generated schema uses ``notes`` for
  annotations-only files.
- ``faq.rst``: TSV save path references Step 0 file setup.
- README **What It Does** aligned with RTD (four Complete Workflow steps, three
  workflows, link to ``workflow_complete.rst``); installation and Contributing
  sections unchanged.
- Documentation copyright: Massachusetts General Hospital, Wyss Center for Bio
  and Neuroengineering, and Charité Universitätsmedizin Berlin.
- Screenshot capture uses the app's responsive window geometry (step 0 compact,
  steps 1+ full workflow) instead of a fixed 1600×1000 frame.
- ``workflow_complete.rst``: drop standalone ``electrode_diagram.png`` (electrode
  UI is already visible in the Step 1 screenshot).

### Fixed

- Step 1 clinical preset buttons disappearing after adding a preset in settings
  (horizontal scroll strip sizing).
- Step 3 session settings: external vertical scrollbar column (same layout as Step 1;
  no overlap with electrode canvases).
- Dependency audit: pin ``idna>=3.15`` (GHSA-65pc-fj4g-8rjx); allow ``idna`` in
  ``exclude-newer-package`` so the fix is not blocked by the one-week cooldown.
- Dependency audit: pin ``uv>=0.11.15`` (GHSA-4gg8-gxpx-9rph).
- Update checker: HTTPS uses the ``certifi`` CA bundle (fixes failed or empty
  GitHub API responses in Briefcase MSI/ZIP on Windows); compares against
  ``APP_VERSION``; empty or invalid release data surfaces as errors instead of
  a misleading “no updates” dialog.
- Electrode diagram export: E0 to En labels no longer clipped on the left in PNG
  output (wider label box and export left padding in ``ElectrodeCanvas``).
- Docs screenshot pipeline: Windows ``QPixmap.save``/PNG compression; trim
  ``grabWindow`` shadow bar on wizard captures; remove duplicate
  ``electrode-canvas.png`` artifact.
- Read the Docs build: ``installation.rst`` SmartScreen cross-reference and
  label placement for Sphinx ``-W`` builds.

## [0.4.0b1] - 2026-05-08

### Changed

- Fixed Linux release raw-archive packaging in CI for Briefcase ``linux system`` builds by
  detecting package roots via ``usr/bin`` + ``usr/lib/dbs_annotator/app`` and archiving
  the ``usr/`` tree, ensuring the launcher is included in the uploaded raw tarball. ([#97](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/97))
- Windows install script is only `scripts/install.ps1`; removed `Install-DBSAnnotator.ps1` and updated references. ([#76](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/76))
- Persist deactivated Step 3 session scales as ``NaN`` in the session TSV and omit them from Word and PDF reports. ([#94](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/94))
- Refreshed ``uv.lock`` with upgraded dependencies (including security-related updates for
  ``pip`` and ``gitpython``). ([#95](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/95))

### Fixed

- Fix `install.ps1` when run with `iex`: move install into a nested function so `$PSCmdlet` binds; document `iex` vs script parameters (`& ([scriptblock]::Create((iwr …).Content))` or local `install.ps1`). ([#77](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/77))
- Simplify `install.ps1` and update README. ([#78](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/78))
- Fix `scripts/install.sh` for POSIX `sh` and Linux launcher paths (`bin/`, `dbs_annotator`). ([#79](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/79))
- Fix `scripts/install.sh` for POSIX `sh`, LF line endings, Linux launcher discovery (`bin/`, `dbs_annotator`), and clearer errors when a release raw `.tar.gz` lacks the Briefcase stub. Linux release workflow now selects the full `app/` tree (largest tree with `bin/`) for the raw archive. ([#80](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/80))

## [0.4.0a2] - 2026-04-22

### Added

- Add a Windows PowerShell installer (``scripts/install.ps1``) and README one-liner to install the portable release ``.zip`` from GitHub when the MSI is unsigned. ([#70](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/70))
- Add ``scripts/install.sh`` (curl/wget) to install from GitHub Releases on Linux x86_64 and macOS (raw ``.tar.gz`` when present, else ``.deb`` / ``.dmg``), with README and installation docs. ([#71](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/71))

## [0.4.0a1] - 2026-04-22

### Added

- Initial changelog scaffold following Keep a Changelog 1.1.0.

### Changed

- Deduplicate TSV schema docs by generating tables from code constants, add CI/pre-commit drift checks, and extend documentation automation with docs-touch/changelog gates, Release Drafter, and Read the Docs tag triggers. ([#51](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/51))
- Improve documentation automation and TSV schema generation. ([#52](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/52))
- Document PR-based releases (`scripts/release_prepare.py`, **CD - Prepare release PR** workflow), maintainer `docs/releasing.rst`, and Sphinx generated-dir guidance (`_autosummary`, `_generated`, `_static`, `_templates`). ([#55](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/55))
- Ship ``0.4.0a1`` alpha, space-free data/install paths (``WyssCenter`` / ``DBSAnnotator``), optional GitHub release update checks, upgrade-safe user config locations, and ``release_prepare.py --bump`` for prerelease and semver bumps. ([#62](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/62))
- Update checker compares all published GitHub releases for the highest applicable newer semver (including pre-releases), handles repos with no releases quietly, surfaces pre-release guidance with support links, and lets users turn off automatic update checks from Help or the notification. ([#63](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/63))
- Consolidate branding under `icons/logosimple/` for Briefcase and Qt, add `scripts/build_app_icons.py` to generate platform icon sizes from a single source PNG, and document Linux `linux system` icon requirements. ([#66](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/66))
