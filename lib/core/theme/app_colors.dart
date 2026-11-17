import 'package:flutter/material.dart';

/// Warm, faded 70s palette: paper, ink and a few poster colors.
///
/// Paper, card and ink come in a day and a night version (the night one is
/// used while the reader's page color is Night). The poster colors are the
/// same in both.
abstract final class AppColors {
  static bool _night = false;

  /// Whether the night version is in use.
  static bool get night => _night;

  /// Switches version; returns whether that changed anything. Widgets read
  /// the colors when they build, so the caller rebuilds them (see `App`).
  static bool useNight(bool value) {
    if (_night == value) return false;
    _night = value;
    return true;
  }

  /// Screen background.
  static Color get paper =>
      _night ? const Color(0xFF15120F) : const Color(0xFFF4EAD5);

  /// A step away from [paper]: empty tracks and bars.
  static Color get paperDark =>
      _night ? const Color(0xFF2E2822) : const Color(0xFFE6D7B6);

  /// Cards, sheets, dialogs and menus.
  static Color get card =>
      _night ? const Color(0xFF221D19) : const Color(0xFFFCF6E6);

  /// Text, icons and outlines on [paper] and [card].
  static Color get ink =>
      _night ? const Color(0xFFE6DCC8) : const Color(0xFF2A1E17);

  /// The hard offset shadow of a box. A light one would glow at night.
  static Color get shadow => _night ? const Color(0xFF000000) : ink;

  static const terracotta = Color(0xFFC4572F);
  static const mustard = Color(0xFFE3A72F);
  static const teal = Color(0xFF2E6F6A);
  static const navy = Color(0xFF2B3A55);

  /// Text and icons on a light poster color (mustard, a highlight color).
  static const onLight = Color(0xFF2A1E17);

  /// Text and icons on a dark poster color (terracotta, teal, navy).
  static const onDark = Color(0xFFFCF6E6);

  /// Used for generated covers when a PDF has no cover image.
  static const covers = [terracotta, teal, mustard, navy];
}
