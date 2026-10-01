import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/electrode/geometry.dart';
import 'package:dbs_annotator/core/electrode/stimulation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless tests for the pure electrode layout math. Uses the committed
/// contract in schema/electrode_models.json.
void main() {
  // Runs at group-declaration time, so no expect() here: a missing contract
  // file fails loudly through the StateError below.
  ElectrodeModel loadModel(String name) {
    final file = File('schema/electrode_models.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final catalog = ElectrodeCatalog.fromJson(json);
    return catalog.models[name] ??
        (throw StateError('Model "$name" not found in the catalog'));
  }

  const size = Size(300, 600);

  group('computeLayout: Boston Scientific Vercise Directed (directional)', () {
    // 4 contacts; levels 1 and 2 are directional, 0 and 3 are rings.
    final model = loadModel('Boston Scientific Vercise Directed');
    final layout = computeLayout(model, size);

    test('levels are in display order: E3 at the top, E0 at the bottom', () {
      expect(layout.levels.map((l) => l.levelIdx).toList(), [3, 2, 1, 0]);

      double topOf(LevelLayout level) => level.contactRects.values
          .map((r) => r.top)
          .reduce((a, b) => a < b ? a : b);
      for (var i = 0; i + 1 < layout.levels.length; i++) {
        expect(
          topOf(layout.levels[i]),
          lessThan(topOf(layout.levels[i + 1])),
          reason: 'display row $i must be above row ${i + 1}',
        );
      }
    });

    test('case rect sits above every contact', () {
      for (final level in layout.levels) {
        for (final rect in level.contactRects.values) {
          expect(layout.caseRect.bottom, lessThan(rect.top));
        }
      }
    });

    test('a directional level yields 3 segment rects + a ring-cap rect', () {
      final level2 = layout.levels[1]; // E2
      expect(level2.levelIdx, 2);
      expect(level2.isDirectional, isTrue);
      expect(level2.contactRects.keys.toSet(), {
        const ContactKey(2, 0),
        const ContactKey(2, 1),
        const ContactKey(2, 2),
      });
      expect(level2.ringCapRect, isNotNull);

      // Segments a/b/c are laid out left/center/right at the same height.
      final a = level2.contactRects[const ContactKey(2, 0)]!;
      final b = level2.contactRects[const ContactKey(2, 1)]!;
      final c = level2.contactRects[const ContactKey(2, 2)]!;
      expect(a.right, lessThan(b.left));
      expect(b.right, lessThan(c.left));
      expect(a.top, b.top);
      expect(b.top, c.top);

      // Ring cap sits just above the segments and spans their full width.
      expect(level2.ringCapRect!.bottom, lessThanOrEqualTo(a.top));
      expect(level2.ringCapRect!.left, a.left);
      expect(level2.ringCapRect!.right, c.right);
    });

    test('a ring level yields exactly 1 rect and no ring cap', () {
      for (final levelIdx in [0, 3]) {
        final level = layout.levels.firstWhere((l) => l.levelIdx == levelIdx);
        expect(level.isDirectional, isFalse);
        expect(level.contactRects.keys.toList(), [ContactKey(levelIdx, 0)]);
        expect(level.ringCapRect, isNull);
      }
    });

    test('hitTest resolves segments, ring cap, case, and misses', () {
      final level2 = layout.levels[1];

      // Center of a known segment -> that ContactKey.
      for (var seg = 0; seg < 3; seg++) {
        final key = ContactKey(2, seg);
        final hit = hitTest(layout, level2.contactRects[key]!.center);
        expect(hit, isA<ContactHit>());
        expect((hit! as ContactHit).key, key);
      }

      // Ring rect of E0 -> ContactKey(0, 0).
      final e0 = layout.levels.last.contactRects[const ContactKey(0, 0)]!;
      final e0Hit = hitTest(layout, e0.center);
      expect(e0Hit, isA<ContactHit>());
      expect((e0Hit! as ContactHit).key, const ContactKey(0, 0));

      // Ring cap center -> RingCapHit for that level.
      final capHit = hitTest(layout, level2.ringCapRect!.center);
      expect(capHit, isA<RingCapHit>());
      expect((capHit! as RingCapHit).levelIdx, 2);

      // Case rect -> CaseHit.
      expect(hitTest(layout, layout.caseRect.center), isA<CaseHit>());

      // Far corner -> nothing.
      expect(hitTest(layout, const Offset(2, 2)), isNull);
    });

    test(
      'generous tap padding: a point just outside a segment still hits it',
      () {
        final b = layout.levels[1].contactRects[const ContactKey(2, 1)]!;
        final justBelow = Offset(b.center.dx, b.bottom + 4);
        final hit = hitTest(layout, justBelow);
        expect(hit, isA<ContactHit>());
        expect((hit! as ContactHit).key, const ContactKey(2, 1));
      },
    );
  });

  group('computeLayout: Medtronic 3389 (non-directional)', () {
    final model = loadModel('Medtronic 3389');
    final layout = computeLayout(model, size);

    test('every level is a single full-width ring rect, no ring caps', () {
      expect(layout.levels.map((l) => l.levelIdx).toList(), [3, 2, 1, 0]);
      for (final level in layout.levels) {
        expect(level.isDirectional, isFalse);
        expect(level.contactRects.length, 1);
        expect(level.contactRects.keys.single, ContactKey(level.levelIdx, 0));
        expect(level.ringCapRect, isNull);
      }
    });

    test('all rects fit inside the canvas', () {
      final all = [
        layout.caseRect,
        layout.leadRect,
        for (final level in layout.levels) ...level.contactRects.values,
      ];
      for (final rect in all) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
    });
  });
}
