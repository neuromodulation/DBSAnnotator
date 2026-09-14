/// The electrode painter, split out of `electrode_view.dart` so the report
/// layer can rasterise a lead offscreen without importing a widget.
///
/// The lead is a vertical cylinder, so all shading varies along x only, with a
/// single light from the upper-left putting the specular highlight at
/// [_specular] of the lead width. Every element (body, ring contacts, all three
/// directional segments, the dome) is filled with a gradient built from ONE
/// shared silhouette rect, [ElectrodeLayout.leadRect], so they read as one lit
/// cylinder rather than a stack of separately-lit parts. The desktop canvas
/// instead gives every contact its own radial gradient centred in its own
/// bounding box, which is why its contacts read as detached glossy buttons.
///
/// Two materials are kept visually distinct: matte insulating polymer for the
/// body and dome, polished platinum-iridium for the contacts. An active contact
/// is *tinted metal*, so the specular survives and it still reads as metal.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/electrode/contact_state.dart';
import '../core/electrode/geometry.dart';
import '../core/electrode/stimulation_rule.dart';
import 'theme.dart';
import 'painter_font.dart';

/// Fraction of the lead width where the specular highlight sits (light from
/// the upper-left).
const double _specular = 0.32;

/// Painter for one lead: cylinder body, CASE, ring / segmented contacts, ring
/// caps and the hemispherical tip.
class ElectrodePainter extends CustomPainter {
  ElectrodePainter({
    required this.layout,
    required this.states,
    required this.caseState,
    required this.labelColor,
    this.palette = ElectrodePalette.light,
  });

  final ElectrodeLayout layout;
  final Map<ContactKey, ContactState> states;
  final ContactState caseState;

  /// Theme text colour for the E{idx} labels beside the lead.
  final Color labelColor;

  /// Inert lead material colours (theme-aware; reports force light).
  final ElectrodePalette palette;

  static const _segmentLabels = ['a', 'b', 'c'];

  static Color _base(ContactState s) => switch (s) {
    ContactState.anodic => DbsColors.anodicBase,
    ContactState.cathodic => DbsColors.cathodicBase,
    ContactState.off => DbsColors.offBase,
  };

  static Color _border(ContactState s) => switch (s) {
    ContactState.anodic => DbsColors.anodicBorder,
    ContactState.cathodic => DbsColors.cathodicBorder,
    ContactState.off => DbsColors.offBorder,
  };

  /// Blend toward white, not an HSV-value shift: that desaturates unpredictably
  /// (`#ff6464` "lightens" to nearly white), and its Qt sibling `darker(80)`
  /// brightens instead of darkening.
  static Color _tint(Color c, double t) => Color.lerp(c, Colors.white, t)!;

  /// Blend toward black.
  static Color _shade(Color c, double t) => Color.lerp(c, Colors.black, t)!;

  /// Polished-metal gradient across the cylinder: dark rims at both silhouette
  /// edges, a narrow bright band at [_specular]. Applied with the shared lead
  /// rect so every contact is lit identically.
  Shader _metalShader(Color base, Rect span) => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      _shade(base, 0.34),
      _shade(base, 0.10),
      _tint(base, 0.62),
      _tint(base, 0.10),
      _shade(base, 0.20),
      _shade(base, 0.42),
    ],
    stops: const [
      0.0,
      _specular - 0.16,
      _specular,
      _specular + 0.26,
      0.84,
      1.0,
    ],
  ).createShader(span);

  /// Matte polymer gradient: same light, far less contrast, no specular spike.
  Shader _polymerShader(Rect span) => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      _shade(palette.polymer, 0.22),
      _shade(palette.polymer, 0.04),
      _tint(palette.polymer, 0.30),
      palette.polymer,
      _shade(palette.polymer, 0.26),
    ],
    stops: const [0.0, _specular - 0.14, _specular, 0.72, 1.0],
  ).createShader(span);

  /// Very subtle vertical darkening at a band's top and bottom edge, which
  /// seats the metal onto the cylinder. Cheap two-draw alternative to the old
  /// per-contact offset drop shadows.
  Shader _seatShader(Rect rect) => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x26000000),
      Color(0x00000000),
      Color(0x00000000),
      Color(0x1F000000),
    ],
    stops: [0.0, 0.22, 0.78, 1.0],
  ).createShader(rect);

  /// The insulating lead body plus its distal dome, or on `tipContact` models
  /// just the body: there the dome belongs to E0 and is painted as metal.
  void _paintLead(Canvas canvas) {
    final span = layout.leadRect;
    final path = Path()..addRect(span);
    if (!layout.isTipContact) {
      path.addArc(layout.domeRect, 0, math.pi);
    }
    canvas
      ..drawPath(path, Paint()..shader = _polymerShader(span))
      ..drawPath(
        path,
        Paint()
          ..color = palette.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
  }

  /// A ring contact, or one directional segment. Square-cornered and exactly
  /// the lead width, so the cylinder silhouette stays one continuous line
  /// (rounded or over-wide contacts let the body show through at every
  /// corner). [shape] lets a directional segment taper.
  void _paintContact(
    Canvas canvas,
    Rect rect,
    ContactState state, {
    Path? shape,
    bool tip = false,
  }) {
    final span = layout.leadRect;
    final base = _base(state);
    final path =
        shape ??
        (tip
            ? (Path()
                ..addRect(rect)
                ..addArc(layout.domeRect, 0, math.pi))
            : (Path()..addRect(rect)));

    canvas
      ..drawPath(path, Paint()..shader = _metalShader(base, span))
      ..drawPath(path, Paint()..shader = _seatShader(rect))
      ..drawPath(
        path,
        Paint()
          ..color = state == ContactState.off
              ? _border(state).withValues(alpha: 0.55)
              : _border(state)
          ..style = PaintingStyle.stroke
          ..strokeWidth = state == ContactState.off ? 0.9 : 1.8,
      );
  }

  /// The CASE (ground / IPG can): vertical gradient plus a feathered specular
  /// sweep across the upper third, not a hard-edged white rounded rect.
  void _paintCase(Canvas canvas, Rect rect, ContactState state) {
    final base = _base(state);
    final r = Radius.circular(rect.width * 0.14);
    final rrect = RRect.fromRectAndRadius(rect, r);
    canvas
      ..drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_tint(base, 0.30), base, _shade(base, 0.24)],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(rect),
      )
      ..save()
      ..clipRRect(rrect)
      ..drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.42),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x59FFFFFF), Color(0x00FFFFFF)],
          ).createShader(rect),
      )
      ..restore()
      ..drawRRect(
        rrect,
        Paint()
          ..color = _border(state)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
  }

  /// The "cycle all three segments together" affordance. Deliberately
  /// understated, a slim flat strip, so the contacts stay the dominant shapes:
  /// on a five-segment Cartesia a glossy tall cap turns the lead into buttons.
  void _paintCap(Canvas canvas, Rect rect, ContactState state) {
    final base = _base(state);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
    canvas
      ..drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Darkens downward. A Qt `darker(80)` port lightens here,
            // because it divides by the percentage.
            colors: [_tint(base, 0.30), _shade(base, 0.04)],
          ).createShader(rect),
      )
      ..drawRRect(
        rrect,
        Paint()
          ..color = _border(state).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
  }

  /// One soft ambient shadow behind the whole lead. Per-element offset
  /// shadows, one per contact and cap, make the canvas look cluttered.
  void _paintAmbientShadow(Canvas canvas) {
    final silhouette = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          layout.caseRect,
          Radius.circular(layout.caseRect.width * 0.14),
        ),
      )
      ..addRect(layout.leadRect)
      ..addArc(layout.domeRect, 0, math.pi);
    canvas.drawPath(
      silhouette.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x2E000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
  }

  /// Label colour on a contact: white on active, near-black on OFF metal.
  static Color _labelOn(ContactState state) => state == ContactState.off
      ? const Color(0xFF1A1A1A)
      : const Color(0xFFFFFFFF);

  /// Font sizes track the rendered lead (via `scale` px/mm) instead of being
  /// hard-coded, so labels stay proportionate on a 320 px pane and a 900 px.
  double _font(double perMm, double lo, double hi) =>
      (layout.scale * perMm).clamp(lo, hi);

  void _paintTextCentered(
    Canvas canvas,
    String text,
    Rect rect,
    Color color,
    double fontSize, {
    bool halo = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: debugPainterFontFamily,
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          height: 1,
          shadows: halo
              ? const [Shadow(color: Color(0x66000000), blurRadius: 2)]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Optically centre: TextPainter's box includes font leading.
    painter.paint(
      canvas,
      rect.center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  /// `E{idx}` in the left gutter, right-aligned to a single column shared by
  /// every level, plus a polarity badge when the level is driven. The old
  /// version aligned to each level's own leftmost rect, so directional labels
  /// sat further left than ring labels; the desktop is worse still, drawing
  /// ring labels *on top of* the contact.
  void _paintLevelLabel(Canvas canvas, LevelLayout level, double gutterRight) {
    final rect = level.contactRects.values.first;
    final polarity = _levelPolarity(level);
    final text =
        'E${level.levelIdx}${switch (polarity) {
          ContactState.anodic => ' +',
          ContactState.cathodic => ' -',
          ContactState.off => '',
        }}';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: debugPainterFontFamily,
          color: polarity == ContactState.off ? labelColor : _border(polarity),
          fontSize: _font(0.46, 10, 20),
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(gutterRight - painter.width, rect.center.dy - painter.height / 2),
    );
  }

  /// The level's polarity for the label badge: the common state of its
  /// contacts, or OFF when they disagree.
  ContactState _levelPolarity(LevelLayout level) {
    final seen = <ContactState>{
      for (final key in level.contactRects.keys)
        states[key] ?? ContactState.off,
    };
    return seen.length == 1 ? seen.first : ContactState.off;
  }

  ContactState _ringState(int levelIdx) {
    final segStates = [
      for (var seg = 0; seg < 3; seg++)
        states[ContactKey(levelIdx, seg)] ?? ContactState.off,
    ];
    if (segStates.every((s) => s == ContactState.anodic)) {
      return ContactState.anodic;
    }
    if (segStates.every((s) => s == ContactState.cathodic)) {
      return ContactState.cathodic;
    }
    return ContactState.off;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintAmbientShadow(canvas);
    _paintLead(canvas);

    _paintCase(canvas, layout.caseRect, caseState);
    _paintTextCentered(
      canvas,
      'CASE',
      layout.caseRect,
      _labelOn(caseState),
      _font(0.38, 9, 18),
    );

    // A single gutter column for every E-label, just left of the widest level.
    final gutterRight =
        layout.levels
            .map(
              (l) => l.contactRects.values.map((r) => r.left).reduce(math.min),
            )
            .reduce(math.min) -
        8;

    for (final level in layout.levels) {
      // Ring caps first, so the segments they sit above overlap them cleanly.
      final cap = level.ringCapRect;
      if (cap != null) {
        final ringState = _ringState(level.levelIdx);
        _paintCap(canvas, cap, ringState);
        _paintTextCentered(
          canvas,
          'Ring',
          cap,
          _labelOn(ringState),
          _font(0.28, 7, 13),
        );
      }

      for (final entry in level.contactRects.entries) {
        final state = states[entry.key] ?? ContactState.off;
        final rect = entry.value;
        if (level.isDirectional) {
          _paintContact(canvas, rect, state);
          _paintTextCentered(
            canvas,
            _segmentLabels[entry.key.segmentIdx],
            rect,
            _labelOn(state),
            _font(0.36, 8, 16),
            halo: true,
          );
        } else {
          _paintContact(canvas, rect, state, tip: level.isTip);
        }
      }

      _paintLevelLabel(canvas, level, gutterRight);
    }
  }

  @override
  bool shouldRepaint(ElectrodePainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.states != states ||
      oldDelegate.caseState != caseState ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.palette != palette;
}
