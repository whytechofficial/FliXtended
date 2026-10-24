// ignore_for_file: unnecessary_const, prefer_const_constructors
import 'package:flixquest/models/app_colors.dart';
import 'package:flixquest/models/occasional_theme.dart';
import 'package:flutter/material.dart';

import 'loading_colors.dart';

ThemeData darkThemeData(
    bool isM3Enabled, ColorScheme? darkDynamicColor, AppColor color) {
  bool useUserColor = color.index != -1;
  final brandDefault = AppColor.flixtendedDefault(true);
  return ThemeData(
    useMaterial3: false,
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Figtree'),
    bottomSheetTheme:
        BottomSheetThemeData(backgroundColor: Colors.grey.shade900),
    appBarTheme: AppBarTheme(
      backgroundColor: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
      iconTheme: IconThemeData(
        color: isM3Enabled
            ? darkDynamicColor?.onPrimary ?? Colors.black
            : useUserColor
                ? color.cs.onPrimary
                : Colors.black,
      ),
      titleTextStyle: TextStyle(
          color: isM3Enabled
              ? darkDynamicColor?.onPrimary ?? Colors.black
              : useUserColor
                  ? color.cs.onPrimary
                  : Colors.black,
          fontFamily: 'FigtreeSB',
          fontSize: 21),
    ),
    dialogTheme: DialogThemeData(backgroundColor: Color(0xFF171717)),
    primaryColor: isM3Enabled
        ? darkDynamicColor?.primary ?? brandDefault.primary
        : useUserColor
            ? color.cs.primary
            : brandDefault.primary,
    iconTheme: IconThemeData(
      color: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
    ),
    bannerTheme: MaterialBannerThemeData(),
    chipTheme: ChipThemeData(),
    snackBarTheme: SnackBarThemeData(
        backgroundColor: isM3Enabled
            ? darkDynamicColor?.onSurface ?? brandDefault.onSurface
            : useUserColor
                ? color.cs.onSurface
                : brandDefault.onSurface,
        contentTextStyle: TextStyle(
            color: isM3Enabled
                ? darkDynamicColor?.surface ?? brandDefault.surface
                : useUserColor
                    ? color.cs.surface
                    : brandDefault.surface)),
    scaffoldBackgroundColor: Color(0xFF161716),
    radioTheme: RadioThemeData(
        fillColor: WidgetStatePropertyAll(isM3Enabled
            ? darkDynamicColor?.primary ?? brandDefault.primary
            : useUserColor
                ? color.cs.primary
                : brandDefault.primary)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(
          isM3Enabled
              ? darkDynamicColor?.primary ?? brandDefault.primary
              : useUserColor
                  ? color.cs.primary
                  : brandDefault.primary,
        ),
        foregroundColor: WidgetStatePropertyAll(
          isM3Enabled
              ? darkDynamicColor?.onPrimary ?? Colors.white
              : useUserColor
                  ? color.cs.onPrimary
                  : Colors.white,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(
            isM3Enabled
                ? darkDynamicColor?.primary.withValues(alpha: 0.1) ??
                    brandDefault.primary.withValues(alpha: 0.1)
                : useUserColor
                    ? color.cs.primary.withValues(alpha: 0.1)
                    : brandDefault.primary.withValues(alpha: 0.1),
          ),
          maximumSize: WidgetStateProperty.all(const Size(200, 60)),
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
              RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                  side: BorderSide(
                    color: isM3Enabled
                        ? darkDynamicColor?.primary ?? brandDefault.primary
                        : useUserColor
                            ? color.cs.primary
                            : brandDefault.primary,
                  )))),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      refreshBackgroundColor: isM3Enabled
          ? darkDynamicColor?.onPrimary ?? Colors.black
          : useUserColor
              ? color.cs.onPrimary
              : Colors.black,
      color: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
      selectionHandleColor: const Color(0xFFFFFFFF),
      selectionColor: Colors.white12,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: InputBorder.none,
      hintStyle: TextStyle(color: Colors.white24, fontFamily: 'Figtree'),
      focusedBorder: InputBorder.none,
      enabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle:
          const TextStyle(fontFamily: 'FigtreeSB', fontWeight: FontWeight.w600),
      unselectedLabelStyle:
          const TextStyle(fontFamily: 'FigtreeSB', fontWeight: FontWeight.w500),
      indicatorColor: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(
        isM3Enabled
            ? darkDynamicColor?.primary ?? brandDefault.primary
            : useUserColor
                ? color.cs.primary
                : brandDefault.primary,
      ),
      trackColor: WidgetStatePropertyAll(
        isM3Enabled
            ? darkDynamicColor?.primaryContainer ?? brandDefault.primaryContainer
            : useUserColor
                ? color.cs.primaryContainer
                : brandDefault.primaryContainer,
      ),
    ),
    colorScheme: isM3Enabled
        ? (darkDynamicColor ?? brandDefault)
        : useUserColor
            ? color.cs
            : brandDefault,
  );
}

ThemeData lightThemeData(
    bool isM3Enabled, ColorScheme? lightDynamicColor, AppColor color) {
  bool useUserColor = color.index != -1;
  final brandDefault = AppColor.flixtendedDefault(false);
  return ThemeData(
    useMaterial3: false,
    textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Figtree'),
    bottomSheetTheme:
        BottomSheetThemeData(backgroundColor: Colors.grey.shade400),
    appBarTheme: AppBarTheme(
      backgroundColor: isM3Enabled
          ? lightDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
      iconTheme: IconThemeData(
        color: isM3Enabled
            ? lightDynamicColor?.onPrimary ?? Colors.black
            : useUserColor
                ? color.cs.onPrimary
                : Colors.black,
      ),
      titleTextStyle: TextStyle(
          color: isM3Enabled
              ? lightDynamicColor?.onPrimary ?? Colors.black
              : useUserColor
                  ? color.cs.onPrimary
                  : Colors.black,
          fontFamily: 'FigtreeSB',
          fontSize: 21),
    ),
    dialogTheme: DialogThemeData(backgroundColor: Color(0xFFdedede)),
    primaryColor: isM3Enabled
        ? lightDynamicColor?.primary ?? brandDefault.primary
        : useUserColor
            ? color.cs.primary
            : brandDefault.primary,
    iconTheme: IconThemeData(
      color: isM3Enabled
          ? lightDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
    ),
    bannerTheme: MaterialBannerThemeData(),
    chipTheme: ChipThemeData(),
    snackBarTheme: SnackBarThemeData(
        backgroundColor: isM3Enabled
            ? lightDynamicColor?.onSurface ?? brandDefault.onSurface
            : useUserColor
                ? color.cs.onSurface
                : brandDefault.onSurface,
        contentTextStyle: TextStyle(
            color: isM3Enabled
                ? lightDynamicColor?.surface ?? brandDefault.surface
                : useUserColor
                    ? color.cs.surface
                    : brandDefault.surface)),
    scaffoldBackgroundColor: Color(0xFFf5f5f5),
    radioTheme: RadioThemeData(
        fillColor: WidgetStatePropertyAll(isM3Enabled
            ? lightDynamicColor?.primary ?? brandDefault.primary
            : useUserColor
                ? color.cs.primary
                : brandDefault.primary)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(
          isM3Enabled
              ? lightDynamicColor?.primary ?? brandDefault.primary
              : useUserColor
                  ? color.cs.primary
                  : brandDefault.primary,
        ),
        foregroundColor: WidgetStatePropertyAll(
          isM3Enabled
              ? lightDynamicColor?.onPrimary ?? Colors.white
              : useUserColor
                  ? color.cs.onPrimary
                  : Colors.white,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(
            isM3Enabled
                ? lightDynamicColor?.primary.withValues(alpha: 0.1) ??
                    brandDefault.primary.withValues(alpha: 0.1)
                : useUserColor
                    ? color.cs.primary.withValues(alpha: 0.1)
                    : brandDefault.primary.withValues(alpha: 0.1),
          ),
          maximumSize: WidgetStateProperty.all(const Size(200, 60)),
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
              RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                  side: BorderSide(
                    color: isM3Enabled
                        ? lightDynamicColor?.primary ?? brandDefault.primary
                        : useUserColor
                            ? color.cs.primary
                            : brandDefault.primary,
                  )))),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      refreshBackgroundColor: isM3Enabled
          ? lightDynamicColor?.onPrimary ?? Colors.black
          : useUserColor
              ? color.cs.onPrimary
              : Colors.black,
      color: isM3Enabled
          ? lightDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: isM3Enabled
          ? lightDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
      selectionHandleColor: const Color(0xFF000000),
      selectionColor: Colors.black12,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: InputBorder.none,
      hintStyle: TextStyle(color: Colors.black26, fontFamily: 'Figtree'),
      focusedBorder: InputBorder.none,
      enabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    ),
    tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(
            fontFamily: 'FigtreeSB', fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'FigtreeSB', fontWeight: FontWeight.w500),
        indicatorColor: isM3Enabled
            ? lightDynamicColor?.primary ?? brandDefault.primary
            : useUserColor
                ? color.cs.primary
                : brandDefault.primary),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(
        isM3Enabled
            ? lightDynamicColor?.primary ?? brandDefault.primary
            : useUserColor
                ? color.cs.primary
                : brandDefault.primary,
      ),
      trackColor: WidgetStatePropertyAll(
        isM3Enabled
            ? lightDynamicColor?.primaryContainer ?? brandDefault.primaryContainer
            : useUserColor
                ? color.cs.primaryContainer
                : brandDefault.primaryContainer,
      ),
    ),
    colorScheme: isM3Enabled
        ? (lightDynamicColor ?? brandDefault)
        : useUserColor
            ? color.cs
            : brandDefault,
  );
}

ThemeData lightsOutThemeData(
    bool isM3Enabled, ColorScheme? darkDynamicColor, AppColor color) {
  bool useUserColor = color.index != -1;
  final brandDefault = AppColor.flixtendedDefault(true);
  return ThemeData(
    useMaterial3: false,
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Figtree'),
    bottomSheetTheme:
        BottomSheetThemeData(backgroundColor: Colors.grey.shade900),
    appBarTheme: AppBarTheme(
      backgroundColor: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
      iconTheme: IconThemeData(
        color: isM3Enabled
            ? darkDynamicColor?.onPrimary ?? Colors.black
            : useUserColor
                ? color.cs.onPrimary
                : Colors.black,
      ),
      titleTextStyle: TextStyle(
          color: isM3Enabled
              ? darkDynamicColor?.onPrimary ?? Colors.black
              : useUserColor
                  ? color.cs.onPrimary
                  : Colors.black,
          fontFamily: 'FigtreeSB',
          fontSize: 21),
      // shape: ContinuousRectangleBorder(
      //   borderRadius: BorderRadius.only(
      //     bottomLeft: Radius.circular(20.0),
      //     bottomRight: Radius.circular(20.0),
      //   ),
      // ),
    ),
    dialogTheme: DialogThemeData(backgroundColor: Color(0xFF171717)),
    primaryColor: isM3Enabled
        ? darkDynamicColor?.primary ?? brandDefault.primary
        : useUserColor
            ? color.cs.primary
            : brandDefault.primary,
    iconTheme: IconThemeData(
      color: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
    ),
    bannerTheme: MaterialBannerThemeData(),
    chipTheme: ChipThemeData(),
    snackBarTheme: SnackBarThemeData(
        backgroundColor: isM3Enabled
            ? darkDynamicColor?.onSurface ?? brandDefault.onSurface
            : useUserColor
                ? color.cs.onSurface
                : brandDefault.onSurface,
        contentTextStyle: TextStyle(
          color: isM3Enabled
              ? darkDynamicColor?.surface ?? brandDefault.surface
              : useUserColor
                  ? color.cs.surface
                  : brandDefault.surface,
        )),
    scaffoldBackgroundColor: Colors.black,
    radioTheme: RadioThemeData(
        fillColor: WidgetStatePropertyAll(isM3Enabled
            ? darkDynamicColor?.primary ?? brandDefault.primary
            : useUserColor
                ? color.cs.primary
                : brandDefault.primary)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(
          isM3Enabled
              ? darkDynamicColor?.primary ?? brandDefault.primary
              : useUserColor
                  ? color.cs.primary
                  : brandDefault.primary,
        ),
        foregroundColor: WidgetStatePropertyAll(
          isM3Enabled
              ? darkDynamicColor?.onPrimary ?? Colors.white
              : useUserColor
                  ? color.cs.onPrimary
                  : Colors.white,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(
            isM3Enabled
                ? darkDynamicColor?.primary.withValues(alpha: 0.1) ??
                    brandDefault.primary.withValues(alpha: 0.1)
                : useUserColor
                    ? color.cs.primary.withValues(alpha: 0.1)
                    : brandDefault.primary.withValues(alpha: 0.1),
          ),
          maximumSize: WidgetStateProperty.all(const Size(200, 60)),
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
              RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                  side: BorderSide(
                    color: isM3Enabled
                        ? darkDynamicColor?.primary ?? brandDefault.primary
                        : useUserColor
                            ? color.cs.primary
                            : brandDefault.primary,
                  )))),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      refreshBackgroundColor: isM3Enabled
          ? darkDynamicColor?.onPrimary ?? Colors.black
          : Colors.black,
      color: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
      selectionHandleColor: const Color(0xFFFFFFFF),
      selectionColor: Colors.white12,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: InputBorder.none,
      hintStyle: TextStyle(color: Colors.white24, fontFamily: 'Figtree'),
      focusedBorder: InputBorder.none,
      enabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle:
          const TextStyle(fontFamily: 'FigtreeSB', fontWeight: FontWeight.w600),
      unselectedLabelStyle:
          const TextStyle(fontFamily: 'FigtreeSB', fontWeight: FontWeight.w500),
      indicatorColor: isM3Enabled
          ? darkDynamicColor?.primary ?? brandDefault.primary
          : useUserColor
              ? color.cs.primary
              : brandDefault.primary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(
        isM3Enabled
            ? darkDynamicColor?.primary ?? brandDefault.primary
            : useUserColor
                ? color.cs.primary
                : brandDefault.primary,
      ),
      trackColor: WidgetStatePropertyAll(
        isM3Enabled
            ? darkDynamicColor?.primaryContainer ?? brandDefault.primaryContainer
            : useUserColor
                ? color.cs.primaryContainer
                : brandDefault.primaryContainer,
      ),
    ),
    colorScheme: isM3Enabled
        ? (darkDynamicColor ?? brandDefault)
        : useUserColor
            ? color.cs
            : brandDefault,
  );
}

class Styles {
  static ThemeData themeData(
      {required String appThemeMode,
      required bool isM3Enabled,
      required ColorScheme? lightDynamicColor,
      required ColorScheme? darkDynamicColor,
      required BuildContext context,
      required AppColor appColor,
      bool compactCorners = false,
      OccasionalTheme? occasionalTheme,
      Color? ambientColor}) {
    var baseTheme = appThemeMode == 'dark'
        ? darkThemeData(isM3Enabled, darkDynamicColor, appColor)
        : appThemeMode == 'light'
            ? lightThemeData(isM3Enabled, lightDynamicColor, appColor)
            : appThemeMode == 'amoled'
                ? lightsOutThemeData(isM3Enabled, darkDynamicColor, appColor)
                : darkThemeData(isM3Enabled, darkDynamicColor, appColor);
    final activeTheme =
        occasionalTheme?.isActive == true ? occasionalTheme : null;
    if (activeTheme != null) {
      baseTheme = _applyOccasionalColors(baseTheme, activeTheme);
    } else if (ambientColor != null) {
      baseTheme = _applyAmbientColor(baseTheme, ambientColor);
    }
    final themed = _applyFlixQuestUI(
      baseTheme,
      compactCorners: compactCorners,
      surfaceOverride:
          activeTheme?.backgroundFor(baseTheme.colorScheme.brightness) ??
              (ambientColor == null ? null : baseTheme.colorScheme.surface),
    );
    return themed.copyWith(
      extensions: [
        ...themed.extensions.values,
        AppLoadingColors.forThemeMode(appThemeMode),
      ],
    );
  }
}

ThemeData _applyAmbientColor(ThemeData base, Color seedColor) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: base.colorScheme.brightness,
  );
  return base.copyWith(
    colorScheme: scheme,
    primaryColor: scheme.primary,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
  );
}

ThemeData _applyOccasionalColors(ThemeData base, OccasionalTheme theme) {
  final brightness = base.colorScheme.brightness;
  final generated = ColorScheme.fromSeed(
    seedColor: theme.primaryColor,
    brightness: brightness,
  );
  final secondary = ColorScheme.fromSeed(
    seedColor: theme.secondaryColor,
    brightness: brightness,
  );
  final tertiary = ColorScheme.fromSeed(
    seedColor: theme.tertiaryColor,
    brightness: brightness,
  );
  final background = theme.backgroundFor(brightness);
  final scheme = generated.copyWith(
    primary: theme.primaryColor,
    onPrimary: _readableOn(theme.primaryColor),
    secondary: theme.secondaryColor,
    onSecondary: _readableOn(theme.secondaryColor),
    secondaryContainer: secondary.primaryContainer,
    onSecondaryContainer: secondary.onPrimaryContainer,
    tertiary: theme.tertiaryColor,
    onTertiary: _readableOn(theme.tertiaryColor),
    tertiaryContainer: tertiary.primaryContainer,
    onTertiaryContainer: tertiary.onPrimaryContainer,
    surface: background ?? generated.surface,
    onSurface:
        background == null ? generated.onSurface : _readableOn(background),
  );
  return base.copyWith(
    colorScheme: scheme,
    primaryColor: theme.primaryColor,
    scaffoldBackgroundColor: background ?? base.scaffoldBackgroundColor,
    canvasColor: background ?? base.canvasColor,
  );
}

Color _readableOn(Color color) =>
    ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xDE000000);

ThemeData _applyFlixQuestUI(
  ThemeData base, {
  Color? surfaceOverride,
  bool compactCorners = false,
}) {
  double corner(double handheld, double television) =>
      compactCorners ? handheld : television;
  final colors = base.colorScheme;
  final dark = colors.brightness == Brightness.dark;
  final surface = surfaceOverride ??
      (dark
          ? (base.scaffoldBackgroundColor == Colors.black
              ? Colors.black
              : const Color(0xFF111315))
          : const Color(0xFFFCFCFD));
  final softSurface = surfaceOverride == null
      ? (dark ? const Color(0xFF1D2023) : const Color(0xFFF3F3F5))
      : Color.alphaBlend(
          colors.onSurface.withValues(alpha: dark ? .08 : .055),
          surface,
        );
  final outline = colors.onSurface.withValues(alpha: .12);
  final primaryIsDark =
      ThemeData.estimateBrightnessForColor(colors.primary) == Brightness.dark;
  final solidButtonForeground =
      primaryIsDark ? Colors.white : Colors.black.withValues(alpha: .88);
  final actionButtonForeground =
      !dark && colors.primary.computeLuminance() > .45
          ? Color.alphaBlend(
              Colors.black.withValues(alpha: .38),
              colors.primary,
            )
          : colors.primary;
  final roundedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(corner(8, 15)),
    borderSide: BorderSide.none,
  );
  Color accentFor(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return colors.onSurface.withValues(alpha: .32);
    }
    return actionButtonForeground;
  }

  // Controls are drawn in ink (the page's text colour) rather than the
  // accent: white in the dark modes, near-black in Light, the way Netflix's
  // Play button is. The accent is kept for progress, selection marks, the
  // text cursor and the brand itself (docs/mobile_redesign_guide.md, 3.2).
  final ink = dark ? const Color(0xFFF7F7F7) : const Color(0xFF141516);
  final onInk = dark ? Colors.black : Colors.white;
  Color inkFor(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return colors.onSurface.withValues(alpha: .32);
    }
    return ink;
  }

  Color selectedFillFor(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return colors.onSurface.withValues(alpha: .12);
    }
    return states.contains(WidgetState.selected)
        ? colors.primary
        : Colors.transparent;
  }

  return base.copyWith(
    colorScheme: colors.copyWith(onPrimary: solidButtonForeground),
    splashColor: ink.withValues(alpha: .08),
    highlightColor: ink.withValues(alpha: .04),
    hoverColor: ink.withValues(alpha: .035),
    scaffoldBackgroundColor: surface,
    canvasColor: surface,
    iconTheme: IconThemeData(color: ink, size: 24),
    primaryIconTheme: IconThemeData(color: solidButtonForeground, size: 24),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(inkFor),
        overlayColor: WidgetStatePropertyAll(ink.withValues(alpha: .10)),
      ),
    ),
    textTheme: base.textTheme.apply(fontFamily: 'Figtree').copyWith(
          headlineLarge: base.textTheme.headlineLarge
              ?.copyWith(fontFamily: 'FigtreeSB', fontWeight: FontWeight.w700),
          headlineMedium: base.textTheme.headlineMedium
              ?.copyWith(fontFamily: 'FigtreeSB', fontWeight: FontWeight.w700),
          headlineSmall: base.textTheme.headlineSmall
              ?.copyWith(fontFamily: 'FigtreeSB', fontWeight: FontWeight.w700),
          titleLarge: base.textTheme.titleLarge
              ?.copyWith(fontFamily: 'FigtreeSB', fontWeight: FontWeight.w700),
          titleMedium: base.textTheme.titleMedium
              ?.copyWith(fontFamily: 'FigtreeSB', fontWeight: FontWeight.w600),
        ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: colors.onSurface, size: 24),
      titleTextStyle: TextStyle(
        color: colors.onSurface,
        fontFamily: 'FigtreeSB',
        fontWeight: FontWeight.w700,
        fontSize: 23,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: softSurface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(corner(8, 16))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: softSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: roundedBorder,
      enabledBorder: roundedBorder,
      focusedBorder: roundedBorder.copyWith(
        borderSide: BorderSide(color: ink.withValues(alpha: .6), width: 1.5),
      ),
      errorBorder: roundedBorder.copyWith(
        borderSide: BorderSide(color: colors.error),
      ),
      prefixIconColor: colors.onSurfaceVariant,
      suffixIconColor: colors.onSurfaceVariant,
      hintStyle:
          TextStyle(color: colors.onSurfaceVariant.withValues(alpha: .65)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: ink,
        foregroundColor: onInk,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(corner(7, 14))),
        textStyle: const TextStyle(fontFamily: 'FigtreeSB'),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: onInk,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(corner(7, 14))),
        textStyle: const TextStyle(fontFamily: 'FigtreeSB'),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        side: BorderSide(color: ink.withValues(alpha: .24), width: 1.4),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(corner(7, 14))),
        textStyle: const TextStyle(fontFamily: 'FigtreeSB'),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(corner(6, 12))),
        textStyle: const TextStyle(fontFamily: 'FigtreeSB'),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      focusElevation: 4,
      hoverElevation: 4,
      backgroundColor: softSurface,
      foregroundColor: ink,
      focusColor: ink.withValues(alpha: .16),
      hoverColor: ink.withValues(alpha: .12),
      splashColor: ink.withValues(alpha: .14),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(selectedFillFor),
      checkColor: WidgetStatePropertyAll(solidButtonForeground),
      overlayColor: WidgetStatePropertyAll(
        colors.primary.withValues(alpha: .10),
      ),
      side: BorderSide(color: colors.onSurfaceVariant, width: 1.6),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(accentFor),
      overlayColor: WidgetStatePropertyAll(
        colors.primary.withValues(alpha: .10),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.primary.withValues(alpha: .14),
      circularTrackColor: colors.primary.withValues(alpha: .14),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: colors.primary,
      inactiveTrackColor: colors.primary.withValues(alpha: .18),
      secondaryActiveTrackColor: colors.primary.withValues(alpha: .45),
      thumbColor: colors.primary,
      overlayColor: colors.primary.withValues(alpha: .12),
      valueIndicatorColor: colors.primary,
      valueIndicatorTextStyle: TextStyle(
        color: solidButtonForeground,
        fontFamily: 'FigtreeSB',
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.primary,
      selectionColor: colors.primary.withValues(alpha: .28),
      selectionHandleColor: colors.primary,
    ),
    toggleButtonsTheme: ToggleButtonsThemeData(
      color: colors.onSurfaceVariant,
      selectedColor: onInk,
      fillColor: ink,
      focusColor: ink.withValues(alpha: .10),
      hoverColor: ink.withValues(alpha: .08),
      splashColor: ink.withValues(alpha: .10),
      borderColor: colors.outline,
      selectedBorderColor: ink,
      borderRadius: BorderRadius.circular(corner(7, 12)),
    ),
    // Selected chips fill with the brand accent (lavender) and invert their
    // label; the rest sit on a faint ink wash with no outline.
    chipTheme: base.chipTheme.copyWith(
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return ink.withValues(alpha: .04);
        }
        return states.contains(WidgetState.selected)
            ? colors.primary
            : ink.withValues(alpha: .08);
      }),
      backgroundColor: ink.withValues(alpha: .08),
      selectedColor: colors.primary,
      secondarySelectedColor: colors.primary,
      checkmarkColor: colors.onPrimary,
      labelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? colors.onPrimary
              : ink,
          fontFamily: 'FigtreeSB',
        ),
      ),
      secondaryLabelStyle:
          TextStyle(color: colors.onPrimary, fontFamily: 'FigtreeSB'),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(corner(8, 22))),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.onSurface.withValues(alpha: .28);
        }
        return states.contains(WidgetState.selected)
            ? solidButtonForeground
            : colors.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.onSurface.withValues(alpha: .10);
        }
        return states.contains(WidgetState.selected)
            ? colors.primary
            : colors.onSurface.withValues(alpha: dark ? .22 : .16);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.transparent
            : colors.outline.withValues(alpha: .7);
      }),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorColor: ink,
      labelColor: ink,
      unselectedLabelColor: colors.onSurfaceVariant,
      labelStyle: const TextStyle(
          fontFamily: 'FigtreeSB', fontWeight: FontWeight.w600, fontSize: 15),
      unselectedLabelStyle: const TextStyle(
          fontFamily: 'FigtreeSB', fontWeight: FontWeight.w500, fontSize: 15),
      indicatorSize: TabBarIndicatorSize.label,
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: surface,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
            fontFamily:
                states.contains(WidgetState.selected) ? 'FigtreeSB' : 'Figtree',
            fontSize: 11,
          )),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      // A neutral handle rather than Material's accent-tinted one.
      dragHandleColor: ink.withValues(alpha: .28),
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(corner(12, 28))),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: colors.primary,
      unselectedItemColor: colors.onSurfaceVariant,
      selectedIconTheme: IconThemeData(color: colors.primary),
      unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
      selectedLabelStyle: const TextStyle(fontFamily: 'FigtreeSB'),
      unselectedLabelStyle: const TextStyle(fontFamily: 'Figtree'),
      elevation: 0,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: ink.withValues(alpha: .10),
      selectedIconTheme: IconThemeData(color: ink),
      unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: ink,
        fontFamily: 'FigtreeSB',
      ),
      unselectedLabelTextStyle: TextStyle(
        color: colors.onSurfaceVariant,
        fontFamily: 'Figtree',
      ),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: colors.secondary,
      textColor: colors.onSecondary,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: ink,
      collapsedIconColor: colors.onSurfaceVariant,
      textColor: colors.onSurface,
      collapsedTextColor: colors.onSurface,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(corner(10, 22))),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colors.onSurface,
        fontFamily: 'FigtreeSB',
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
        height: 1.45,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFF2F3F4) : const Color(0xFF1D2023),
      contentTextStyle: TextStyle(
        color: dark ? const Color(0xFF17191B) : Colors.white,
        fontFamily: 'FigtreeSB',
      ),
      // The snack bar is inverted (light on dark pages), so its action is
      // the page colour's ink, in bold.
      actionTextColor: dark ? const Color(0xFF17191B) : Colors.white,
      closeIconColor: dark ? const Color(0xFF17191B) : Colors.white,
      showCloseIcon: true,
      elevation: 8,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(corner(8, 16))),
    ),
    dividerTheme: DividerThemeData(color: outline, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: colors.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(corner(8, 14))),
    ),
  );
}
