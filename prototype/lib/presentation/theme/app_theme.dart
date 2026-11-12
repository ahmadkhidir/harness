import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'harness_colors.dart';
import 'harness_tokens.dart';

/// Builds the Harness [ThemeData] for a given [brightness].
///
/// The theme is the single source of truth for brand color, type, shape,
/// spacing-derived density, and component tokens. Screens read semantic roles
/// from [HarnessColors] instead of raw values, so light and dark invert with a
/// single palette swap.
ThemeData buildHarnessTheme({required Brightness brightness}) {
  final colors = brightness == Brightness.dark
      ? HarnessColors.dark
      : HarnessColors.light;
  final isDark = brightness == Brightness.dark;
  final scheme = _colorScheme(colors, brightness);
  final textTheme = HarnessType.textTheme(colors);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: colors.surface,
    canvasColor: colors.surface,
    cardColor: colors.surface,
    dividerColor: colors.border,
    disabledColor: colors.textSecondary.withValues(alpha: 0.4),
    focusColor: colors.primary.c500.withValues(alpha: 0.12),
    hoverColor: colors.primary.c500.withValues(alpha: 0.06),
    splashColor: colors.primary.c500.withValues(alpha: 0.08),
    highlightColor: colors.primary.c500.withValues(alpha: 0.06),
    splashFactory: InkRipple.splashFactory,
    applyElevationOverlayColor: false,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: <ThemeExtension<dynamic>>[colors],
    appBarTheme: _appBarTheme(colors, textTheme, isDark),
    inputDecorationTheme: _inputTheme(colors, textTheme),
    filledButtonTheme: FilledButtonThemeData(
      style: _filledButtonStyle(colors, textTheme, isDark),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _outlinedButtonStyle(colors, textTheme, isDark),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _textButtonStyle(colors, textTheme),
    ),
    iconButtonTheme: IconButtonThemeData(style: _iconButtonStyle(colors)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primary.c600,
      foregroundColor: colors.primary.c100,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: HarnessRadius.mdAll,
      ),
      extendedTextStyle: HarnessType.button,
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: HarnessRadius.mdAll,
        side: BorderSide(color: colors.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: HarnessRadius.lgAll,
        side: BorderSide(color: colors.border),
      ),
      titleTextStyle: textTheme.titleSmall,
      contentTextStyle: textTheme.bodySmall?.copyWith(
        color: colors.textSecondary,
      ),
      barrierColor: const Color(0x99000000),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: colors.borderStrong,
      dragHandleSize: const Size(36, 4),
      shape: RoundedRectangleBorder(
        borderRadius: HarnessRadius.sheetTop,
        side: BorderSide(color: colors.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? colors.neutral.c300 : colors.neutral.c900,
      contentTextStyle: textTheme.bodySmall?.copyWith(
        color: isDark ? colors.neutral.c900 : colors.neutral.c100,
      ),
      actionTextColor: isDark ? colors.primary.c700 : colors.primary.c300,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.all(HarnessSpace.lg),
      shape: const RoundedRectangleBorder(
        borderRadius: HarnessRadius.smAll,
      ),
    ),
    chipTheme: _chipTheme(colors, textTheme),
    tabBarTheme: TabBarThemeData(
      labelColor: colors.primary.c500,
      unselectedLabelColor: colors.textSecondary,
      labelStyle: HarnessType.label,
      unselectedLabelStyle: HarnessType.label,
      indicatorColor: colors.primary.c500,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: colors.border,
      overlayColor: WidgetStatePropertyAll(
        colors.primary.c500.withValues(alpha: 0.08),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: HarnessRadius.smAll,
        border: Border.all(color: colors.border),
      ),
      textStyle: HarnessType.bodySm.copyWith(color: colors.textPrimary),
      waitDuration: const Duration(milliseconds: 400),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary.c500,
      linearTrackColor: colors.border,
      circularTrackColor: colors.border,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.primary.c500,
      inactiveTrackColor: colors.border,
      thumbColor: colors.primary.c600,
      overlayColor: colors.primary.c500.withValues(alpha: 0.12),
      valueIndicatorColor: colors.primary.c600,
      valueIndicatorTextStyle: HarnessType.label.copyWith(
        color: colors.primary.c100,
      ),
      trackHeight: 2,
    ),
    dividerTheme: DividerThemeData(
      color: colors.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: colors.textSecondary, size: HarnessSize.iconMd),
    primaryIconTheme: IconThemeData(color: colors.textPrimary),
    listTileTheme: ListTileThemeData(
      iconColor: colors.textSecondary,
      textColor: colors.textPrimary,
      titleTextStyle: textTheme.titleSmall,
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: colors.textSecondary,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: HarnessSpace.lg,
        vertical: HarnessSpace.xs,
      ),
      minVerticalPadding: HarnessSpace.sm,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.primary.c500,
      selectionColor: colors.primary.c500.withValues(alpha: 0.28),
      selectionHandleColor: colors.primary.c500,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primary.c100;
        }
        return colors.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primary.c600;
        }
        return colors.surfaceSecondary;
      }),
      trackOutlineColor: WidgetStatePropertyAll(colors.borderStrong),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primary.c600;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(colors.primary.c100),
      side: BorderSide(color: colors.borderStrong, width: 1.5),
      shape: const RoundedRectangleBorder(
        borderRadius: HarnessRadius.xsAll,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primary.c600;
        }
        return colors.borderStrong;
      }),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: HarnessRadius.smAll,
        side: BorderSide(color: colors.border),
      ),
      textStyle: textTheme.bodyMedium,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.primary.c100,
      labelTextStyle: WidgetStatePropertyAll(HarnessType.label),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: colors.primary.c500, size: HarnessSize.iconMd);
        }
        return IconThemeData(color: colors.textSecondary, size: HarnessSize.iconMd);
      }),
    ),
  );
}

/// Maps brand roles onto the Material [ColorScheme].
ColorScheme _colorScheme(HarnessColors colors, Brightness brightness) {
  return ColorScheme(
    brightness: brightness,
    primary: colors.primary.c600,
    onPrimary: colors.primary.c100,
    primaryContainer: colors.primary.c100,
    onPrimaryContainer: colors.primary.c900,
    secondary: colors.primary.c700,
    onSecondary: colors.primary.c100,
    secondaryContainer: colors.primary.c100,
    onSecondaryContainer: colors.primary.c700,
    tertiary: colors.warning.c500,
    onTertiary: colors.warning.c100,
    tertiaryContainer: colors.warning.c100,
    onTertiaryContainer: colors.warning.c900,
    error: colors.error.c500,
    onError: colors.error.c100,
    errorContainer: colors.error.c100,
    onErrorContainer: colors.error.c900,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    surfaceContainerLowest: colors.surface,
    surfaceContainerLow: colors.surface,
    surfaceContainer: colors.surfaceSecondary,
    surfaceContainerHigh: colors.surfaceSecondary,
    surfaceContainerHighest: colors.surfaceSecondary,
    outline: colors.borderStrong,
    outlineVariant: colors.border,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: colors.neutral.c900,
    onInverseSurface: colors.neutral.c100,
    inversePrimary: colors.primary.c300,
    surfaceTint: Colors.transparent,
  );
}

AppBarThemeData _appBarTheme(
  HarnessColors colors,
  TextTheme textTheme,
  bool isDark,
) {
  return AppBarThemeData(
    backgroundColor: colors.surface,
    foregroundColor: colors.textPrimary,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    toolbarHeight: HarnessSize.appBar,
    titleSpacing: HarnessSpace.lg,
    titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.textPrimary),
    iconTheme: IconThemeData(
      color: colors.textSecondary,
      size: HarnessSize.iconMd,
    ),
    actionsIconTheme: IconThemeData(
      color: colors.textSecondary,
      size: HarnessSize.iconMd,
    ),
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: colors.surface,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: colors.border,
    ),
  );
}

InputDecorationThemeData _inputTheme(
  HarnessColors colors,
  TextTheme textTheme,
) {
  final border = OutlineInputBorder(
    borderRadius: HarnessRadius.smAll,
    borderSide: BorderSide(color: colors.borderStrong),
  );
  return InputDecorationThemeData(
    filled: true,
    fillColor: colors.surfaceSecondary,
    isDense: false,
    constraints: const BoxConstraints(minHeight: HarnessSize.input),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: HarnessSpace.md,
      vertical: HarnessSpace.md,
    ),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: HarnessRadius.smAll,
      borderSide: BorderSide(color: colors.primary.c500, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: HarnessRadius.smAll,
      borderSide: BorderSide(color: colors.error.c500, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: HarnessRadius.smAll,
      borderSide: BorderSide(color: colors.error.c500, width: 2),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: HarnessRadius.smAll,
      borderSide: BorderSide(color: colors.border),
    ),
    hintStyle: textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary.withValues(alpha: 0.72),
    ),
    labelStyle: HarnessType.label.copyWith(color: colors.textSecondary),
    floatingLabelStyle: HarnessType.label.copyWith(color: colors.primary.c500),
    helperStyle: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
    helperMaxLines: 3,
    errorStyle: textTheme.bodySmall?.copyWith(color: colors.error.c700),
    errorMaxLines: 3,
    prefixIconColor: colors.textSecondary,
    suffixIconColor: colors.textSecondary,
    iconColor: colors.textSecondary,
  );
}

ButtonStyle _filledButtonStyle(
  HarnessColors colors,
  TextTheme textTheme,
  bool isDark,
) {
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, HarnessSize.button)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: HarnessSpace.lg,
        vertical: HarnessSpace.md,
      ),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: HarnessRadius.smAll),
    ),
    textStyle: WidgetStatePropertyAll(HarnessType.button),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.primary.c100.withValues(alpha: 0.4);
      }
      if (states.contains(WidgetState.pressed)) return colors.primary.c700;
      if (states.contains(WidgetState.hovered)) return colors.primary.c700;
      return colors.primary.c600;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return colors.textSecondary;
      return colors.primary.c100;
    }),
    overlayColor: WidgetStatePropertyAll(
      colors.primary.c100.withValues(alpha: 0.12),
    ),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: colors.primary.c500, width: 2);
      }
      return BorderSide.none;
    }),
    elevation: const WidgetStatePropertyAll(0),
  );
}

ButtonStyle _outlinedButtonStyle(
  HarnessColors colors,
  TextTheme textTheme,
  bool isDark,
) {
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, HarnessSize.button)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: HarnessSpace.lg,
        vertical: HarnessSpace.md,
      ),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: HarnessRadius.smAll),
    ),
    textStyle: WidgetStatePropertyAll(HarnessType.button),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered)) {
        return colors.primary.c100.withValues(alpha: 0.5);
      }
      return Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.textSecondary.withValues(alpha: 0.4);
      }
      return colors.primary.c500;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: colors.primary.c500, width: 2);
      }
      return BorderSide(color: colors.primary.c500, width: 1.5);
    }),
    elevation: const WidgetStatePropertyAll(0),
  );
}

ButtonStyle _textButtonStyle(HarnessColors colors, TextTheme textTheme) {
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, HarnessSize.touchTarget)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: HarnessSpace.md,
        vertical: HarnessSpace.sm,
      ),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: HarnessRadius.smAll),
    ),
    textStyle: WidgetStatePropertyAll(HarnessType.button),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered)) {
        return colors.surfaceSecondary;
      }
      return Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.textSecondary.withValues(alpha: 0.4);
      }
      return colors.textSecondary;
    }),
    overlayColor: WidgetStatePropertyAll(
      colors.primary.c500.withValues(alpha: 0.08),
    ),
  );
}

ButtonStyle _iconButtonStyle(HarnessColors colors) {
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(
      Size(HarnessSize.touchTarget, HarnessSize.touchTarget),
    ),
    iconSize: const WidgetStatePropertyAll(HarnessSize.iconMd),
    foregroundColor: WidgetStatePropertyAll(colors.textSecondary),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: HarnessRadius.smAll),
    ),
    overlayColor: WidgetStatePropertyAll(
      colors.primary.c500.withValues(alpha: 0.08),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(HarnessSpace.sm)),
  );
}

ChipThemeData _chipTheme(HarnessColors colors, TextTheme textTheme) {
  return ChipThemeData(
    backgroundColor: colors.surfaceSecondary,
    selectedColor: colors.primary.c100,
    secondarySelectedColor: colors.primary.c100,
    disabledColor: colors.surfaceSecondary.withValues(alpha: 0.4),
    labelStyle: HarnessType.label.copyWith(color: colors.textSecondary),
    secondaryLabelStyle: HarnessType.label.copyWith(color: colors.primary.c900),
    labelPadding: const EdgeInsets.symmetric(horizontal: HarnessSpace.sm),
    padding: const EdgeInsets.symmetric(
      horizontal: HarnessSpace.sm,
      vertical: HarnessSpace.xs,
    ),
    side: BorderSide(color: colors.border),
    shape: const RoundedRectangleBorder(
      borderRadius: HarnessRadius.smAll,
    ),
    showCheckmark: false,
    elevation: 0,
    pressElevation: 0,
    brightness: colors == HarnessColors.dark
        ? Brightness.dark
        : Brightness.light,
  );
}
