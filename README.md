# Wyss DBS Annotator

[![CI](https://github.com/neuromodulation/DBSAnnotator/actions/workflows/ci.yml/badge.svg)](https://github.com/neuromodulation/DBSAnnotator/actions/workflows/ci.yml)
[![Docs](https://readthedocs.org/projects/dbs-annotator/badge/?version=latest)](https://dbs-annotator.readthedocs.io/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Record deep brain stimulation programming visits, and get analysis-ready data
out.

Once the electrodes are implanted, the patient comes back to see a neurologist or
psychiatrist, who tries stimulation configurations and settles on one that works.
That takes a visit or several, and the parameters go on being adapted over months
or years.

Wyss DBS Annotator documents those visits: the stimulation parameters tried on each
contact, the clinical and session scale ratings at each configuration, side
effects, and free-text notes, written to **BIDS tab-separated files** that go
straight into analysis. It also produces clinician-readable **PDF and Word
reports** for the patient record.

It runs **fully offline**. No account, no server, no telemetry. It is available
for iPadOS, Android, Windows, macOS and Linux, published in each platform's app
store by the Wyss Center for Bio and Neuroengineering.

## Why

Vendor programming devices record what the device needs, not what research
needs, and they do not export data anyone can pool across patients or sites.
The alternative in practice is paper notes, which do not survive analysis. So
sessions get documented twice, inconsistently, and the relationship between
what was delivered and what happened, which is the whole point of a programming
session, is the part that gets lost.

This tool records that relationship as it happens, in one format, with the
timestamps intact.

## Repository layout

```
lib/                 the Flutter application (Dart)
test/                automated tests
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
flutter test        # no device needed
flutter analyze
flutter run         # on this computer, an emulator, or a connected device
```

Nothing needs generating first. The schema contract is committed, so a fresh
clone builds and tests immediately.

## What it does

| Home screen entry | What it is for |
|---|---|
| **Complete workflow** | Record a programming visit: stimulation parameters, electrode contacts, clinical and session scales, side effects, notes |
| **Annotations only** | Timestamped free-text notes and nothing else |
| **Reports and datasets** | Upload TSVs and get a session report, a longitudinal report across visits, a combined table or a BIDS dataset |

## Output

Data is written as BIDS `_beh.tsv` with a JSON sidecar documenting every column,
one row per (block, scale), so it pivots directly:

```python
df = pd.read_csv(path, sep="\t", na_values=["n/a"])
df.pivot_table(index=["append_id", "block_id"], columns="scale_name", values="scale_value")
```

**Export → BIDS dataset** lays a set of sessions out as a validator-ready
`sub-XX/ses-YYYYMMDD/beh/` tree.

Reports come out as PDF and Word, both built from the same numbers so they
cannot disagree. The full format reference is in the
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

To replace them, use the **static** TTFs from
<https://fonts.google.com/specimen/IBM+Plex+Sans> or
<https://github.com/IBM/plex/releases>.

## Installing

Install from your platform's app store; search for *Wyss DBS Annotator*,
published by the Wyss Center for Bio and Neuroengineering. To build it yourself,
see [Building from source](https://dbs-annotator.readthedocs.io/en/latest/installation.html#building-from-source).
Maintainers publishing a release: see [MOBILE_RELEASE.md](MOBILE_RELEASE.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Citing

If you use Wyss DBS Annotator in published work, please cite it; see
[CITATION.cff](CITATION.cff).

## License

MIT. See [LICENSE](LICENSE).
