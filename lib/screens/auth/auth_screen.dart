import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../widgets/primary_button.dart';
import 'forgot_password_screen.dart';
import '../legal/legal_screen.dart';

/// Sign in / register against the SoftCar production backend. Registration is
/// phone-first: an Egyptian phone number (verified with a 6-digit OTP via
/// BEON) is required, email is optional. Terms & Privacy are linked from the
/// I-agree checkbox (uber-style).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isRegister = false;

  final _identifier = TextEditingController();
  final _password = TextEditingController();

  final _fullName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPhone = TextEditingController();
  final _regPassword = TextEditingController();
  final _regConfirm = TextEditingController();
  UserGender? _gender;
  bool _agreed = false;
  bool _busy = false;

  // OTP step state
  int _otpStep = 0; // 0 = form, 1 = code entry
  final _otpCode = TextEditingController();
  int _resendIn = 0;
  Timer? _timer;

  String get _regPhoneValue {
    var p = _regPhone.text.trim();
    if (p.startsWith('+20')) p = '0${p.substring(3)}';
    if (p.length == 11 && p.startsWith('1')) p = '0$p';
    return p;
  }

  bool get _regPhoneValid => RegExp(r'^01\d{9}$').hasMatch(_regPhoneValue);

  @override
  void dispose() {
    _timer?.cancel();
    _identifier.dispose();
    _password.dispose();
    _fullName.dispose();
    _regEmail.dispose();
    _regPhone.dispose();
    _regPassword.dispose();
    _regConfirm.dispose();
    _otpCode.dispose();
    super.dispose();
  }

  // ---- sign in -----------------------------------------------------------

  Future<void> _signIn() async {
    if (_identifier.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() => _busy = true);
    final auth = context.read<AuthService>();
    final ok = await auth.login(_identifier.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } else {
      _showError(auth.lastError ?? L10n.t(context, 'signInFailed'));
    }
  }

  // ---- register (phone-first + OTP) --------------------------------------

  void _validateAndSendOtp() {
    final name = _fullName.text.trim();
    final password = _regPassword.text;

    if (name.length < 2) {
      _showError(L10n.t(context, 'enterFullName'));
      return;
    }
    final email = _regEmail.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      _showError(L10n.t(context, 'enterValidEmail'));
      return;
    }
    if (!_regPhoneValid) {
      _showError(L10n.t(context, 'validPhone'));
      return;
    }
    if (password.length < 8) {
      _showError(L10n.t(context, 'passwordTooShort'));
      return;
    }
    if (password != _regConfirm.text) {
      _showError(L10n.t(context, 'passwordsMismatch'));
      return;
    }
    if (_gender == null) {
      _showError(L10n.t(context, 'chooseGenderRequired'));
      return;
    }
    if (!_agreed) {
      _showError(L10n.t(context, 'readTermsRequired'));
      return;
    }
    _sendOtp();
  }

  Future<void> _sendOtp() async {
    setState(() => _busy = true);
    final auth = context.read<AuthService>();
    try {
      await auth.requestOtp(channel: 'phone', target: _regPhoneValue);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _otpStep = 1;
        _otpCode.clear();
        _resendIn = 60;
      });
      _startTimer();
      Haptics.success();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(e.toString());
    }
  }

  void _startTimer() {
    _timer?.cancel();
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

  Future<void> _verifyOtpAndRegister() async {
    final code = _otpCode.text.trim();
    if (code.length != 6) {
      _showError(L10n.t(context, 'enterValidCode'));
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthService>();
    final verified = await auth.verifyOtp(target: _regPhoneValue, code: code);
    if (!mounted) return;
    if (!verified) {
      setState(() => _busy = false);
      _showError(auth.lastError ?? L10n.t(context, 'codeIncorrect'));
      return;
    }
    final ok = await auth.register(
      name: _fullName.text.trim(),
      email: _regEmail.text.trim(),
      password: _regPassword.text,
      phone: _regPhoneValue,
      gender: _gender!.code,
      acceptTerms: _agreed,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } else {
      _showError(auth.lastError ?? L10n.t(context, 'registrationFailed'));
    }
  }

  void _openTerms(String tab) {
    Haptics.selection();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LegalScreen(initialTab: tab)));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  'assets/logo/logo.png',
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'soft',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const TextSpan(
                      text: 'car',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                L10n.t(context, 'bookShuttle'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 24),

            // Mode switcher ---------------------------------------------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    _Tab(
                      label: L10n.t(context, 'signIn'),
                      selected: !_isRegister,
                      onTap: () => setState(() => _isRegister = false),
                    ),
                    _Tab(
                      label: L10n.t(context, 'signUp'),
                      selected: _isRegister,
                      onTap: () => setState(() => _isRegister = true),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _isRegister
                      ? (_otpStep == 0
                          ? _RegisterForm(
                              key: const ValueKey('register'),
                              name: _fullName,
                              email: _regEmail,
                              phone: _regPhone,
                              password: _regPassword,
                              confirm: _regConfirm,
                              gender: _gender,
                              agreed: _agreed,
                              busy: _busy,
                              onGender: (g) => setState(() => _gender = g),
                              onAgreed: (v) => setState(() => _agreed = v),
                              onOpenTerms: _openTerms,
                              onSubmit: _validateAndSendOtp,
                            )
                          : _OtpStep(
                              key: const ValueKey('otp'),
                              code: _otpCode,
                              phone: _regPhoneValue,
                              resendIn: _resendIn,
                              busy: _busy,
                              onResend: _resendIn <= 0 && !_busy ? _sendOtp : null,
                              onVerify: _verifyOtpAndRegister,
                              onBack: () => setState(() {
                                _otpStep = 0;
                                _timer?.cancel();
                              }),
                            ))
                      : _SignInForm(
                          key: const ValueKey('signin'),
                          identifier: _identifier,
                          password: _password,
                          busy: _busy,
                          onSubmit: _signIn,
                          onSwitch: () => setState(() => _isRegister = true),
                          onForgot: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen()),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab
// ---------------------------------------------------------------------------
class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Haptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sign-in form
// ---------------------------------------------------------------------------
class _SignInForm extends StatefulWidget {
  final TextEditingController identifier;
  final TextEditingController password;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onSwitch;
  final VoidCallback onForgot;
  const _SignInForm({
    super.key,
    required this.identifier,
    required this.password,
    required this.busy,
    required this.onSubmit,
    required this.onSwitch,
    required this.onForgot,
  });

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  bool _obscure = true;

  bool get valid =>
      widget.identifier.text.trim().isNotEmpty &&
      widget.password.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t(context, 'signIn'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          L10n.t(context, 'signInSub'),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: widget.identifier,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: L10n.t(context, 'email'),
            hintText: 'name@example.com',
            prefixIcon: const Icon(Icons.alternate_email, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.password,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => valid && !widget.busy ? widget.onSubmit() : null,
          decoration: InputDecoration(
            labelText: L10n.t(context, 'password'),
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.onForgot,
            child: Text(
              L10n.t(context, 'forgotPassword'),
              style: const TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: L10n.t(context, 'signIn'),
          icon: Icons.arrow_forward,
          loading: widget.busy,
          onPressed: valid && !widget.busy ? widget.onSubmit : null,
        ),
        const SizedBox(height: 14),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(L10n.t(context, 'noAccount'),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: widget.onSwitch,
                child: Text(L10n.t(context, 'signUp'),
                    style: const TextStyle(
                        color: AppColors.accent, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Register form (step 0)
// ---------------------------------------------------------------------------
class _RegisterForm extends StatefulWidget {
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController password;
  final TextEditingController confirm;
  final UserGender? gender;
  final bool agreed;
  final bool busy;
  final ValueChanged<UserGender> onGender;
  final ValueChanged<bool> onAgreed;
  final void Function(String tab) onOpenTerms;
  final VoidCallback onSubmit;

  const _RegisterForm({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    required this.confirm,
    required this.gender,
    required this.agreed,
    required this.busy,
    required this.onGender,
    required this.onAgreed,
    required this.onOpenTerms,
    required this.onSubmit,
  });

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t(context, 'signUp'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          L10n.t(context, 'registerSub'),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: widget.name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: L10n.t(context, 'fullName'),
            prefixIcon: const Icon(Icons.person_outline, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: L10n.t(context, 'phoneNumber'),
            hintText: L10n.t(context, 'phoneHint'),
            prefixIcon: const Icon(Icons.phone_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.email,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: L10n.t(context, 'emailOptional'),
            prefixIcon: const Icon(Icons.alternate_email, size: 20),
          ),
        ),
        const SizedBox(height: 18),

        // Gender ------------------------------------------------------------
        Text(L10n.t(context, 'gender'),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _GenderChip(
                label: L10n.t(context, 'male'),
                icon: Icons.male_rounded,
                color: AppColors.seatMale,
                selected: widget.gender == UserGender.male,
                onTap: () => widget.onGender(UserGender.male),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GenderChip(
                label: L10n.t(context, 'female'),
                icon: Icons.female_rounded,
                color: AppColors.seatFemale,
                selected: widget.gender == UserGender.female,
                onTap: () => widget.onGender(UserGender.female),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: widget.password,
          obscureText: _obscure,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: L10n.t(context, 'password'),
            hintText: L10n.t(context, 'passwordAtLeast'),
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.confirm,
          obscureText: _obscureConfirm,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: L10n.t(context, 'confirmPassword'),
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Terms checkbox with hyperlinks ------------------------------------
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => widget.onAgreed(!widget.agreed),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: widget.agreed ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.agreed
                        ? AppColors.accent
                        : AppColors.textTertiary,
                    width: 1.6,
                  ),
                ),
                child: widget.agreed
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 13, height: 1.5),
                  children: [
                    TextSpan(text: '${L10n.t(context, 'agreeShort')} '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => widget.onOpenTerms('terms'),
                        child: Text(
                          L10n.t(context, 'termsTitle'),
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                    const TextSpan(text: ' & '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => widget.onOpenTerms('privacy'),
                        child: Text(
                          L10n.t(context, 'privacyTitle'),
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: L10n.t(context, 'continue'),
          icon: Icons.arrow_forward,
          loading: widget.busy,
          onPressed: widget.busy ? null : widget.onSubmit,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// OTP step (step 1)
// ---------------------------------------------------------------------------
class _OtpStep extends StatefulWidget {
  final TextEditingController code;
  final String phone;
  final int resendIn;
  final bool busy;
  final VoidCallback? onResend;
  final VoidCallback onVerify;
  final VoidCallback onBack;
  const _OtpStep({
    super.key,
    required this.code,
    required this.phone,
    required this.resendIn,
    required this.busy,
    required this.onResend,
    required this.onVerify,
    required this.onBack,
  });

  @override
  State<_OtpStep> createState() => _OtpStepState();
}

class _OtpStepState extends State<_OtpStep> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t(context, 'otpTitle'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '${L10n.t(context, 'otpSub')}\n${widget.phone}',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: widget.code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.w800),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: L10n.t(context, 'enterCode'),
            counterText: '',
            prefixIcon: const Icon(Icons.pin_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: widget.resendIn > 0
              ? Text(
                  '${L10n.t(context, 'resendIn')} ${widget.resendIn} ${L10n.t(context, 'seconds')}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                )
              : TextButton(
                  onPressed: widget.onResend,
                  child: Text(L10n.t(context, 'resendCode'),
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800)),
                ),
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: L10n.t(context, 'verifyCode'),
          icon: Icons.verified_outlined,
          loading: widget.busy,
          onPressed:
              widget.busy || widget.code.text.trim().length != 6
                  ? null
                  : widget.onVerify,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: widget.busy ? null : widget.onBack,
            child: Text(
              L10n.t(context, 'cancel'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _GenderChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected
                    ? Colors.white
                    : isDark
                        ? Colors.white70
                        : AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
