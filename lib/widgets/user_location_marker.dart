import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Round floating "locate me" action used on the live maps to re-centre the
/// camera on the passenger. Shows a small spinner while [busy] is true.
class LocateMeButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool busy;
  final String tooltip;
  const LocateMeButton({
    super.key,
    required this.onTap,
    this.busy = false,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? AppColors.surfaceDarkElevated : Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.info),
                  )
                : Icon(
                    Icons.my_location,
                    color: AppColors.info,
                    size: 21,
                    semanticLabel: tooltip,
                  ),
          ),
        ),
      ),
    );
  }
}