# DBS Annotator

[![CI](https://github.com/neuromodulation/DBSAnnotator/actions/workflows/ci.yml/badge.svg)](https://github.com/neuromodulation/DBSAnnotator/actions/workflows/ci.yml)
[![Docs](https://readthedocs.org/projects/dbs-annotator/badge/?version=latest)](https://dbs-annotator.readthedocs.io/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Record deep brain stimulation programming visits, and get analysis-ready data
out.

Once the electrodes are implanted, the patient comes back to see a neurologist or
psychiatrist, who tries stimulation configurations and settles on one that works.
That takes a visit or several, and the parameters go on being adapted over months
or years.

DBS Annotator documents those visits: the stimulation parameters tried on each
contact, the clinical and session scale ratings at each configuration, side
effects, and free-text notes, written to **BIDS tab-separated files** that go
straight into analysis. It also produces clinician-readable **PDF and Word
reports** for the patient record.

It runs **fully offline**. No account, no server, no telemetry. Tablet-first
(iPadOS and Android) with desktop builds for Linux, Windows and macOS.

## Why

Vendor programming devices record what the device needs, not what research
needs, and they do not export data anyone can pool across patients or sites.
The alternative in practice is paper notes, which do not survive analysis. So
sessions get documented twice, inconsistently, and the relationship between
what was delivered and what happened, which is the whole point of a titration
session, is the part that gets lost.

This tool records that relationship as it happens, in one format, with the
timestamps intact.

## Repository layout

```
lib/                 the Flutter application (Dart)
test/                463 tests
assets/              bundled schema contract, fonts, app icon
android/ ios/ linux/ macos/ windows/
schema/              the machine-readable domain contract (TSV columns,
                     BIDS naming, stimulation limits, electrode models)
docs/                documentation source (Read the Docs)
paper/               JOSS paper
```

## Getting started

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
**3.38.4 or later** (Dart 3.12+). From the repository root:

```bash
flutter pub get
flutter test        # 463 tests, no device needed
flutter analyze
flutter run         # on a connected tablet, emulator, or desktop
```

Nothing needs generating first. The schema contract is committed, so a fresh
clone builds and tests immediately.

## The four workflows

| Workflow | What it records |
|---|---|
| **Complete workflow** | Stimulation parameters, electrode contact selection, clinical and session scales, side effects, notes: the full titration session |
| **Annotations only** | Timestamped free-text notes and nothing else |
| **Single session report** | Open an existing TSV, get its report, with no authoring |
| **Longitudinal review** | Several sessions of one patient, compared across visits |

## Output

Data is written as BIDS `_beh.tsv` with a JSON sidecar documenting every column,
one row per (block, scale), so it pivots directly:

```python
df = pd.read_csv(path, sep="\t", na_values=["n/a"])
df.pivot_table(index=["append_id", "block_id"], columns="scale_name", values="scale_value")
```

`_beh` rather than `_events`: the BIDS specification reserves `_events.tsv` for
files whose first two columns are `onset` and `duration` and which accompany a
recording, and says that files without them "MUST be labeled `_beh.tsv`". A
programming session has neither. **Export → BIDS dataset** lays a set of sessions
out as a validator-ready `sub-XX/ses-YYYYMMDD/beh/` tree.

Reports come out as PDF and Word, both built from the same numbers so they
cannot disagree. The full format reference, including how files written by the
older desktop app are read, is in the
[documentation](https://dbs-annotator.readthedocs.io/).

## Fonts

`assets/fonts/IBMPlexSans-{Regular,Bold}.ttf` are committed (SIL Open Font
License, see `assets/fonts/LICENSE-IBMPlexSans.txt`). They do two jobs:

- **PDF reports.** Without them the exporter falls back to Helvetica, which is
  Latin-1 only, so a curly quote or an accented character in a clinical note
  becomes `?`. The app warns when that happens.
- **Documentation screenshots.** `flutter_tester` ships no fonts at all, so the
  capture harness registers these; on a host without them it falls back to a
  system font and the images stop being reproducible between machines.

If you ever need to replace them, get the **static** TTFs from
<https://fonts.google.com/specimen/IBM+Plex+Sans> ("Get font", then the
`static/` folder in the zip) or from <https://github.com/IBM/plex/releases>.

Do **not** hot-link a `raw.githubusercontent` path from google/fonts: IBM Plex
Sans has moved to a variable font there, so the old static path 404s, and a 404
still writes a file: GitHub's error page is ~300 KB of HTML, which sails past any
"is the file big enough?" check. Verify the magic bytes instead:

```powershell
Get-ChildItem assets/fonts/*.ttf | ForEach-Object {
  $b = [System.IO.File]::ReadAllBytes($_.FullName)[0..3]
  "{0}: {1}" -f $_.Name, (($b | ForEach-Object { $_.ToString('x2') }) -join ' ')
}
```

`00 01 00 00` is a TrueType font (`4f 54 54 4f` for OpenType/CFF). Anything else
is not, and the loader will correctly ignore it.

## Releases

Tag `app-vX.Y.Z` to trigger
[the pipeline](.github/workflows/ci.yml). Android attaches an APK to the GitHub
Release, signed with the project key once the signing secrets are set and with
the debug key until then, which is runnable but not distributable
([MOBILE_RELEASE.md](MOBILE_RELEASE.md)). iPadOS goes to TestFlight (Apple has no
sideload path); Linux, Windows and macOS bundles are built as workflow artifacts.
Per-OS app store distribution is planned.

To put a build on a machine or tablet today, with no developer account, see
[Installing a build you made yourself](https://dbs-annotator.readthedocs.io/en/latest/installation.html).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Citing

If you use DBS Annotator in published work, please cite it; see
[CITATION.cff](CITATION.cff).

## License

MIT. See [LICENSE](LICENSE).
