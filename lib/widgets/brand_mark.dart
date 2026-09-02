import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The SoftCar wordmark + logo mark. Reused on splash, login, and headers.
class BrandMark extends StatelessWidget {
  final double size;
  final bool dark;

  const BrandMark({super.key, this.size = 28, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final color = dark ? AppColors.textOnDark : AppColors.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.28),
          child: Image.asset(
            'assets/logo/logo.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(width: size * 0.32),
        Text(
          'soft',
          style: TextStyle(
            fontSize: size * 0.95,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: color,
          ),
        ),
        Text(
          'car',
          style: TextStyle(
            fontSize: size * 0.95,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}

/// Compact wordmark for small contexts (e.g. map top-left logo).
class BrandWordmark extends StatelessWidget {
  final double size;
  const BrandWordmark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: 'soft',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: size,
            letterSpacing: -0.6,
          ),
        ),
        TextSpan(
          text: 'car',
          style: TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
            fontSize: size,
            letterSpacing: -0.6,
          ),
        ),
      ]),
    );
  }
}
