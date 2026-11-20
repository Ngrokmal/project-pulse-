import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../application/profile_controller.dart';
import '../../domain/profile.dart';
import 'pulse_sheet.dart';

/// "Your card": the five lines the card is built from.
///
/// The last two fields are the interesting ones. **Status** is the line at the
/// top of Right now, and **Where** is a place the person types — the note under
/// it says so out loud, because that promise is the reason the field exists.
class EditCardSheet extends ConsumerStatefulWidget {
  const EditCardSheet({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<EditCardSheet> createState() => _EditCardSheetState();
}

class _EditCardSheetState extends ConsumerState<EditCardSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.displayName,
  );
  late final TextEditingController _handle = TextEditingController(
    text: widget.profile.username ?? '',
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.profile.bio,
  );
  late final TextEditingController _status = TextEditingController(
    text: widget.profile.statusText,
  );
  late final TextEditingController _where = TextEditingController(
    text: widget.profile.whereText,
  );

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _status.dispose();
    _where.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = Profile.validateDisplayName(_name.text);
    final handleError = Profile.validateUsername(_handle.text);
    final bioError = Profile.validateBio(_bio.text);
    final statusError = Profile.validateStatus(_status.text);
    final whereError = Profile.validateWhere(_where.text);
    final first =
        nameError ?? handleError ?? bioError ?? statusError ?? whereError;
    if (first != null) {
      setState(() => _error = first);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final failure = await ref
        .read(profileControllerProvider.notifier)
        .save(
          displayName: _name.text,
          username: _handle.text.trim().isEmpty ? null : _handle.text,
          bio: _bio.text,
          statusText: _status.text,
          whereText: _where.text,
          // The zone is re-captured on every save, so "Local time" follows the
          // phone rather than a value frozen at signup.
          captureZone: true,
        );

    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      setState(() => _error = _describe(failure));
      return;
    }
    Navigator.of(context).pop(true);
  }

  static String _describe(AppFailure failure) => switch (failure) {
    ValidationFailure(:final userMessage) => userMessage,
    AuthFailure(:final userMessage) => userMessage,
    NetworkFailure() => 'The card could not be reached. Try again in a moment.',
    _ => 'The card could not be saved.',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHeading(
          title: 'Your card',
          subtitle:
              'These are the lines people actually read. Nothing here is '
              'public beyond Pulse.',
        ),
        _Field(
          label: 'Name',
          controller: _name,
          maxLength: Profile.displayNameMax,
          hint: 'Saiful Islam',
        ),
        _Field(
          label: 'Handle',
          controller: _handle,
          maxLength: 24,
          hint: 'saiful',
          prefix: '@',
          autocorrect: false,
        ),
        _Field(
          label: 'One line',
          controller: _bio,
          maxLength: Profile.bioMax,
          hint: 'Quiet software, loud playlists.',
          lines: 3,
        ),
        _Field(
          label: 'Status — right now',
          controller: _status,
          maxLength: Profile.statusMax,
          hint: 'Building Pulse, every night',
        ),
        _Field(
          label: 'Where',
          controller: _where,
          maxLength: Profile.whereMax,
          hint: 'Chattogram, BD',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 2, right: 8),
          child: Text(
            'You type this yourself. Pulse never reads GPS and never guesses '
            'your city — leave it empty and the row disappears.',
            style: AppTypography.micro.copyWith(
              fontSize: 10.5,
              height: 1.55,
              color: const Color(0xFFA9A5B8),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: AppTypography.micro.copyWith(
                fontSize: 12,
                color: AppColors.danger,
              ),
            ),
          ),
        SheetActions(
          busy: _busy,
          confirmLabel: 'Save',
          onCancel: () => Navigator.of(context).pop(false),
          onConfirm: _save,
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.maxLength,
    this.hint,
    this.prefix,
    this.lines = 1,
    this.autocorrect = true,
  });

  final String label;
  final TextEditingController controller;
  final int maxLength;
  final String? hint;
  final String? prefix;
  final int lines;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 3, bottom: 6),
            child: Text(
              label.toUpperCase(),
              style: AppTypography.micro.copyWith(
                fontSize: 10.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          TextField(
            controller: controller,
            maxLength: maxLength,
            maxLines: lines,
            minLines: lines,
            autocorrect: autocorrect,
            enableSuggestions: autocorrect,
            textCapitalization: autocorrect
                ? TextCapitalization.sentences
                : TextCapitalization.none,
            style: AppTypography.bodyMedium.copyWith(
              fontSize: 14.5,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              prefixText: prefix,
              counterText: '',
              filled: true,
              fillColor: AppColors.cardAlt,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: const BorderSide(
                  color: AppColors.brand400,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
