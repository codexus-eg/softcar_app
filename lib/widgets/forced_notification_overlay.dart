import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../services/push_service.dart';

/// Forced in-app notification overlay (see backend `EVENT_NOTIFICATION` push).
/// Pops a full-screen floating card that the passenger must dismiss with the
/// X button; while it is on screen the loud system notification also plays so
/// the alert is heard even if the app is in the foreground. Resolves with
/// `true` when the passenger taps the call-to-action, `false` on dismiss.
Future<bool?> showForcedNotificationOverlay(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
}) {
  unawaited(
    PushService.instance.show(
      title: title,
      body: message,
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      payload: jsonEncode(<String, String>{
        'type': 'EVENT_NOTIFICATION',
        'id': '',
      }),
    ),
  );
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder:
        (ctx) => PopScope(
          canPop: false,
          child: Dialog(
            insetPadding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(ctx).brightness == Brightness.dark
                        ? AppColors.surfaceDarkElevated
                        : AppColors.surface,
                    AppColors.accent.withValues(alpha: 0.12),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.55,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(
                              actionLabel,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.06),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(ctx).pop(false),
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(Icons.close_rounded, color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
}