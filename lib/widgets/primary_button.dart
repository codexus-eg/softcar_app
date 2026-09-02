import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';

/// SoftCar's signature call-to-action button.
///
/// Unlike a plain flat button, it uses a red brand-gradient with a white
/// circular "go" chip on the right — a distinctive fingerprint that sets
/// SoftCar apart. Variants:
///  - `primary` (default): ink (light mode) / white (dark mode) with icon chip
///  - `accent`: SoftCar red gradient — the signature look
///  - `outline`: bordered, transparent fill
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outline;
  final bool accent;
  final IconData? icon;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.outline = false,
    this.accent = false,
    this.icon,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final useGradient = accent;
    final background = outline
        ? Colors.transparent
        : accent
            ? null
            : isDark
                ? Colors.white
                : AppColors.ink;
    final foreground = outline
        ? AppColors.textPrimary
        : accent
            ? Colors.white
            : isDark
                ? AppColors.ink
                : Colors.white;
    final border = outline
        ? Border.all(color: AppColors.divider, width: 1.2)
        : null;

    final child = loading
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(foreground),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
              if (accent && enabled) ...[
                const SizedBox(width: 10),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward,
                      size: 17, color: Colors.white),
                ),
              ],
            ],
          );

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: useGradient
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.accent, AppColors.accentDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                )
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: border,
                ),
          child: InkWell(
            onTap: enabled
                ? () {
                    Haptics.light();
                    onPressed!();
                  }
                : null,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: height,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
