Key terms
=========

The words the rest of this documentation uses, in the order you meet them.

**Visit (session)**
   One programming appointment. The app records one visit per file.

**Configuration (setting)**
   One set of stimulation parameters on both leads: which contacts are active,
   the amplitude, frequency and pulse width.

**Block**
   One configuration as recorded: its parameters, contacts, scale ratings, side
   effects and notes, stamped with the time it was inserted. A visit is a series
   of blocks, numbered in order.

**Baseline**
   The first block, recorded in the *Initial configuration* step: the settings the
   patient arrived with and the clinical scores before anything was changed.

**Clinical scales**
   Validated assessments typed once per visit at baseline, such as Y-BOCS, MADRS
   or UPDRS-III.

**Session scales**
   Quick ratings taken at *every* block, each on a range you define (for example
   Obsessions 0-10), so configurations can be compared within the visit.

**Program**
   The label of the stimulation program (A, B, C...) the configuration belongs
   to. Reports call it the *group*, the term the device manufacturers use.

**Contact notation**
   How reports write a configuration: ``2b(60%) 2c(40%)- / case+`` means
   contacts 2b and 2c are cathodes (-) sharing the current 60/40, and the case
   is the anode (+).

**Scale targets**
   What "better" means for each session scale: lower, higher, or closest to a
   value. You set them; nothing is ranked until you do.

**Aggregate index**
   A score from 0 to 1 per block, computed from the session scales against the
   targets, where 1 is best. It is what the green highlighting ranks by. See
   :ref:`scale-targets`.

**BIDS**
   The Brain Imaging Data Structure, a community standard for naming and
   organising neuroscience data. The app names and lays out its files to it, so
   they can be pooled and validated with standard tools. See
   :doc:`output_format`.

**TSV and sidecar**
   Each visit is a tab-separated text file (``.tsv``) with a JSON file of the same
   name beside it, the *sidecar*, which describes every column.

**Run**
   The number that tells apart two visits of the same patient on the same day
   (``run-01``, ``run-02``).

**append_id**
   A counter in the file that goes up each time the file is reopened to add more
   blocks, so a visit continued later can be told apart from one recorded in a
   single sitting.
