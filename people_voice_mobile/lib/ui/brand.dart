import 'package:flutter/material.dart';

/// Values mirrored from the published website's main.css and navbar.css.
abstract final class Brand {
  static const red = Color(0xffd00000);
  static const heading = Color(0xff2d465e);
  static const text = Color(0xff212529);
  static const muted = Color(0xff6c757d);
  static const line = Color(0xffe1e7ed);
  static const light = Color(0xfff0f1f2);
  static const logo = 'assets/brand/logo.png';

  static ThemeData theme({Brightness brightness = Brightness.light}) {
    final dark = brightness == Brightness.dark;
    final foreground = dark ? const Color(0xffedf2f7) : heading;
    final accent = dark ? const Color(0xffff8d8d) : red;
    final border = dark ? const Color(0xff334151) : line;
    final surface = dark ? const Color(0xff17212e) : Colors.white;
    final scheme = ColorScheme.fromSeed(seedColor: red, brightness: brightness)
        .copyWith(
          primary: accent,
          onPrimary: dark ? const Color(0xff450008) : Colors.white,
          secondary: dark ? const Color(0xffb8cfe6) : heading,
          surface: surface,
          onSurface: dark ? const Color(0xffedf2f7) : text,
          onSurfaceVariant: dark
              ? const Color(0xffb2bfcd)
              : const Color(0xff586574),
          surfaceContainerLow: dark
              ? const Color(0xff1d2937)
              : const Color(0xfff2f5f8),
          surfaceContainerHighest: dark
              ? const Color(0xff2c3949)
              : const Color(0xffe9eef3),
          outline: dark ? const Color(0xff718296) : const Color(0xff7d8b99),
          outlineVariant: border,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: dark
          ? const Color(0xff101923)
          : const Color(0xfff8fafc),
      colorScheme: scheme,
    );
    TextStyle title(TextStyle? style) => (style ?? const TextStyle()).copyWith(
      fontFamily: 'Montserrat',
      color: foreground,
      fontWeight: FontWeight.w700,
      letterSpacing: -.7,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: title(base.textTheme.headlineLarge)
            .copyWith(fontSize: 30, height: 1.2),
        headlineMedium: title(base.textTheme.headlineMedium)
            .copyWith(fontSize: 26, height: 1.25),
        headlineSmall: title(base.textTheme.headlineSmall)
            .copyWith(fontSize: 22, height: 1.3),
        titleLarge: title(base.textTheme.titleLarge)
            .copyWith(fontSize: 20, height: 1.3),
        titleMedium: title(base.textTheme.titleMedium),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.55),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: surface,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: title(base.textTheme.titleLarge),
        shape: Border(bottom: BorderSide(color: border)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: .12),
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: .12),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent
                : scheme.onSurfaceVariant,
            size: 23,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: states.contains(WidgetState.selected)
                ? accent
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused) ? accent : border,
          ),
        ),
        shape: WidgetStatePropertyAll(shape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: border),
          shape: shape,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
    );
  }
}

class BrandMasthead extends StatelessWidget {
  const BrandMasthead({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          Brand.logo,
          width: 44,
          height: 44,
          fit: BoxFit.contain,
          semanticLabel: 'Fayetteville The People Voice',
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Fayetteville',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 19,
                letterSpacing: -.8,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              'THE PEOPLE VOICE',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 10,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.eyebrow, this.subtitle});
  final String title;
  final String? eyebrow, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[
        Text(
          eyebrow!.toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 11,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(
          subtitle!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          Container(width: 44, height: 3, color: Brand.red),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
      const SizedBox(height: 20),
    ],
  );
}

/// A readable empty or recoverable error state with an optional next step.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.newspaper_outlined,
    this.onAction,
    this.actionLabel,
  });
  final String title, message;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: colors.primary),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
