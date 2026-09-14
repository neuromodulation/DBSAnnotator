Installation
============

DBS Annotator runs on tablets and on the desktop from a single codebase. How you
install it depends on the platform, and the honest state of each is below.

.. note::

   Store distribution is in preparation, starting with the Microsoft Store
   submission for Windows. Until a listing is live, the builds below are
   **research-grade**: signed with the project's own certificate or not at all,
   and installed deliberately rather than from a store. Every route produces the
   same application; only the trust and update mechanics differ.

Android tablet
--------------

Each tagged release attaches an ``.apk`` to its
`GitHub release <https://github.com/neuromodulation/DBSAnnotator/releases>`_.

1. On the tablet, open the release page and download ``app-release.apk``.
2. Android will ask you to allow installation from that source. This is expected
   for an app that does not come from Google Play.
3. Open the downloaded file to install.

iPadOS
------

Apple provides no sideloading path, so iPad builds are distributed through
**TestFlight**. The invitation link is published in the release notes when a
build is available.

This requires an Apple Developer account on the publishing side, which is why
iPad availability may lag behind Android.

Windows
-------

Two routes, depending on whether you want an installed application or just
something you can run.

**MSIX installer.** A real installation: Start-menu entry, proper uninstall,
per-user application data, and no SmartScreen prompt once it arrives from the
Store. The Microsoft Store submission is in preparation; when the listing is
live, installing from the Store is the whole procedure and there is nothing to
trust by hand, because Microsoft signs Store packages themselves.

Until then, a tagged release attaches an ``.msix`` signed with the project's own
certificate. Windows will not trust it until you say so, and the trust step is
per-machine and needs administrator rights:

1. Right-click the ``.msix`` → *Properties* → **Digital Signatures** → select the
   signature → *Details* → *View Certificate* → **Install Certificate**.
2. Choose **Local Machine**, then *Place all certificates in the following store*
   → **Trusted People**.
3. Double-click the ``.msix`` to install.

.. warning::

   Check whose certificate you are trusting before step 2; the certificate
   details are on screen at that point. Trusting a certificate means Windows will
   silently accept **any** package signed with it, not just this one. Only trust a
   certificate you can attribute to a person or organisation you know.

   In particular, a package built with the packaging tool's *default* certificate
   is signed by a shared test identity whose private key is public. That is fine
   for checking that a package installs on your own machine, and unsuitable for a
   shared or clinical machine.

**Loose folder**, if you would rather not install anything. Every commit builds
one and attaches it to the workflow run: open the latest successful run of the
*App CI/CD* workflow in the
`Actions tab <https://github.com/neuromodulation/DBSAnnotator/actions>`_ and
download ``windows-bundle``. Unzip it and run ``dbs_annotator.exe`` from inside
the folder; it needs the DLLs and ``data\`` directory beside it. Being unsigned,
SmartScreen will warn on first launch: *More info* → *Run anyway*.

Linux and macOS
---------------

No installer yet. Desktop bundles are built for every commit and attached to the
workflow run rather than to a release, because these targets exist mainly so that
the report and export code is exercised on every platform. Download
``linux-bundle`` from the *Actions* tab as above. macOS is built in CI but not
published as an artifact; build it from source (below).

Both are unsigned, so macOS Gatekeeper refuses an unsigned app on double-click;
right-click → *Open* allows it once.

Building from source
--------------------

The most reliable route on any platform, and the one to use if you intend to
modify anything. It needs only the
`Flutter SDK <https://docs.flutter.dev/get-started/install>`_ **3.38.4 or later**
(Dart 3.12 or later, which is the floor ``pubspec.lock`` resolves against, so an
older SDK fails at ``pub get``):

.. code-block:: bash

   git clone https://github.com/neuromodulation/DBSAnnotator.git
   cd DBSAnnotator
   flutter pub get
   flutter run          # on a connected tablet, emulator, or the desktop

Nothing needs generating first: the schema contract is committed, so a fresh
clone builds immediately. To confirm the checkout is sound:

.. code-block:: bash

   flutter analyze      # must report no issues
   flutter test         # runs the full suite, no device needed

On Linux the desktop build additionally needs GTK development headers:

.. code-block:: bash

   sudo apt-get install ninja-build libgtk-3-dev

Installing a build you made yourself
------------------------------------

No developer account and no store listing is needed to put a real, installable
build on a Windows machine or an Android tablet today. This is the route to use
for evaluation before store distribution exists.

**Windows.** Either run it out of the build folder, or build the installer:

.. code-block:: bash

   flutter build windows --release
   # run in place: build\windows\x64\runner\Release\dbs_annotator.exe
   # (copy the WHOLE Release folder if you move it: the .exe needs the DLLs
   #  and data\ beside it)

   dart run msix:create
   # -> build\windows\msix\dbs_annotator.msix, plus a self-signed certificate

Build first, package second: ``msix_config`` sets ``build_windows: false`` so the
packaging step never launches a second, differently-configured Flutter build. To
install the MSIX, trust its certificate as described under **Windows** above.
Running the loose executable needs no certificate, but SmartScreen shows "Windows
protected your PC" on first launch: *More info* → *Run anyway*.

**Android.** Build an APK, copy it to the tablet (USB, or any file-sharing
route) and open it there:

.. code-block:: bash

   flutter build apk --release
   # -> build/app/outputs/flutter-apk/app-release.apk

Unless a signing key has been configured, this APK is signed with the debug key.
It installs and runs normally, but it cannot later be replaced in place by a
properly signed build: that needs an uninstall first, which takes the app's
stored preferences with it. Fine for testing; not for handing to a site.

**macOS.** ``flutter build macos --release`` produces a ``.app`` under
``build/macos/Build/Products/Release/``. Gatekeeper blocks an unsigned app on
double-click; right-click → *Open* allows it once.

**iPadOS.** The only target that genuinely needs a Mac, because Xcode has to do
the build. A free Apple ID is enough to run it on your own iPad through Xcode's
automatic provisioning, but the resulting build expires after seven days and has
to be re-installed. A paid Apple Developer account is what removes that limit and
enables TestFlight.

Unicode in PDF reports
----------------------

Released builds bundle IBM Plex Sans, so a curly quote or an accented character
typed into a clinical note comes out as itself.

If you are building from a source tree whose ``assets/fonts/`` is empty, the PDF
exporter falls back to a built-in font that covers Latin-1 only, and those
characters are replaced with ``?``. **The app tells you when this happens**, so
the substitution is never silent. To fix it, restore the two OFL-licensed
files:

.. code-block:: text

   assets/fonts/IBMPlexSans-Regular.ttf
   assets/fonts/IBMPlexSans-Bold.ttf

from the **static** TrueType builds of
`IBM Plex Sans <https://fonts.google.com/specimen/IBM+Plex+Sans>`_. Word export
is unaffected either way, since ``.docx`` uses the reader's own fonts.

Where your data goes
--------------------

Files are written where you choose to save them, via the platform's own file
picker or share sheet. The app keeps no hidden database and uploads nothing.
Application preferences (scale presets, paper size, panel order) are stored in
the OS application-support directory for the app.
