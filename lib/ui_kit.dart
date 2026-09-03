import 'package:flutter/material.dart';

import 'animations.dart';
import 'app_theme.dart';

/// Network image with a shimmer placeholder, a fade-in, and a real error
/// state.
///
/// Every screen used a bare `Image.network`, which shows nothing while the
/// bytes arrive, pops in hard when they do, and renders the framework's grey
/// exception box when a URL is dead — which happens often here, since listing
/// photos come from user uploads.
class SmartImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final IconData fallbackIcon;

  const SmartImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.fallbackIcon = Icons.image_not_supported_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = (url == null || url!.trim().isEmpty)
        ? _placeholder()
        : Image.network(
            url!,
            width: width,
            height: height,
            fit: fit,
            // Fades the decoded frame in instead of snapping it on.
            frameBuilder: (context, child, frame, wasSyncLoaded) {
              if (wasSyncLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                child: child,
              );
            },
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Shimmer(
                width: width ?? double.infinity,
                height: height ?? double.infinity,
                radius: radius,
              );
            },
            errorBuilder: (_, __, ___) => _placeholder(),
          );

    if (radius == 0) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: content,
    );
  }

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: const Color(0xFFEDF1F5),
        alignment: Alignment.center,
        child: Icon(fallbackIcon, size: 28, color: Colors.black26),
      );
}

/// Consistent snackbars. Screens were each building their own SnackBar with a
/// different colour and no icon, so success and failure looked the same.
class AppSnack {
  AppSnack._();

  static void success(BuildContext context, String message) =>
      _show(context, message, const Color(0xFF15803D), Icons.check_circle_rounded);

  static void error(BuildContext context, String message) =>
      _show(context, message, const Color(0xFFDC2626), Icons.error_rounded);

  static void info(BuildContext context, String message) =>
      _show(context, message, AppColors.darkTeal, Icons.info_rounded);

  static void _show(
      BuildContext context, String message, Color colour, IconData icon) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colour,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.all(14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 19),
              const SizedBox(width: 11),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      );
  }
}

/// Illustrated empty state. Replaces the bare grey icon plus one line of text
/// that most screens used.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeSlideIn(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.lightTeal.withValues(alpha: 0.16),
                      AppColors.darkTeal.withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: Icon(icon, size: 46, color: AppColors.darkTeal),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF64748B), height: 1.45),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 22),
                GradientButton(
                  width: 220,
                  height: 46,
                  text: actionLabel!,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Section heading with the teal accent bar the host dashboard already used,
/// pulled out so every screen gets the same one.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 21,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: AppColors.primaryGradient,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
