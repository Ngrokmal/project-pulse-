import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../application/admin_providers.dart';
import '../domain/admin_repository.dart';

/// A presentation gate, never the security boundary: every RPC checks the
/// authenticated server-side allowlist again at the moment of the action.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminAccessProvider);
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: access.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not verify administrator access.'),
              TextButton(
                onPressed: () => ref.invalidate(adminAccessProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: (allowed) => allowed && auth is AuthSignedIn
            ? _AdminWorkspace(key: ValueKey(auth.user.id))
            : const Center(child: Text('Administrator access is required.')),
      ),
    );
  }
}

class _AdminWorkspace extends ConsumerStatefulWidget {
  const _AdminWorkspace({super.key});
  @override
  ConsumerState<_AdminWorkspace> createState() => _AdminWorkspaceState();
}

class _AdminWorkspaceState extends ConsumerState<_AdminWorkspace> {
  final _query = TextEditingController();
  List<ManagedUser> _users = [];
  String? _error;
  bool _loading = true;
  bool _saving = false;
  int _offset = 0;
  bool _hasMore = false;
  String _submittedQuery = '';
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load(reset: true));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!mounted || (_loading && !reset)) return;
    if (reset) {
      _offset = 0;
      _submittedQuery = _query.text.trim();
    }
    final generation = ++_loadGeneration;
    final query = _submittedQuery;
    final offset = _offset;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _users = [];
        _hasMore = false;
      }
    });
    try {
      final next = await ref
          .read(adminRepositoryProvider)
          .users(query: query, offset: offset);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _users = reset ? next : [..._users, ...next];
        _offset += next.length;
        _hasMore = next.length == 25;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = 'Could not load users. Please try again.');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _run(Future<void> Function(AdminRepository) action) async {
    if (!mounted || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action(ref.read(adminRepositoryProvider));
      if (mounted) await _load(reset: true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The change was not confirmed. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeSuspension(ManagedUser user) async {
    if (user.isSuspended) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore account?'),
          content: Text(
            'Allow ${user.displayName.isEmpty ? user.email : user.displayName} to sign in again? Their old session will not be restored.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await _run((repo) => repo.setSuspension(user.id, false));
      }
      return;
    }
    final duration = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Suspend account'),
        children: [
          for (final item in [
            (1, '1 hour'),
            (24, '24 hours'),
            (168, '7 days'),
            (0, 'Until an admin restores it'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item.$1),
              child: Text(item.$2),
            ),
        ],
      ),
    );
    if (duration == null) return;
    final until = duration == 0
        ? null
        : DateTime.now().toUtc().add(Duration(hours: duration));
    await _run((repo) => repo.setSuspension(user.id, true, until: until));
  }

  Future<void> _editMessage() async {
    final code = TextEditingController();
    final message = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit error message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'Error code'),
              maxLength: 64,
            ),
            TextField(
              controller: message,
              decoration: const InputDecoration(labelText: 'Message'),
              maxLength: 500,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (code.text.trim(), message.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    code.dispose();
    message.dispose();
    if (result == null || result.$1.isEmpty || result.$2.isEmpty) return;
    await _run((repo) => repo.setErrorMessage(result.$1, result.$2));
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'Account controls',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Changes are checked by the server and recorded in the audit log.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _query,
        enabled: !_loading && !_saving,
        decoration: InputDecoration(
          labelText: 'Search name or email',
          suffixIcon: IconButton(
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.search),
          ),
        ),
        onSubmitted: (_) => _load(reset: true),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (!_loading && _users.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No users found.'),
        ),
      for (final user in _users)
        Card(
          child: ExpansionTile(
            title: Text(
              user.displayName.isEmpty ? user.email : user.displayName,
            ),
            subtitle: Text('${user.email}\n${user.status}'),
            children: [
              SwitchListTile(
                title: const Text('Can send messages'),
                value: user.canSendMessages,
                onChanged: _saving
                    ? null
                    : (value) => _run(
                        (repo) =>
                            repo.setControl(user.id, 'send_messages', value),
                      ),
              ),
              SwitchListTile(
                title: const Text('Can start calls'),
                value: user.canStartCalls,
                onChanged: _saving
                    ? null
                    : (value) => _run(
                        (repo) =>
                            repo.setControl(user.id, 'start_calls', value),
                      ),
              ),
              SwitchListTile(
                title: const Text('Can change profile photo'),
                value: user.canChangeProfilePhoto,
                onChanged: _saving
                    ? null
                    : (value) => _run(
                        (repo) => repo.setControl(
                          user.id,
                          'change_profile_photo',
                          value,
                        ),
                      ),
              ),
              TextButton(
                onPressed: _saving || !user.canManageSuspension
                    ? null
                    : () => _changeSuspension(user),
                child: Text(
                  !user.canManageSuspension
                      ? 'Status requires separate review'
                      : user.isSuspended
                      ? 'Restore account'
                      : 'Suspend account',
                ),
              ),
            ],
          ),
        ),
      if (_hasMore && !_loading)
        TextButton(
          onPressed: _saving ? null : () => _load(),
          child: const Text('Load more users'),
        ),
      const Divider(height: 32),
      OutlinedButton.icon(
        onPressed: _saving ? null : _editMessage,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit server error message'),
      ),
    ],
  );
}
