import 'package:flutter/material.dart';

import 'harness_colors.dart';

/// Spacing scale.
///
/// Every gap, pad, and margin in the interface is one of these steps. A call
/// site never invents an in-between value.
abstract final class HarnessSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Fixed component sizes.
abstract final class HarnessSize {
  /// Minimum hit area for every interactive element.
  static const double touchTarget = 44;

  /// Primary, secondary, outline, and destructive button height.
  static const double button = 48;

  /// Composer and text field height.
  static const double input = 48;

  /// Session app bar height.
  static const double appBar = 56;

  /// Tool call pills and status chips.
  static const double pill = 28;

  /// Timer strip above the composer.
  static const double timerStrip = 40;

  /// Composer growth cap before it scrolls internally.
  static const double composerMax = 168;

  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
}

/// Corner radii.
abstract final class HarnessRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double full = 9999;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
}

/// Motion character.
///
/// Mechanical and quick: a state change lands in one beat and nothing loops
/// for atmosphere.
abstract final class HarnessMotion {
  /// State changes, presses, and selection moves.
  static const Duration quick = Duration(milliseconds: 120);

  /// Layout and sheet transitions.
  static const Duration standard = Duration(milliseconds: 220);

  /// Scroll-to-end and other content moves.
  static const Duration content = Duration(milliseconds: 260);

  /// The cubic used for every transition; no overshoot or elastic curves.
  static const Curve curve = Curves.easeOutCubic;
}

/// Elevation tokens.
abstract final class HarnessShadows {
  /// Composer bar and app bar separation from the message stream.
  static List<BoxShadow> get lightSm => const [
        BoxShadow(
          color: Color(0x0F0F1615),
          offset: Offset(0, 1),
          blurRadius: 2,
        ),
      ];

  /// Popover menus and the model quick-select sheet at rest.
  static List<BoxShadow> get lightMd => const [
        BoxShadow(
          color: Color(0x140F1615),
          offset: Offset(0, 4),
          blurRadius: 12,
        ),
      ];

  /// Modal bottom sheets and dialogs.
  static List<BoxShadow> get lightLg => const [
        BoxShadow(
          color: Color(0x240F1615),
          offset: Offset(0, 12),
          blurRadius: 32,
        ),
      ];

  static List<BoxShadow> get darkSm => const [
        BoxShadow(
          color: Color(0x99000000),
          offset: Offset(0, 1),
          blurRadius: 2,
        ),
      ];

  static List<BoxShadow> get darkMd => const [
        BoxShadow(
          color: Color(0x8C000000),
          offset: Offset(0, 6),
          blurRadius: 16,
        ),
      ];

  static List<BoxShadow> get darkLg => const [
        BoxShadow(
          color: Color(0xA6000000),
          offset: Offset(0, 16),
          blurRadius: 36,
        ),
      ];

  static List<BoxShadow> sm(Brightness brightness) =>
      brightness == Brightness.dark ? darkSm : lightSm;

  static List<BoxShadow> md(Brightness brightness) =>
      brightness == Brightness.dark ? darkMd : lightMd;

  static List<BoxShadow> lg(Brightness brightness) =>
      brightness == Brightness.dark ? darkLg : lightLg;
}

/// Typography tokens.
abstract final class HarnessType {
  /// Display / heading family.
  static const String sans = 'Geist';

  /// Commands, tool observations, JSON, and inline code.
  static const String mono = 'Geist Mono';

  /// 28px / 600 / 1.2. Empty-session welcome heading.
  static const TextStyle display = TextStyle(
    fontFamily: sans,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// 22px / 600 / 1.25. Screen titles.
  static const TextStyle h1 = TextStyle(
    fontFamily: sans,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  /// 18px / 600 / 1.3. Sheet titles and section headers.
  static const TextStyle h2 = TextStyle(
    fontFamily: sans,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// 15px / 600 / 1.35. List row titles and dialog headings.
  static const TextStyle h3 = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// 15px / 400 / 1.5. Chat messages, descriptions, input text.
  static const TextStyle body = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// 15px / 500 / 1.5. Button labels.
  static const TextStyle button = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  /// 13px / 400 / 1.45. Metadata, tool detail, sheet body copy.
  static const TextStyle bodySm = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// 12px / 500 / 1.3. Status pills, chips, timer strip, field labels.
  static const TextStyle label = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// 13px / 400 / 1.5. Commands, JSON observations, inline code.
  static const TextStyle code = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// 12px / 400 / 1.55. Monospace metadata such as paths and line numbers.
  static const TextStyle codeSm = TextStyle(
    fontFamily: mono,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  /// The Material text theme, with every step collapsed onto the brand scale.
  static TextTheme textTheme(HarnessColors colors) {
    final base = TextTheme(
      displayLarge: display,
      displayMedium: display,
      displaySmall: display,
      headlineLarge: display,
      headlineMedium: display,
      headlineSmall: display,
      titleLarge: h1,
      titleMedium: h2,
      titleSmall: h3,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: bodySm,
      labelLarge: label,
      labelMedium: label,
      labelSmall: label,
    );
    return base.apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    );
  }
}

/// A compact context extension for the brand palette.
extension HarnessColorsContext on BuildContext {
  /// The brand palette for the nearest theme.
  HarnessColors get harnessColors => HarnessColors.of(this);

  /// The brand palette's brightness.
  Brightness get harnessBrightness => Theme.of(this).brightness;
}
