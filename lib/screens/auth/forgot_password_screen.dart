import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../services/auth_service.dart';
import '../../widgets/primary_button.dart';

/// Forgot-password flow (3 steps): phone -> OTP code -> new password.
/// Uses the production BEON OTP endpoints on the SoftCar backend.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _step = 0; // 0 phone, 1 code, 2 new password
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  int _resendIn = 0;
  Timer? _timer;
  String? _hint;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _phoneValue {
    var p = _phone.text.trim();
    if (p.startsWith('+20')) p = '0${p.substring(3)}';
    if (p.length == 11 && p.startsWith('1')) p = '0$p';
    return p;
  }

  bool get _phoneValid => RegExp(r'^01\d{9}$').hasMatch(_phoneValue);

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendIn -= 1;
        if (_resendIn <= 0) t.cancel();
      });
    });
  }

  Future<void> _sendCode() async {
    if (!_phoneValid) {
      _toast(L10n.t(context, 'validPhone'));
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthService>();
    final msg = await auth.forgotPassword(_phoneValue);
    if (!mounted) return;
    setState(() => _busy = false);
    if (msg == null) {
      _toast(auth.lastError ?? L10n.t(context, 'networkError'));
      return;
    }
    _startResendTimer();
    Haptics.success();
    setState(() {
      _step = 1;
      _hint = msg;
    });
  }

  Future<void> _verifyCode() async {
    if (_code.text.trim().length != 6) {
      _toast(L10n.t(context, 'enterValidCode'));
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthService>();
    final ok = await auth.verifyOtp(target: _phoneValue, code: _code.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _toast(auth.lastError ?? L10n.t(context, 'codeIncorrect'));
      return;
    }
    Haptics.success();
    setState(() {
      _step = 2;
      _hint = null;
    });
  }

  Future<void> _reset() async {
    if (_newPassword.text.length < 8) {
      _toast(L10n.t(context, 'passwordTooShort'));
      return;
    }
    if (_newPassword.text != _confirm.text) {
      _toast(L10n.t(context, 'passwordsMismatch'));
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthService>();
    final err = await auth.resetPassword(
      phone: _phoneValue,
      code: _code.text.trim(),
      newPassword: _newPassword.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err);
      return;
    }
    Haptics.success();
    _showDone();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showDone() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.accent, size: 40),
        title: Text(L10n.t(ctx, 'passwordChanged')),
        content: Text(L10n.t(ctx, 'passwordChangedSub')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).popUntil((r) => r.isFirst),
            child: Text(L10n.t(ctx, 'done')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'forgotPasswordTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 4),
            Icon(
              _step == 0
                  ? Icons.lock_reset_rounded
                  : _step == 1
                      ? Icons.pin_outlined
                      : Icons.password_rounded,
              size: 56,
              color: AppColors.accent,
            ),
            const SizedBox(height: 16),
            Text(
              _step == 0
                  ? L10n.t(context, 'forgotPasswordTitle')
                  : _step == 1
                      ? L10n.t(context, 'otpTitle')
                      : L10n.t(context, 'newPassword'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _step == 0
                  ? L10n.t(context, 'forgotPasswordSub')
                  : _step == 1
                      ? '${L10n.t(context, 'otpSub')}\n$_phoneValue'
                      : L10n.t(context, 'passwordAtLeast'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            if (_hint != null) ...[
              const SizedBox(height: 8),
              Text(
                _hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 28),

            if (_step == 0) ...[
              _field(
                controller: _phone,
                label: L10n.t(context, 'phoneNumber'),
                hint: L10n.t(context, 'phoneHint'),
                icon: Icons.phone_outlined,
                keyboard: TextInputType.phone,
                formatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))
                ],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: L10n.t(context, 'sendCode'),
                icon: Icons.sms_outlined,
                loading: _busy,
                onPressed: _busy || !_phoneValid ? null : _sendCode,
              ),
            ],

            if (_step == 1) ...[
              _field(
                controller: _code,
                label: L10n.t(context, 'enterCode'),
                hint: '• • • • • •',
                icon: Icons.pin_outlined,
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              if (_resendIn > 0)
                Center(
                  child: Text(
                    '${L10n.t(context, 'resendIn')} $_resendIn ${L10n.t(context, 'seconds')}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                )
              else
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _sendCode,
                    child: Text(L10n.t(context, 'resendCode')),
                  ),
                ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: L10n.t(context, 'verifyCode'),
                icon: Icons.check_circle_outline,
                loading: _busy,
                onPressed: _busy || _code.text.trim().length != 6
                    ? null
                    : _verifyCode,
              ),
            ],

            if (_step == 2) ...[
              _field(
                controller: _newPassword,
                label: L10n.t(context, 'newPassword'),
                hint: L10n.t(context, 'passwordAtLeast'),
                icon: Icons.lock_outline,
                obscure: _obscure,
                suffixIcon: _visibilityToggle(
                  hidden: _obscure,
                  onToggle: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: 12),
              _field(
                controller: _confirm,
                label: L10n.t(context, 'confirmPassword'),
                icon: Icons.lock_outline,
                obscure: _obscureConfirm,
                suffixIcon: _visibilityToggle(
                  hidden: _obscureConfirm,
                  onToggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: L10n.t(context, 'savePassword'),
                icon: Icons.save_outlined,
                loading: _busy,
                onPressed: _busy ? null : _reset,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? formatters,
    int? maxLength,
    bool obscure = false,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      maxLength: maxLength,
      inputFormatters: formatters,
      onChanged: onChanged,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _visibilityToggle({
    required bool hidden,
    required VoidCallback onToggle,
  }) {
    return IconButton(
      icon: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
      ),
      onPressed: onToggle,
    );
  }
}
