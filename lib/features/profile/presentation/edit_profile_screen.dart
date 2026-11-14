import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/pulse_text_field.dart';
import '../../../core/widgets/state_views.dart';
import '../application/profile_controller.dart';
import '../domain/profile.dart';

/// Edit profile — writes go through the RLS-protected column grants and are
/// re-validated by database constraints (§8). Errors are typed and visible.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  bool _saving = false;
  AppFailure? _failure;
  bool _initialised = false;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _seed(Profile profile) {
    if (_initialised) return;
    _initialised = true;
    _name.text = profile.displayName;
    _username.text = profile.username ?? '';
    _bio.text = profile.bio;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _failure = null;
    });
    final failure = await ref
        .read(profileControllerProvider.notifier)
        .save(
          displayName: _name.text,
          username: _username.text,
          bio: _bio.text,
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _failure = failure;
    });
    if (failure == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated')));
      if (context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Edit profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/app'),
        ),
      ),
      body: SafeArea(
        child: state.when(
          loading: () => const PulseLoading(),
          error: (error, _) => PulseErrorState(
            failure: error is AppFailure ? error : const ServerFailure(),
            onRetry: () =>
                ref.read(profileControllerProvider.notifier).refresh(),
          ),
          data: (profile) {
            if (profile == null) {
              return const PulseEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not signed in',
                message: 'Log in to edit your profile.',
              );
            }
            _seed(profile);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_failure != null) ...[
                    PulseInlineNotice(message: _failure!.userMessage),
                    const SizedBox(height: 14),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        PulseTextField(
                          controller: _name,
                          label: 'Display name',
                          hint: 'Your name',
                          prefixIcon: Icons.person_outline_rounded,
                          textInputAction: TextInputAction.next,
                          validator: (v) =>
                              Profile.validateDisplayName(v ?? ''),
                        ),
                        const SizedBox(height: 14),
                        PulseTextField(
                          controller: _username,
                          label: 'Username (optional)',
                          hint: 'lowercase, 3-24 chars',
                          prefixIcon: Icons.alternate_email_rounded,
                          textInputAction: TextInputAction.next,
                          validator: (v) => Profile.validateUsername(v ?? ''),
                        ),
                        const SizedBox(height: 14),
                        PulseTextField(
                          controller: _bio,
                          label: 'Bio (optional)',
                          hint: 'A short line about you',
                          prefixIcon: Icons.notes_rounded,
                          textInputAction: TextInputAction.newline,
                          validator: (v) => Profile.validateBio(v ?? ''),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Changes are saved to your account and validated by the database.',
                    style: AppTypography.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  GradientButton(
                    label: 'Save changes',
                    loading: _saving,
                    onPressed: _save,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
