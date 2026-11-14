import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../application/chat_controller.dart';

/// Create a group: title + at least one other person. The server decides the
/// owner (me) and validates everything again (§8 groups).
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _title = TextEditingController();
  final _selected = <String>{};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _canSubmit => _title.text.trim().length >= 2 && _selected.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    // Capture before the await: no BuildContext across an async gap.
    final router = GoRouter.of(context);
    try {
      final id = await ref
          .read(chatRepositoryProvider)
          .createGroup(title: _title.text.trim(), memberIds: _selected.toList());
      ref.invalidate(conversationsProvider);
      if (!mounted) return;
      router.pushReplacement('/chat/$id');
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/app'),
        ),
        title: Text('New group', style: AppTypography.titleMedium),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _canSubmit && !_saving ? _submit : null,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _title,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  hintText: 'Trip to Cox’s Bazar',
                  counterText: '',
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PulseInlineNotice(message: _error!),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Members',
                    style: AppTypography.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${_selected.length} selected',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            Expanded(
              child: people.when(
                loading: () => const PulseLoading(message: 'Loading people'),
                error: (error, _) => PulseErrorState(
                  failure: error is AppFailure ? error : const ServerFailure(),
                  onRetry: () => ref.invalidate(peopleProvider),
                ),
                data: (list) => list.isEmpty
                    ? const PulseEmptyState(
                        icon: Icons.group_outlined,
                        title: 'Nobody to add yet',
                        message:
                            'Create a second account to test groups between two '
                            'people.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final person = list[i];
                          final on = _selected.contains(person.id);
                          return CheckboxListTile(
                            value: on,
                            contentPadding: EdgeInsets.zero,
                            activeColor: AppColors.brand600,
                            title: Text(
                              person.displayName,
                              style: AppTypography.titleMedium,
                            ),
                            subtitle: person.username == null
                                ? null
                                : Text(
                                    '@${person.username}',
                                    style: AppTypography.caption,
                                  ),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(person.id);
                              } else {
                                _selected.remove(person.id);
                              }
                            }),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
