import 'package:flutter/material.dart';

class AppColors {
  static const Color darkTeal = Color(0xFF0F4C5C);
  static const Color lightTeal = Color(0xFF26C6DA);
  static const List<Color> primaryGradient = [darkTeal, lightTeal];
  
  static BoxDecoration gradientDecoration = BoxDecoration(
    gradient: const LinearGradient(
      colors: primaryGradient,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(12),
  );
}

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final double height;
  final double? width;
  final bool loading;
  final IconData? icon;

  const GradientButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.height = 52,
    this.width,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: onPressed == null 
              ? [Colors.grey, Colors.grey.shade400] 
              : AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (onPressed == null ? Colors.grey : AppColors.darkTeal).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(30),
          child: Center(
            child: loading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class CustomInputDecoration {
  static InputDecoration getDecoration(String hint, {IconData? prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black45, fontSize: 14),
      filled: true,
      fillColor: Colors.white.withOpacity(0.9),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppColors.darkTeal, size: 20) : null,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.lightTeal, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
    );
  }
}

/// Shown next to a host's name once an admin has approved their CNIC.
///
/// This is the visible payoff for the verification flow — without it the whole
/// review queue produces nothing a guest can actually see.
class VerifiedBadge extends StatelessWidget {
  /// Value of `hosts.verification_status`.
  final String? status;

  /// Compact form for cards and list tiles: icon only, no label.
  final bool compact;

  const VerifiedBadge({super.key, required this.status, this.compact = false});

  bool get _isVerified => status == 'verified';

  @override
  Widget build(BuildContext context) {
    if (!_isVerified) return const SizedBox.shrink();

    const green = Color(0xFF15803D);

    if (compact) {
      return const Tooltip(
        message: 'Identity verified',
        child: Icon(Icons.verified_rounded, size: 15, color: green),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: green.withValues(alpha: 0.22)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 13, color: green),
          SizedBox(width: 5),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: green,
            ),
          ),
        ],
      ),
    );
  }
}

/// App-wide theme.
///
/// MaterialApp previously had no `theme:` at all, so anything not explicitly
/// styled fell back to stock Material blue — dialogs, date pickers, text
/// selection handles, default buttons, the tab indicator. That is why the app
/// looked inconsistent even where individual screens were carefully coloured.
class AppTheme {
  AppTheme._();

  static const Color surface = Color(0xFFF6F8FB);
  static const Color textDark = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.darkTeal,
      primary: AppColors.darkTeal,
      secondary: AppColors.lightTeal,
      surface: Colors.white,
      brightness: Brightness.light,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: surface,
      splashFactory: InkSparkle.splashFactory,

      textTheme: base.textTheme.apply(
        bodyColor: textDark,
        displayColor: textDark,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkTeal,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkTeal,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkTeal,
          side: const BorderSide(color: AppColors.lightTeal),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.darkTeal),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AppColors.lightTeal, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF1F5F9),
        selectedColor: AppColors.darkTeal,
        labelStyle: const TextStyle(fontSize: 12.5, color: textDark),
        secondaryLabelStyle:
            const TextStyle(fontSize: 12.5, color: Colors.white),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: AppColors.darkTeal,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: const TextStyle(fontSize: 13.5),
      ),

      // Was stock blue everywhere the app did not override it.
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.darkTeal),
      dividerTheme: DividerThemeData(color: Colors.grey.shade200, space: 1),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.darkTeal,
        foregroundColor: Colors.white,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.darkTeal,
        selectionHandleColor: AppColors.darkTeal,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        headerBackgroundColor: AppColors.darkTeal,
        headerForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
