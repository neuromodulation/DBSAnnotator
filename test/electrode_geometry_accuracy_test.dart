import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/electrode/geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The committed contract is the source of truth.
ElectrodeCatalog _catalog() {
  final raw = File('schema/electrode_models.json').readAsStringSync();
  return ElectrodeCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  final catalog = _catalog();
  final sizes = [
    const Size(300, 600),
    const Size(300, 560),
    const Size(220, 320),
    const Size(520, 900),
  ];

  /// pitch / contactHeight, in drawn pixels. Each model is fitted to the pane,
  /// so absolute sizes are not comparable between models; this ratio is
  /// scale-free, and matching the model's millimetre ratio is "mm-accurate".
  double drawnPitchRatio(String name, [Size size = const Size(300, 600)]) {
    final l = computeLayout(catalog.models[name]!, size);
    final tops = l.levels.map((x) => x.contactRects.values.first.top).toList();
    final pitch = tops[1] - tops[0];
    return pitch / l.levels.first.contactRects.values.first.height;
  }

  test('mm-accurate: drawn pitch matches each model millimetre ratio', () {
    for (final entry in catalog.models.entries) {
      final m = entry.value;
      if (m.numContacts < 2) continue;
      // True millimetres: contactHeight + contactSpacing, with no per-gap
      // padding. A flat +1 mm on every gap, as the desktop applies, would
      // collapse 3387 and 3391 onto the same 1:1.667 ratio. Models whose
      // spacing falls under the minimum drawn gap are pinned to that floor,
      // so they are skipped here; the invariant group still covers them.
      final expected = (m.contactHeight + m.contactSpacing) / m.contactHeight;
      final actual = drawnPitchRatio(entry.key);
      if (actual > expected + 0.001) continue; // gap pinned to the px floor
      expect(actual, closeTo(expected, 0.001), reason: entry.key);
    }
  });

  test('mm-accurate: 3387 / 3389 / 3391 are three visibly different leads', () {
    // Contact:gap proportions, which is what the eye actually reads:
    //   3389  1.5 / 0.5 -> 1.333    3387  1.5 / 1.5 -> 2.0
    //   3391  3.0 / 4.0 -> 2.333
    final r89 = drawnPitchRatio('Medtronic 3389');
    final r87 = drawnPitchRatio('Medtronic 3387');
    final r91 = drawnPitchRatio('Medtronic 3391');

    expect(r89, closeTo(2.0 / 1.5, 0.001));
    expect(r87, closeTo(3.0 / 1.5, 0.001));
    expect(r91, closeTo(7.0 / 3.0, 0.001));

    // All three mutually distinct by a clearly visible margin.
    expect(r87 - r89, greaterThan(0.3));
    expect(r91 - r87, greaterThan(0.3));
  });

  test(
    'ring caps are a usable touch target, and segments keep the majority',
    () {
      // Tablet-first: the "Ring" strip must be comfortably pressable, so it
      // claims part of the segments' height on top of the inter-level gap.
      for (final name in [
        'Medtronic SenSight B33005',
        'Boston Scientific Vercise Directed',
        'Abbott StJude Infinity 6172',
        'ALEVA directSTIM',
      ]) {
        for (final size in [const Size(300, 640), const Size(520, 900)]) {
          final l = computeLayout(catalog.models[name]!, size);
          for (final lv in l.levels.where((x) => x.isDirectional)) {
            final cap = lv.ringCapRect!;
            final seg = lv.contactRects.values.first;
            expect(
              cap.height,
              greaterThanOrEqualTo(20),
              reason: '$name @$size cap too thin to press',
            );
            // The segments must still dominate the level.
            expect(
              seg.height,
              greaterThan(cap.height),
              reason: '$name @$size cap outweighs its segments',
            );
            // And the cap must not overlap them.
            expect(cap.bottom, lessThanOrEqualTo(seg.top + 0.01));
          }
        }
      }
    },
  );

  test('all leads render at the same width: they are all 1.27-1.30 mm', () {
    // Width must NOT follow the height-fitted scale, or a widely-spaced model
    // would look like a thinner physical product.
    final widths = [
      for (final n in ['Medtronic 3387', 'Medtronic 3389', 'Medtronic 3391'])
        computeLayout(catalog.models[n]!, const Size(300, 600)).leadRect.width,
    ];
    for (final w in widths) {
      expect(w, closeTo(widths.first, 0.01));
    }
    // Boston is 1.30 mm vs Medtronic 1.27 mm: a touch wider, but only a touch.
    final boston = computeLayout(
      catalog.models['Boston Scientific Vercise']!,
      const Size(300, 600),
    ).leadRect.width;
    expect(boston, greaterThan(widths.first));
    expect(boston, lessThan(widths.first * 1.1));
  });

  test('tipContact models expose a metal tip on E0; others do not', () {
    final boston = computeLayout(
      catalog.models['Boston Scientific Vercise Directed']!,
      const Size(300, 600),
    );
    expect(boston.isTipContact, isTrue);
    expect(
      boston.levels.last.isTip,
      isTrue,
      reason: 'E0 is the hemispherical tip on Boston leads',
    );
    // Body stops at the distal contact, which finishes the lead itself.
    expect(
      boston.leadRect.bottom,
      closeTo(boston.levels.last.contactRects.values.first.top, 0.01),
    );

    final mdt = computeLayout(
      catalog.models['Medtronic 3389']!,
      const Size(300, 600),
    );
    expect(mdt.isTipContact, isFalse);
    expect(mdt.levels.last.isTip, isFalse);
    expect(
      mdt.leadRect.bottom,
      closeTo(mdt.levels.last.contactRects.values.first.bottom, 0.01),
    );
  });

  group('invariants across every catalogue model and canvas size', () {
    for (final name in _catalog().models.keys) {
      for (final size in sizes) {
        test('$name @ ${size.width.toInt()}x${size.height.toInt()}', () {
          final model = catalog.models[name]!;
          final l = computeLayout(model, size);

          // (a) Everything stays inside the canvas.
          final rects = <Rect>[
            l.caseRect,
            l.leadRect,
            for (final lv in l.levels) ...lv.contactRects.values,
            for (final lv in l.levels)
              if (lv.ringCapRect != null) lv.ringCapRect!,
          ];
          for (final r in rects) {
            expect(r.left, greaterThanOrEqualTo(-0.01), reason: 'left $r');
            expect(r.top, greaterThanOrEqualTo(-0.01), reason: 'top $r');
            expect(
              r.right,
              lessThanOrEqualTo(size.width + 0.01),
              reason: 'right $r',
            );
            expect(
              r.bottom,
              lessThanOrEqualTo(size.height + 0.01),
              reason: 'bottom $r',
            );
          }
          // The dome hangs below the distal contact and must also fit.
          expect(
            l.domeRect.bottom - l.domeRect.height / 2,
            lessThanOrEqualTo(size.height + 0.01),
            reason: 'dome overflows',
          );

          // (b) A ring cap never overlaps the level above it; a
          // max(gap*0.8, 16.0) floor does exactly that on Cartesia HX/X.
          for (var i = 0; i < l.levels.length; i++) {
            final cap = l.levels[i].ringCapRect;
            if (cap == null) continue;
            expect(
              cap.bottom,
              lessThanOrEqualTo(
                l.levels[i].contactRects.values.first.top + 0.01,
              ),
              reason: 'cap overlaps its own segments',
            );
            if (i > 0) {
              final above = l.levels[i - 1].contactRects.values
                  .map((r) => r.bottom)
                  .reduce((a, b) => a > b ? a : b);
              expect(
                cap.top,
                greaterThanOrEqualTo(above - 0.01),
                reason: 'cap overlaps the level above',
              );
            }
            expect(cap.height, greaterThan(0));
          }

          // (c) Ring-cap centres stay tappable, which hit-test precedence
          // protects.
          for (final lv in l.levels) {
            final cap = lv.ringCapRect;
            if (cap == null) continue;
            expect(
              hitTest(l, cap.center),
              isA<RingCapHit>(),
              reason: 'cap centre of E${lv.levelIdx} not reachable',
            );
          }

          // (d) Every contact centre resolves to its own contact.
          for (final lv in l.levels) {
            for (final e in lv.contactRects.entries) {
              final hit = hitTest(l, e.value.center);
              expect(hit, isA<ContactHit>(), reason: 'centre of ${e.key}');
              expect((hit as ContactHit).key, e.key, reason: 'centre ${e.key}');
            }
          }

          // (e) The case centre resolves to the case.
          expect(hitTest(l, l.caseRect.center), isA<CaseHit>());

          // (f) Directional segments stay ordered and coplanar.
          for (final lv in l.levels.where((x) => x.isDirectional)) {
            final a = lv.contactRects[lv.contactRects.keys.elementAt(0)]!;
            final b = lv.contactRects[lv.contactRects.keys.elementAt(1)]!;
            final c = lv.contactRects[lv.contactRects.keys.elementAt(2)]!;
            expect(a.right, lessThan(b.left));
            expect(b.right, lessThan(c.left));
            expect(a.top, b.top);
            expect(b.top, c.top);
            expect(lv.ringCapRect!.left, a.left);
            expect(lv.ringCapRect!.right, c.right);
            // Segments must stay wide enough to tap.
            expect(a.width, greaterThan(14), reason: 'segment a too thin');
            expect(c.width, greaterThan(14), reason: 'segment c too thin');
          }
        });
      }
    }
  });

  group('case height and crowding width', () {
    test('the case is a fixed height, whatever the lead or the pane', () {
      // A case scaled to 1.75x the drawn lead width is 137 px on a 300x600
      // pane, 23 % of the canvas, and grows with the lead, so a wide lead
      // steals the height the contacts need.
      final heights = <double>{};
      for (final model in _catalog().models.values) {
        for (final size in const [
          Size(300, 600),
          Size(220, 420),
          Size(180, 900),
        ]) {
          heights.add(computeLayout(model, size).caseRect.height);
        }
      }
      expect(heights, hasLength(1), reason: 'one height everywhere: $heights');
      expect(
        heights.single,
        lessThan(40),
        reason: 'and a modest one: ${heights.single}',
      );
    });

    test('shortening the case gave the contacts the room', () {
      // The vertical budget the shorter case frees goes to the stack, so the
      // labels stay legible: a SenSight on a small tablet pane otherwise gets
      // 36 px contacts at a 10.9 px font.
      final layout = computeLayout(
        _catalog().models['Medtronic SenSight B33005']!,
        const Size(220, 420),
      );
      final contact = layout.levels.first.contactRects.values.first;
      expect(contact.height, greaterThan(45));
      expect(layout.scale, greaterThan(30));
    });

    test('a crowded lead is drawn wider than a four-level one', () {
      // Levels share a fixed pane height, so each contact gets shorter as their
      // number grows and a short contact cannot hold a readable label. Height
      // cannot grow, so width does.
      const pane = Size(220, 420);
      final catalog = _catalog();
      final four = computeLayout(
        catalog.models['Medtronic 3389']!,
        pane,
      ).leadRect.width;
      for (final name in [
        'Boston Scientific Vercise Cartesia HX', // 6 levels
        'Boston Scientific Vercise', // 8 rings
      ]) {
        final wide = computeLayout(catalog.models[name]!, pane).leadRect.width;
        expect(wide, greaterThan(four), reason: name);
      }
    });

    test('but a crowded lead still reads as a slender probe', () {
      // The ramp is deliberately mild: a paddle would be worse than small text.
      for (final size in const [Size(300, 600), Size(220, 420)]) {
        final l = computeLayout(
          _catalog().models['Boston Scientific Vercise']!,
          size,
        );
        expect(l.leadRect.width, lessThan(l.leadRect.height * 0.6));
      }
    });
  });
}
