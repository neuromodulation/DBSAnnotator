Reports
=======

Every workflow can produce a report in **PDF** and in **Word** (``.docx``). Both
are built from the same computed values, so the two documents cannot disagree
with each other, a property worth having when one is filed and the other is
edited.

Choosing what goes in
---------------------

Exporting asks which sections to include, and lets you set the
:ref:`scale targets <scale-targets>` at the same time. Paper size (A4 or Letter)
applies to both formats.

The patient header is always present, so a report is never anonymous.

Session report
--------------

**Header.** Patient ID, the session date and clock span *taken from the recorded
rows* with their UTC offset, and separately the date the document was generated,
the app version, and the source filename with its row count. The session date and
the generation date are distinct fields on purpose: a report produced a fortnight
later must not assert that the session happened the day the button was pressed.

**Last recorded configuration.** A box on page one giving the final settings per
side in vendor notation: contacts with their share of current, total milliamps,
frequency, pulse width and group. Named for what it is, the last block in the
file. Nothing in the data records that a clinician *confirmed* it.

**Baseline assessment (pre-session).** The clinical scores recorded before
stimulation changes began, as a two-column table, plus the baseline notes.

**Session data.** The figure and the table.

*The figure* plots each session scale against configuration, with the aggregate
index and, when targets are set, green bands on the best and second-best
scoring settings.

*The table* gives one row per side per block: time, group, frequency, anode,
cathode with the per-contact current share, total amplitude, pulse width, the
scale ratings, the aggregate index with its rank, and notes. Values belonging to
the block are printed once, not repeated per side.

**Recorded observations.** Every block that carries a note, listed with its time
and the stimulation active at the time. This exists because side effects are the
safety content of a session and are unreadable buried in a table cell.

**Response.** Each scale's first and last recorded value with the change between
them. This is the clinical bottom line, and it cannot be recovered from the
parameter ranges alone.

**Electrode configuration.** The initial and last-recorded settings as four lead
diagrams in one row, each captioned with its configuration in words, plus a key
for the polarity colours. The caption matters: the drawing shows *which* contacts
are active but not how current is shared, and for current steering the split is
the configuration.

**Programming summary.** Annotation span, configurations tested with the number
of distinct settings among them, and the amplitude, frequency and pulse-width
ranges actually tried.

**Attestation.** Recorded by / Reviewed by / Date.

Annotations report
------------------

A patient header, the notes in a time-and-text table oldest-first, the span they
cover, and an attestation block. See :doc:`screens/annotations`.

Longitudinal report
-------------------

Several sessions of one patient, compared across visits. See
:doc:`screens/reports` for the screen that produces it. There are two
figures, because they answer different questions:

**Clinical scales by visit.** One assessment per visit, so the x axis is the
visit itself, labelled ``<date>_<run>``. This is the "is the patient better than
last time" figure.

**Session scales by visit and block.** Several configurations per visit, so each
visit contributes a run of points.

Then a per-visit table giving the date, the programme in force at the end of
that visit, the number of blocks, and the primary clinical scale with its
change from the previous visit. The source file list is an appendix.

If the imported files name more than one patient, the report says so in a box on
page one. Combining two people into one longitudinal report is a safety problem,
not a formatting one.

.. _scale-targets:

Scale targets
-------------

Ranking configurations requires knowing what "better" means for each scale, and
only you know that. Each scale gets a mode:

``Min``
   Lower is better, as for a symptom severity score.

``Max``
   Higher is better, as for a function or quality-of-life score.

``Custom``
   Closest to a stated value is better.

``Ignore``
   Excluded from the ranking.

The aggregate index is the unweighted mean, across the scales rated at that
block, of each value normalised into its declared range and oriented by its
target, clipped to 0-1, where 1 is best. A scale with no target contributes a
neutral 0.5 at half weight. The report prints this definition alongside the
figure, and prints the bounds each scale was normalised into, so the number can
be reproduced.

.. _what-the-reports-do-not-say:

What the reports do not say
---------------------------

The ranking is a computation over recorded scale values, and its limits are
worth stating here as plainly as the reports themselves state them.

**It does not account for side effects or tolerability.** A configuration that
scored well on every scale and produced an intolerable paraesthesia will be
ranked highly. The notes column is not an input.

**It is not a recommendation.** It does not say which settings to programme.

**It will not run without targets.** With no scale targets set, no configuration
is ranked, nothing is shaded green, and the report says so. Defaulting every
scale to "lower is better" would silently score *falling mood* and *falling
energy* as improvements, and inventing a clinical intention is worse than
declining to rank.

**"Last recorded configuration" is not "chosen".** It is the final block in the
file. A setting that was tried and rejected would appear there identically.

**The numbers carry no instrument metadata.** The record stores no scale anchors,
administration method or rater, so the reports state that those cannot be
reproduced from the document.

Where the session's own data allows it, the report also prints the spread between
repeat ratings of an unchanged setting, which measures how far the index moves
when nothing changes, so that two settings closer together than that can be seen
for what they are.
