/// The brand palette as `PdfColor`s, so a printed report carries the same
/// colours as the app rather than Material's default greys.
library;

import 'package:pdf/pdf.dart';

import '../core/brand_palette.dart';

/// Rank 1 and rank 2 row shading and chart bands.
const pdfBestFill = PdfColor.fromInt(kBestFill);
const pdfSecondFill = PdfColor.fromInt(kSecondFill);

/// Footers, meta lines and secondary labels. 5.02:1 on white.
const pdfInk = PdfColor.fromInt(kInkMuted);

/// Rules and panel borders.
const pdfRule = PdfColor.fromInt(kRuleColor);

/// Table header fills.
const pdfHeaderFill = PdfColor.fromInt(kHeaderFill);

/// The page-1 summary box and other tinted panels.
const pdfPanelFill = PdfColor.fromInt(kPanelFill);
