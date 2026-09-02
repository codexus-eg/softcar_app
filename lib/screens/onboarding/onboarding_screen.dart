import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../models/shuttle.dart';
import '../../services/storage_service.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/primary_button.dart';

/// Three-slide onboarding with page indicator + "Get started".
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static const _slides = [
    _SlideData(
      icon: Icons.confirmation_number_outlined,
      color: AppColors.accent,
    ),
    _SlideData(icon: Icons.airport_shuttle, color: AppColors.accent),
    _SlideData(icon: Icons.favorite_rounded, color: AppColors.warning),
  ];

  void _next() {
    if (_index == _slides.length - 1) {
      Navigator.of(context).pushReplacementNamed('/auth');
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.read<StorageService>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.all(20),
                child: BrandMark(size: 26),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final data = _slides[i];
                  final title = L10n.t(context, [
                    'onboardReserveTitle',
                    'onboardWaysTitle',
                    'onboardColourTitle',
                  ][i]);
                  final body = L10n.t(context, [
                    'onboardReserveBody',
                    'onboardWaysBody',
                    'onboardColourBody',
                  ][i]);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            color: data.color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: data.color,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Icon(data.icon,
                                  size: 56, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          body,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        if (i == 1) ...[
                          const SizedBox(height: 28),
                          const _FleetShowcase(),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                              active ? AppColors.ink : AppColors.divider,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _index == _slides.length - 1
                        ? L10n.t(context, 'getStarted')
                        : L10n.t(context, 'continue'),
                    onPressed: () {
                      if (_index == _slides.length - 1) {
                        storage.setOnboarded();
                      }
                      _next();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideData {
  final IconData icon;
  final Color color;
  const _SlideData({required this.icon, required this.color});
}

/// The three SoftCar vehicles shown as cards during onboarding.
class _FleetShowcase extends StatelessWidget {
  const _FleetShowcase();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        for (final c in ShuttleClass.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceDarkElevated
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: c.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(c.icon, size: 21, color: c.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                        Text(c.tagline,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.color,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${c.seats} ${L10n.t(context, 'seatsAbbr')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
