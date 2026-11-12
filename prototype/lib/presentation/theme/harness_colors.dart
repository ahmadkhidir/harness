import 'package:flutter/material.dart';

/// A six-step tonal ramp for one brand color family.
///
/// The ramp is the unit the design system swaps on a theme change: every
/// family ships the same steps (`900`, `700`, `600`, `500`, `300`, `100`) so a
/// component asks for a step rather than a raw hex value.
///
/// The values originate from `docs/Harness/branding.md` and must not be
/// retuned at a call site.
@immutable
class ColorRamp {
  /// Text on a `100` tint, and the highest-contrast step.
  final Color c900;

  /// Hover and pressed backgrounds, secondary labels.
  final Color c700;

  /// Solid fill behind a `100` label.
  final Color c600;

  /// Base step: links, focus rings, active icons, running state.
  final Color c500;

  /// Selected backgrounds, focus glow, and borders on tinted surfaces.
  final Color c300;

  /// Tinted background for the family's selected and status surfaces.
  final Color c100;

  const ColorRamp({
    required this.c900,
    required this.c700,
    required this.c600,
    required this.c500,
    required this.c300,
    required this.c100,
  });

  /// Interpolates every step of the ramp for theme transitions.
  static ColorRamp lerp(ColorRamp a, ColorRamp b, double t) {
    return ColorRamp(
      c900: Color.lerp(a.c900, b.c900, t)!,
      c700: Color.lerp(a.c700, b.c700, t)!,
      c600: Color.lerp(a.c600, b.c600, t)!,
      c500: Color.lerp(a.c500, b.c500, t)!,
      c300: Color.lerp(a.c300, b.c300, t)!,
      c100: Color.lerp(a.c100, b.c100, t)!,
    );
  }
}

/// Every semantic color role the interface reads.
///
/// Flutter's [ColorScheme] covers the Material roles only, so the brand
/// families (success, warning, and info) and the full tonal ladder live here.
/// Access the palette with [HarnessColors.of] and prefer these roles over
/// `Theme.of(context).colorScheme` for anything brand-specific.
///
/// Structural mappings match `docs/Harness/branding.md`:
/// - `surface` = `neutral-100`
/// - `surfaceSecondary` = `neutral-200`
/// - `textPrimary` = `neutral-900`
/// - `textSecondary` = `neutral-600`
/// - `border` = `neutral-300`
/// - `borderStrong` = `neutral-500`
@immutable
class HarnessColors extends ThemeExtension<HarnessColors> {
  /// Signal Teal: the only accent, reserved for work the harness performs.
  final ColorRamp primary;

  /// Graphite: text, surfaces, and borders. Carries a slight teal cast.
  final ColorRamp neutral;

  /// Completed tool call indicator.
  final ColorRamp success;

  /// Compaction notices and limits that are nearing.
  final ColorRamp warning;

  /// Failed call indicators and destructive actions.
  final ColorRamp error;

  /// Neutral guidance and provider notices.
  final ColorRamp info;

  /// Page surface.
  final Color surface;

  /// Secondary surface and input background.
  final Color surfaceSecondary;

  /// Primary text.
  final Color textPrimary;

  /// Secondary text and metadata.
  final Color textSecondary;

  /// Hairline borders and dividers.
  final Color border;

  /// Strong borders and control outlines.
  final Color borderStrong;

  const HarnessColors({
    required this.primary,
    required this.neutral,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.surface,
    required this.surfaceSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.borderStrong,
  });

  /// Light theme palette.
  static const HarnessColors light = HarnessColors(
    primary: ColorRamp(
      c900: Color(0xFF04302D),
      c700: Color(0xFF075651),
      c600: Color(0xFF086964),
      c500: Color(0xFF0B7D76),
      c300: Color(0xFF7CC4BE),
      c100: Color(0xFFE1F4F1),
    ),
    neutral: ColorRamp(
      c900: Color(0xFF0F1615),
      c700: Color(0xFF2E3837),
      c600: Color(0xFF4A5553),
      c500: Color(0xFF6B7674),
      c300: Color(0xFFCBD2D0),
      c100: Color(0xFFF7F9F8),
    ),
    success: ColorRamp(
      c900: Color(0xFF123A16),
      c700: Color(0xFF1F6B25),
      c600: Color(0xFF2F8E35),
      c500: Color(0xFF2F8E35),
      c300: Color(0xFFA8DCAB),
      c100: Color(0xFFE9F7EA),
    ),
    warning: ColorRamp(
      c900: Color(0xFF3B2600),
      c700: Color(0xFF7A5200),
      c600: Color(0xFFA86F00),
      c500: Color(0xFFA86F00),
      c300: Color(0xFFEFCB8B),
      c100: Color(0xFFFCF2DC),
    ),
    error: ColorRamp(
      c900: Color(0xFF400C0A),
      c700: Color(0xFF861E18),
      c600: Color(0xFFB4362C),
      c500: Color(0xFFB4362C),
      c300: Color(0xFFF1B7B0),
      c100: Color(0xFFFCEBE9),
    ),
    info: ColorRamp(
      c900: Color(0xFF082A4A),
      c700: Color(0xFF14538C),
      c600: Color(0xFF1E6FB8),
      c500: Color(0xFF1E6FB8),
      c300: Color(0xFFAFD2F0),
      c100: Color(0xFFE9F3FB),
    ),
    surface: Color(0xFFF7F9F8),
    surfaceSecondary: Color(0xFFE8ECEA),
    textPrimary: Color(0xFF0F1615),
    textSecondary: Color(0xFF4A5553),
    border: Color(0xFFCBD2D0),
    borderStrong: Color(0xFF6B7674),
  );

  /// Dark theme palette. Dark is the product default.
  static const HarnessColors dark = HarnessColors(
    primary: ColorRamp(
      c900: Color(0xFFC4F0EA),
      c700: Color(0xFF86D8D0),
      c600: Color(0xFF66C6BD),
      c500: Color(0xFF48B0A7),
      c300: Color(0xFF1C625D),
      c100: Color(0xFF0C2A28),
    ),
    neutral: ColorRamp(
      c900: Color(0xFFEFF3F2),
      c700: Color(0xFFBFC7C5),
      c600: Color(0xFF9DA8A6),
      c500: Color(0xFF7C8785),
      c300: Color(0xFF38413F),
      c100: Color(0xFF141A19),
    ),
    success: ColorRamp(
      c900: Color(0xFFC9F2CC),
      c700: Color(0xFF8BD893),
      c600: Color(0xFF58BF63),
      c500: Color(0xFF58BF63),
      c300: Color(0xFF1E4D25),
      c100: Color(0xFF102A14),
    ),
    warning: ColorRamp(
      c900: Color(0xFFFFE0AE),
      c700: Color(0xFFF2C173),
      c600: Color(0xFFD9A044),
      c500: Color(0xFFD9A044),
      c300: Color(0xFF5C3D08),
      c100: Color(0xFF2E210A),
    ),
    error: ColorRamp(
      c900: Color(0xFFFFD6D1),
      c700: Color(0xFFFFA79D),
      c600: Color(0xFFEE7C70),
      c500: Color(0xFFEE7C70),
      c300: Color(0xFF6B211B),
      c100: Color(0xFF30100D),
    ),
    info: ColorRamp(
      c900: Color(0xFFCFE4FF),
      c700: Color(0xFF9DC4F5),
      c600: Color(0xFF6AA6E8),
      c500: Color(0xFF6AA6E8),
      c300: Color(0xFF14375C),
      c100: Color(0xFF0A1D30),
    ),
    surface: Color(0xFF141A19),
    surfaceSecondary: Color(0xFF222A29),
    textPrimary: Color(0xFFEFF3F2),
    textSecondary: Color(0xFF9DA8A6),
    border: Color(0xFF38413F),
    borderStrong: Color(0xFF7C8785),
  );

  /// Resolves the palette for the nearest [Theme], falling back to dark.
  static HarnessColors of(BuildContext context) {
    return Theme.of(context).extension<HarnessColors>() ?? dark;
  }

  @override
  HarnessColors copyWith({
    ColorRamp? primary,
    ColorRamp? neutral,
    ColorRamp? success,
    ColorRamp? warning,
    ColorRamp? error,
    ColorRamp? info,
    Color? surface,
    Color? surfaceSecondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? borderStrong,
  }) {
    return HarnessColors(
      primary: primary ?? this.primary,
      neutral: neutral ?? this.neutral,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
    );
  }

  @override
  HarnessColors lerp(ThemeExtension<HarnessColors>? other, double t) {
    if (other is! HarnessColors) return this;
    return HarnessColors(
      primary: ColorRamp.lerp(primary, other.primary, t),
      neutral: ColorRamp.lerp(neutral, other.neutral, t),
      success: ColorRamp.lerp(success, other.success, t),
      warning: ColorRamp.lerp(warning, other.warning, t),
      error: ColorRamp.lerp(error, other.error, t),
      info: ColorRamp.lerp(info, other.info, t),
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSecondary:
          Color.lerp(surfaceSecondary, other.surfaceSecondary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
    );
  }
}
