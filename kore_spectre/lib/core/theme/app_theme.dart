import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor   = Color(0xFFB06EF5);
  static const Color errorColor     = Color(0xFFF87171);
  static const Color warningColor   = Color(0xFFFBBF24);
  static const Color successColor   = Color(0xFF34D399);
  static const Color surfaceDark    = Color(0xFF14102A);
  static const Color cardDark       = Color(0xFF1D1838);
  static const Color backgroundDark = Color(0xFF0C0A18);

  static ThemeData get dark {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary:              primaryColor,
      onPrimary:            Colors.white,
      primaryContainer:     Color(0xFF3D1A6E),
      onPrimaryContainer:   Color(0xFFDFB3FF),
      secondary:            Color(0xFFD07EF8),
      onSecondary:          Colors.white,
      secondaryContainer:   Color(0xFF2A1050),
      onSecondaryContainer: Color(0xFFE9B8FF),
      error:                errorColor,
      onError:              Colors.white,
      errorContainer:       Color(0xFF4D001A),
      onErrorContainer:     Color(0xFFFFB3B3),
      surface:              surfaceDark,
      onSurface:            Colors.white,
      surfaceContainerHighest: cardDark,
      outline:              Color(0xFF4A3570),
      outlineVariant:       Color(0xFF2E2050),
    );

    return ThemeData(
      useMaterial3: true,
      brightness:   Brightness.dark,
      colorScheme:  colorScheme,
      scaffoldBackgroundColor: backgroundDark,

      cardTheme: CardThemeData(
        color:            cardDark,
        elevation:        2,
        shadowColor:      Colors.black54,
        surfaceTintColor: primaryColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor:        backgroundDark,
        surfaceTintColor:       Colors.transparent,
        elevation:              0,
        scrolledUnderElevation: 1,
        shadowColor:            Colors.black38,
        centerTitle:            false,
        titleTextStyle: TextStyle(
          color:        Colors.white,
          fontSize:     20,
          fontWeight:   FontWeight.w700,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: Colors.white70),
      ),

      chipTheme: ChipThemeData(
        backgroundColor:   cardDark,
        selectedColor:     Color(0xFF2D1A55),
        disabledColor:     cardDark,
        labelStyle:        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        side:              BorderSide(color: Color(0xFF2E2050)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: EdgeInsets.symmetric(horizontal: 4),
      ),

      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStateProperty.all(cardDark),
        elevation:       WidgetStateProperty.all(0),
        shadowColor:     WidgetStateProperty.all(Colors.transparent),
        overlayColor:    WidgetStateProperty.all(Colors.white10),
        textStyle: WidgetStateProperty.all(
          const TextStyle(color: Colors.white, fontSize: 14),
        ),
        hintStyle: WidgetStateProperty.all(
          const TextStyle(color: Colors.white38, fontSize: 14),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return const BorderSide(color: primaryColor, width: 1.5);
          }
          return const BorderSide(color: Color(0xFF2E2050));
        }),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled:    true,
        fillColor: cardDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation:       0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize:   15,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side:            const BorderSide(color: primaryColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize:   15,
          ),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardDark,
        indicatorColor: primaryColor.withValues(alpha: 0.15),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? primaryColor : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? primaryColor : Colors.white54,
          size: 22,
        )),
      ),

      dividerTheme: const DividerThemeData(
        color:     Color(0xFF2E2050),
        thickness: 1,
        space:     1,
      ),

      listTileTheme: const ListTileThemeData(
        tileColor: cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
