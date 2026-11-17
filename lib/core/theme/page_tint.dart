import 'package:flutter/material.dart';

/// Page background for the PDF reader (old-book looks).
///
/// Light tints multiply the page, so white paper takes the tint color and
/// black text stays black. Night inverts the page to light text on dark.
enum PageTint {
  white('White', Color(0xFFFFFFFF)),
  cream('Cream', Color(0xFFF8F1DC)),
  sepia('Sepia', Color(0xFFF1E2C2)),
  oldBook('Old book', Color(0xFFE6CF9C)),
  sage('Sage', Color(0xFFDCE8D5)),
  night('Night', Color(0xFF1E1B18));

  const PageTint(this.label, this.swatch);

  final String label;

  /// How a blank page looks with this tint.
  final Color swatch;

  bool get isDark => this == night;

  /// Text color for previews drawn on [swatch].
  Color get textColor =>
      isDark ? const Color(0xFFE1DACD) : const Color(0xFF1A1A1A);

  /// A blank page after [filter] is applied (white run through the filter).
  /// Lets pre-rendered pages be tinted once instead of filtered every frame.
  Color get blank => isDark ? const Color(0xFF010000) : swatch;

  ColorFilter get filter =>
      isDark ? _nightFilter : ColorFilter.mode(swatch, BlendMode.multiply);

  static const _nightFilter = ColorFilter.matrix(<double>[
    -0.88, 0, 0, 0, 225, //
    0, -0.88, 0, 0, 218,
    0, 0, -0.88, 0, 205,
    0, 0, 0, 1, 0,
  ]);
}
