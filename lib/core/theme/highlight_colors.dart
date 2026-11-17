import 'package:flutter/painting.dart';

/// The PDF viewer draws a highlight as a 30% see-through layer, and the
/// reader then tints the whole page (cream, sepia, old book). Only strong
/// colors that differ from warm paper survive that: yellow sinks into the
/// paper and blue turns grey, so amber and violet take their places.
/// The first one is the default.
const highlightColors = <Color>[
  Color(0xFFFF9100), // amber
  Color(0xFF00C853), // green
  Color(0xFFF50057), // pink
  Color(0xFF8B2CFF), // violet
];

/// Earlier highlight colors (ARGB) and what replaces them. Highlights made
/// with them are recolored when their book is opened.
const retiredHighlightColors = <int, int>{
  0xFFFFC400: 0xFFFF9100, // yellow -> amber
  0xFF2979FF: 0xFF8B2CFF, // blue -> violet
  0xFF00AAFF: 0xFF8B2CFF, // light blue (the first palette) -> violet
};

/// The color (ARGB) that replaces [argb], or null if it is not a retired
/// one. A color read back from a PDF can be a step or two off per channel,
/// so close counts.
int? replacementForHighlightColor(int argb) {
  bool near(int other) {
    for (final shift in const [16, 8, 0]) {
      final gap = ((argb >> shift) & 0xFF) - ((other >> shift) & 0xFF);
      if (gap.abs() > 4) return false;
    }
    return true;
  }

  for (final MapEntry(key: retired, value: next)
      in retiredHighlightColors.entries) {
    if (near(retired)) return next;
  }
  return null;
}
