import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_mark.dart';
import '../../../core/widgets/pulse_text_field.dart';
import '../../../core/widgets/state_views.dart';
import '../application/auth_controller.dart';

enum _Mode { login, signup }

/// Login / Sign up. Real Supabase auth, real validation, real error states —
/// no fake success, no hidden failures (§2 B, §11, §26).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.startInSignup = false});

  final bool startInSignup;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  late _Mode _mode = widget.startInSignup ? _Mode.signup : _Mode.login;
  bool _submitting = false;
  AppFailure? _failure;
  String? _infoBanner;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _isSignup => _mode == _Mode.signup;

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Email is required';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(value);
    return ok ? null : 'Enter a valid email address';
  }

  String? _validatePassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Use at least 8 characters';
    return null;
  }

  String? _validateName(String? v) {
    if (!_isSignup) return null;
    final value = (v ?? '').trim();
    if (value.length < 2) return 'Enter your name';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (!_isSignup) return null;
    if ((v ?? '') != _password.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return; // duplicate-submit guard (§11)
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _failure = null;
      _infoBanner = null;
    });

    try {
      if (_isSignup) {
        final res = await ref
            .read(authControllerProvider.notifier)
            .signUp(
              displayName: _name.text,
              email: _email.text,
              password: _password.text,
            );
        if (!mounted) return;
        if (res?.needsEmailConfirmation ?? false) {
          setState(() {
            _mode = _Mode.login;
            _infoBanner = 'Account created. Confirm your email, then log in.';
          });
        } else {
          context.go('/app');
        }
      } else {
        final failure = await ref
            .read(authControllerProvider.notifier)
            .signIn(email: _email.text, password: _password.text);
        if (!mounted) return;
        if (failure == null) {
          context.go('/app');
        } else {
          setState(() => _failure = failure);
        }
      }
    } on AppFailure catch (f) {
      if (mounted) setState(() => _failure = f);
    } catch (_) {
      if (mounted) setState(() => _failure = const ServerFailure());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/welcome'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: PulseMark(size: 58)),
                    const SizedBox(height: 18),
                    Text(
                      _isSignup ? 'Create your account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isSignup
                          ? 'Join Pulse and start connecting.'
                          : 'Log in to continue to your chats.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_infoBanner != null) ...[
                      PulseInlineNotice(
                        message: _infoBanner!,
                        tone: NoticeTone.success,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_failure != null) ...[
                      PulseInlineNotice(message: _failure!.userMessage),
                      const SizedBox(height: 14),
                    ],
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (_isSignup) ...[
                            PulseTextField(
                              controller: _name,
                              label: 'Full name',
                              hint: 'Ngrok Use',
                              prefixIcon: Icons.person_outline_rounded,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.name],
                              validator: _validateName,
                            ),
                            const SizedBox(height: 14),
                          ],
                          PulseTextField(
                            controller: _email,
                            label: 'Email address',
                            hint: 'you@example.com',
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            prefixIcon: Icons.alternate_email_rounded,
                            autofillHints: const [AutofillHints.email],
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 14),
                          PulseTextField(
                            controller: _password,
                            label: 'Password',
                            obscure: true,
                            textInputAction: _isSignup
                                ? TextInputAction.next
                                : TextInputAction.done,
                            prefixIcon: Icons.lock_outline_rounded,
                            autofillHints: const [AutofillHints.password],
                            validator: _validatePassword,
                            onSubmitted: (_) => _isSignup ? null : _submit(),
                          ),
                          if (_isSignup) ...[
                            const SizedBox(height: 14),
                            PulseTextField(
                              controller: _confirm,
                              label: 'Confirm password',
                              obscure: true,
                              textInputAction: TextInputAction.done,
                              prefixIcon: Icons.lock_clock_outlined,
                              validator: _validateConfirm,
                              onSubmitted: (_) => _submit(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    GradientButton(
                      label: _isSignup ? 'Create account' : 'Log in',
                      loading: _submitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() {
                              _mode = _isSignup ? _Mode.login : _Mode.signup;
                              _failure = null;
                              _infoBanner = null;
                            }),
                      child: Text(
                        _isSignup
                            ? 'Already have an account? Log in'
                            : 'New to Pulse? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
