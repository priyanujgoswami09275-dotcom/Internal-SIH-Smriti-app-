/// Monad design-system tokens for Flutter — mirrors DESIGN.md exactly.
///
/// Font substitutes (deliberate, offline-first — see note below):
/// - Serif: bundled `Newsreader` — DESIGN.md lists "Times New Roman, Georgia,
///   or any editorial serif with similar stroke contrast" as the substitute
///   for Untitled Serif. Newsreader is that Georgia-adjacent editorial serif,
///   bundled as TTF so games/reminders render with no network (NER
///   offline-first requirement). google_fonts PT Serif was rejected because it
///   needs a network fetch on first run.
/// - Mono: bundled `JetBrainsMono` — DESIGN.md's own first-listed substitute
///   for ABC Diatype Mono (alongside IBM Plex Mono / Space Mono alternates).
///   Bundled TTF, no google_fonts dependency, works offline.
///
/// Lake Blue discrepancy (flagged per brief): DESIGN.md's color table says
/// "Violet wash … Do not promote it to the primary CTA color", but the intro,
/// every button component spec, and the Do's/Don'ts all define Lake Blue as
/// the single primary-action fill. This file follows the component specs +
/// Do's/Don'ts as source of truth: Lake Blue IS the one primary CTA color.
library;

import 'package:flutter/material.dart';

class Monad {
  Monad._();

  // ===== Colors (DESIGN.md Tokens — Colors, exact hex, no substitutions) =====
  static const Color parchment = Color(0xFFF6F3F1);
  static const Color lakeBlue = Color(0xFF2B59D1);
  static const Color periwinkleMist = Color(0xFFCFDAF5);
  static const Color skyBlue = Color(0xFFA0B5EB);
  static const Color mint = Color(0xFFA7FCCD);
  static const Color coral = Color(0xFFFF9473);
  static const Color gold = Color(0xFFECDA98);
  static const Color crimson = Color(0xFFA23B00);
  static const Color offBlack = Color(0xFF242424);
  static const Color ink = Color(0xFF000000);
  static const Color graphite = Color(0xFF4E4D4D);
  static const Color smoke = Color(0xFF5C5A59);
  static const Color ash = Color(0xFFCECAC8);
  static const Color white = Color(0xFFFFFFFF);

  // ===== NE India palette (pre-existing; decorative-only, never UI fills) =====
  static const Color teaGreen = Color(0xFF2D5A27);
  static const Color eriGold = Color(0xFFC9A227);
  static const Color terracotta = Color(0xFFC0704A);
  static const Color indigo = Color(0xFF3D2B7A);

  // ===== Font families (bundled TTF, see header note) =====
  static const String serifFamily = 'Newsreader'; // Untitled Serif substitute
  static const String monoFamily =
      'JetBrainsMono'; // ABC Diatype Mono substitute

  // ===== Spacing (8px base unit, named constants) =====
  static const double spacing8 = 8;
  static const double spacing16 = 16;
  static const double spacing24 = 24;
  static const double spacing32 = 32;
  static const double spacing40 = 40;
  static const double spacing64 = 64;
  static const double spacing72 = 72;
  static const double spacing80 = 80;
  static const double spacing200 = 200;
  static const double spacing216 = 216;

  // Backwards-compatible aliases used across existing screens.
  static const double space8 = spacing8;
  static const double space16 = spacing16;
  static const double space24 = spacing24;
  static const double space32 = spacing32;
  static const double space40 = spacing40;
  static const double space64 = spacing64;

  // ===== Radii =====
  static const double radiusButton = 100; // pill buttons
  static const double radiusCard = 40; // cards
  static const double radiusPill = 9999; // tags / pills
  static const double radiusTag = 9999; // stadium — use StadiumBorder()
  static const double radiusMin = 16; // smallest allowed card radius

  // Aliases.
  static const double cardRadius = radiusCard;
  static const double buttonRadius = radiusButton;
  static const double tagRadius = radiusTag;

  // ===== Layout =====
  static const double pageMaxWidth = 1432;
  static const double sectionGap = spacing64;
  static const double cardPadding = 40;
  static const double elementGap = 16;

  // ===== Type scale — exact px/weight/tracking, serif 24px+ only =====
  // Mono 12–20px (all body/UI text). Serif 24px+ (headings only, w400 never 500+).
  static const TextStyle monoCaption = TextStyle(
      fontFamily: monoFamily,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: -0.4,
      color: smoke);
  static const TextStyle monoBodySm = TextStyle(
      fontFamily: monoFamily,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.35,
      letterSpacing: -0.28,
      color: graphite);
  static const TextStyle monoBody = TextStyle(
      fontFamily: monoFamily,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.35,
      letterSpacing: -0.4,
      color: graphite);
  static const TextStyle monoLabel = TextStyle(
      fontFamily: monoFamily,
      fontSize: 18,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: -0.4,
      color: offBlack);
  static const TextStyle monoBodyLg = TextStyle(
      fontFamily: monoFamily,
      fontSize: 20,
      fontWeight: FontWeight.w400,
      height: 1.35,
      letterSpacing: -0.4,
      color: graphite);

  /// Weight 500 is permitted ONLY on mono for emphasized UI labels.
  static const TextStyle monoEmphasis = TextStyle(
      fontFamily: monoFamily,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.35,
      letterSpacing: -0.4,
      color: offBlack);

  static const TextStyle subheading = TextStyle(
      fontFamily: serifFamily,
      fontSize: 24,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: -0.48,
      color: offBlack);
  static const TextStyle headingSm = TextStyle(
      fontFamily: serifFamily,
      fontSize: 32,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: -0.64,
      color: offBlack);
  static const TextStyle heading = TextStyle(
      fontFamily: serifFamily,
      fontSize: 40,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: -0.8,
      color: offBlack);
  static const TextStyle headingLg = TextStyle(
      fontFamily: serifFamily,
      fontSize: 48,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: -0.96,
      color: offBlack);
  static const TextStyle display = TextStyle(
      fontFamily: serifFamily,
      fontSize: 80,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: -1.6,
      color: offBlack);

  /// Uppercase mono label for buttons / nav / tags (14px, uppercase applied
  /// by the widget via toUpperCase()).
  static const TextStyle monoButtonLabel = TextStyle(
      fontFamily: monoFamily,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.0,
      letterSpacing: -0.28,
      color: white);

  // ===== Widget specs =====

  /// Pill button (100px radius, 48px min height, mono 14 uppercase).
  static ButtonStyle bluePill() =>
      _pill(foreground: white, background: lakeBlue);
  static ButtonStyle blackPill() =>
      _pill(foreground: white, background: offBlack);
  static ButtonStyle ghostPill() => _pill(
      foreground: offBlack, background: Colors.transparent, border: offBlack);

  static ButtonStyle _pill(
      {required Color foreground, required Color background, Color? border}) {
    return ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(foreground),
      backgroundColor: WidgetStatePropertyAll(background),
      overlayColor: WidgetStatePropertyAll(foreground.withValues(alpha: 0.08)),
      minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          side: border != null ? BorderSide(color: border) : BorderSide.none)),
      textStyle: const WidgetStatePropertyAll(monoButtonLabel),
    );
  }

  /// Card shape: 40px radius, 1px ash hairline, no elevation.
  static RoundedRectangleBorder get cardShape => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusCard),
      side: const BorderSide(color: ash, width: 1));

  static RoundedRectangleBorder get softShape => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMin),
      side: const BorderSide(color: ash, width: 1));

  // ===== Elder-care game extension (DESIGN.md amendment) =====
  // Pastel face tints at ≤25% opacity over parchment — illustration surfaces
  // only, always paired with distinct art + text label (never color-alone).
  static const double _faceTintOpacity = 0.22;
  static Color get tintCoral => Color.lerp(parchment, coral, _faceTintOpacity)!;
  static Color get tintSky => Color.lerp(parchment, skyBlue, _faceTintOpacity)!;
  static Color get tintMint => Color.lerp(parchment, mint, _faceTintOpacity)!;
  static Color get tintGold => Color.lerp(parchment, gold, _faceTintOpacity)!;

  // Stable order for cycling tints across cards.
  static List<Color> get faceTints => [tintMint, tintSky, tintCoral, tintGold];

  /// Reminder type color (icon + label + tint together; never color-alone).
  /// Fixed mapping: medicine = lakeBlue, water = skyBlue, food = gold,
  /// exercise = mint.
  static Color reminderColor(String type) {
    switch (type.toLowerCase()) {
      case 'medicine':
        return lakeBlue;
      case 'water':
        return skyBlue;
      case 'food':
        return gold;
      case 'exercise':
        return mint;
      default:
        return graphite;
    }
  }

  /// Shadow — ONLY game card faces + status chips ever get elevation.
  /// Exact spec: black 10% opacity, blur 10, offset (0, 0).
  static List<BoxShadow> get gameCardShadow => [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 0)),
      ];

  /// Backwards-compatible alias (existing screens reference `cardShadow`).
  static List<BoxShadow> get cardShadow => gameCardShadow;

  /// Patient-facing body floor: 20px (--text-body-lg), offBlack.
  static TextStyle get patientBody => monoBodyLg.copyWith(color: offBlack);

  /// ThemeData for the whole app. scaffoldBackgroundColor = parchment GLOBALLY.
  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: lakeBlue,
        onPrimary: white,
        secondary: offBlack,
        onSecondary: white,
        surface: parchment,
        onSurface: offBlack,
        surfaceContainerHighest: periwinkleMist,
        onSurfaceVariant: graphite,
        outline: ash,
        error: crimson,
        onError: white,
      ),
      scaffoldBackgroundColor: parchment,
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: display,
        displayMedium: headingLg,
        displaySmall: heading,
        headlineLarge: headingLg,
        headlineMedium: heading,
        headlineSmall: headingSm,
        titleLarge: subheading,
        titleMedium: subheading,
        titleSmall: monoBody.copyWith(color: offBlack),
        bodyLarge: monoBodyLg,
        bodyMedium: monoBody,
        bodySmall: monoBodySm,
        labelLarge: monoLabel,
        labelMedium: monoBodySm.copyWith(color: offBlack),
        labelSmall: monoCaption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: parchment,
        foregroundColor: offBlack,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: headingSm,
      ),
      dividerTheme: const DividerThemeData(color: ash, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: parchment,
        elevation: 0,
        shape: cardShape,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: parchment,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMin),
            borderSide: const BorderSide(color: ash)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMin),
            borderSide: const BorderSide(color: ash)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMin),
            borderSide: const BorderSide(color: lakeBlue, width: 1)),
        labelStyle: monoCaption,
        hintStyle: monoCaption,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(style: bluePill()),
      elevatedButtonTheme: ElevatedButtonThemeData(style: blackPill()),
      outlinedButtonTheme: OutlinedButtonThemeData(style: ghostPill()),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(offBlack),
          textStyle: const WidgetStatePropertyAll(TextStyle(
              fontFamily: monoFamily,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.28)),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: monoBody.copyWith(color: offBlack),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: parchment,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radiusMin),
              borderSide: const BorderSide(color: ash)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: offBlack,
        contentTextStyle: monoBody.copyWith(color: parchment),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMin)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: lakeBlue),
    );
  }
}
