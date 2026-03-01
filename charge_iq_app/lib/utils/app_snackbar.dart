import 'package:flutter/material.dart';

/// Centralized snackbar utility for consistent styling across the app.
///
/// Usage:
///   AppSnackBar.success(context, 'Vehicle added!');
///   AppSnackBar.error(context, 'Something went wrong');
///   AppSnackBar.warning(context, 'Battery low');
///   AppSnackBar.info(context, 'AI mode enabled');
class AppSnackBar {
  AppSnackBar._();

  // ── Color palette ───────────────────────────────────────────────────────
  static const Color _successBg = Color(0xFF10B981);
  static const Color _errorBg = Color(0xFFEF4444);
  static const Color _warningBg = Color(0xFFF59E0B);
  static const Color _infoBg = Color(0xFF1565C0);

  // ── Public methods ──────────────────────────────────────────────────────

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    IconData icon = Icons.check_circle_rounded,
  }) {
    _show(
      context,
      message,
      bgColor: _successBg,
      icon: icon,
      duration: duration,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    IconData icon = Icons.error_rounded,
  }) {
    _show(context, message, bgColor: _errorBg, icon: icon, duration: duration);
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    IconData icon = Icons.warning_amber_rounded,
  }) {
    _show(
      context,
      message,
      bgColor: _warningBg,
      icon: icon,
      duration: duration,
    );
  }

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    IconData icon = Icons.info_outline,
  }) {
    _show(context, message, bgColor: _infoBg, icon: icon, duration: duration);
  }

  /// Generic show — used internally and can be called directly for custom cases.
  static void _show(
    BuildContext context,
    String message, {
    required Color bgColor,
    required IconData icon,
    Color iconColor = Colors.white,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: duration,
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
