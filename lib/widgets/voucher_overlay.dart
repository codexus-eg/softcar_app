import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../core/utils/haptics.dart';
import 'primary_button.dart';

/// First-open promo overlay for a single voucher (see `GET /api/vouchers/active`).
/// Resolves to `'apply'` when the passenger taps "Apply now", `'later'` for
/// the dismiss action, or null if the dialog is dismissed some other way.
Future<String?> showVoucherOverlay(
  BuildContext context,
  Map<String, dynamic> voucher,
) {
  final code = voucher['code']?.toString() ?? '';
  final name = voucher['name']?.toString() ?? '';
  final description = voucher['description']?.toString() ?? '';
  final imageUrl = Formatters.imageUrl(voucher['imageUrl']);

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder:
        (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 168,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isNotEmpty)
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => _gradientPlaceholder(name),
                      )
                    else
                      _gradientPlaceholder(name),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                          stops: [0.4, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      bottom: 14,
                      right: 20,
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      L10n.t(ctx, 'specialOffer'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.ink,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              code,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 50,
                          height: 50,
                          child: IconButton(
                            tooltip: L10n.t(ctx, 'copyCode'),
                            icon: const Icon(
                              Icons.copy_rounded,
                              size: 20,
                              color: AppColors.accent,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.accentSoft,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: code),
                              );
                              if (!ctx.mounted) return;
                              Haptics.success();
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(L10n.t(ctx, 'codeCopied')),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      accent: true,
                      label: L10n.t(ctx, 'applyNow'),
                      icon: Icons.local_offer_outlined,
                      onPressed: () => Navigator.of(ctx).pop('apply'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop('later'),
                      child: Text(L10n.t(ctx, 'later')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
  );
}

Widget _gradientPlaceholder(String name) {
  return DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.accent, AppColors.accentDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Icon(
        Icons.confirmation_number_outlined,
        size: 46,
        color: Colors.white.withValues(alpha: 0.35),
      ),
    ),
  );
}
