import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../application/blocked_people_controller.dart';
import '../domain/blocked_person.dart';
import 'widgets/orbit_ring.dart';
import 'widgets/pulse_ui.dart';

/// **Blocked people.**
///
/// One honest page for the quietest thing the app does. It lists exactly the
/// rows this account wrote into `public.blocks` — nothing is inferred, no one
/// is told, and every row can be undone from here.
///
/// The v4 card already knows how to block (Safety lens, a person's profile
/// sheet). Until this page existed, a block was a one-way door: the row was
/// real on the server, but there was nowhere to see it and no way back.
class BlockedPeopleScreen extends ConsumerWidget {
  const BlockedPeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(blockedPeopleProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _Backdrop(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _Header(count: people.value?.length),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppMotion.base,
                    switchInCurve: AppMotion.curve,
                    child: people.when(
                      loading: () => const _Loading(),
                      error: (error, _) => _Failed(
                        failure: error is AppFailure
                            ? error
                            : const ServerFailure(),
                        onRetry: () => ref.invalidate(blockedPeopleProvider),
                      ),
                      data: (rows) => KeyedSubtree(
                        key: ValueKey(rows.isEmpty ? 'empty' : 'list'),
                        child: rows.isEmpty
                            ? const _Empty()
                            : _List(people: rows),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The navy the profile opens with, kept to the top third and faded out, so the
/// page belongs to the same product as the card without drowning the list.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // A long, soft fall: the navy must be gone by the time the first
          // card arrives, and must never end as a visible seam.
          // The navy must be *finished* before the first line of ink, or the
          // empty state writes dark grey on a dark blue.
          stops: [0.0, 0.11, 0.34],
          colors: [AppColors.navy800, AppColors.navy900, AppColors.bg],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 16, 10),
      child: Row(
        children: [
          _RoundButton(
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            onTap: () => context.canPop() ? context.pop() : context.go('/app'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Blocked people',
                  style: AppTypography.titleLarge.copyWith(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == null
                      ? 'Reading your list…'
                      : count == 0
                      ? 'Nobody, right now'
                      : '$count ${count == 1 ? 'person' : 'people'}',
                  style: AppTypography.micro.copyWith(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          if (count != null && count! > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Private',
                    style: AppTypography.micro.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.people});

  final List<BlockedPerson> people;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        4,
        AppSpacing.screenX,
        32,
      ),
      children: [
        const _RuleCard(),
        const SizedBox(height: 18),
        for (final (index, person) in people.indexed) ...[
          _BlockedTile(person: person, now: DateTime.now(), index: index),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Unblocking is instant and silent — they are never told either way.',
            textAlign: TextAlign.center,
            style: AppTypography.micro.copyWith(
              fontSize: 11,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// What a block actually does, in three lines. This is the copy that makes the
/// page worth having: a person should not have to guess what they did.
class _RuleCard extends StatelessWidget {
  const _RuleCard();

  @override
  Widget build(BuildContext context) {
    return PulseCard(
      gradientHairline: true,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.brand600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'What a block does',
                  style: AppTypography.titleMedium.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const _Rule(
            icon: Icons.volume_off_rounded,
            text: 'Messages and calls stop, both ways.',
          ),
          const _Rule(
            icon: Icons.visibility_off_outlined,
            text: 'They are never told. No banner, no notice.',
          ),
          const _Rule(
            icon: Icons.undo_rounded,
            text: 'Undo it any time — the row here simply goes away.',
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 13, color: AppColors.brand500),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockedTile extends ConsumerWidget {
  const _BlockedTile({
    required this.person,
    required this.now,
    required this.index,
  });

  final BlockedPerson person;
  final DateTime now;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = person.avatarUrl?.trim();

    return PulseCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          // The same comet aperture as the card, small enough to be a portrait.
          // The ring's footprint is faceSize + 2·(gap + 12) — anything smaller
          // clips the comet into a smear.
          SizedBox(
            width: 64,
            height: 64,
            child: OrbitRing(
              faceSize: 40,
              gap: 2,
              spark: index == 0,
              face: ClipOval(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: url != null && url.isNotEmpty
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              _Initials(person: person, size: 40),
                        )
                      : _Initials(person: person, size: 40),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMedium.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  person.blockedLabel(now),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.micro.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _UnblockPill(person: person),
        ],
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.person, required this.size});

  final BlockedPerson person;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Center(
        child: Text(
          person.initials,
          style: AppTypography.titleMedium.copyWith(
            fontSize: size * 0.34,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _UnblockPill extends ConsumerStatefulWidget {
  const _UnblockPill({required this.person});

  final BlockedPerson person;

  @override
  ConsumerState<_UnblockPill> createState() => _UnblockPillState();
}

class _UnblockPillState extends ConsumerState<_UnblockPill> {
  bool _busy = false;

  Future<void> _confirm() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _UnblockSheet(person: widget.person),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final failure = await ref
        .read(blockedPeopleProvider.notifier)
        .unblock(widget.person);
    if (!mounted) return;
    setState(() => _busy = false);
    PulseToast.show(
      context,
      failure == null
          ? '${widget.person.displayName} is unblocked'
          : failure.userMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _busy ? null : _confirm,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppColors.brand100),
        ),
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: AppColors.brand600,
                  ),
                )
              : Text(
                  'Unblock',
                  style: AppTypography.caption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand700,
                  ),
                ),
        ),
      ),
    );
  }
}

class _UnblockSheet extends StatelessWidget {
  const _UnblockSheet({required this.person});

  final BlockedPerson person;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE1DDF0),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Unblock ${person.displayName.split(RegExp(r'\s+')).first}?',
              textAlign: TextAlign.center,
              style: AppTypography.titleLarge.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              'Messages and calls can reach you again, and their card and photo '
              'come back to your chat list. They are not told this happened.',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                fontSize: 12.5,
                height: 1.55,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
                      ),
                    ),
                    child: const Text('Keep blocked'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: AppColors.brand600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
                      ),
                    ),
                    child: const Text('Unblock'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Nobody blocked: the page still has to be worth opening, so it says what it
/// would hold and reassures that the list is private.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        26,
        AppSpacing.screenX,
        32,
      ),
      children: [
        Center(
          child: SizedBox(
            width: 156,
            height: 156,
            child: OrbitRing(
              faceSize: 132,
              gap: 3,
              face: Container(
                width: 132,
                height: 132,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 52,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Nobody is blocked',
          textAlign: TextAlign.center,
          style: AppTypography.headlineMedium.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'When you block someone, they wait here — quietly. They are never '
          'told, nothing about them is shown anywhere else, and you can undo it '
          'with one tap.',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(
            fontSize: 12.5,
            height: 1.6,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 22),
        const _RuleCard(),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        4,
        AppSpacing.screenX,
        32,
      ),
      children: [
        const _RuleCard(),
        const SizedBox(height: 18),
        for (var i = 0; i < 4; i++) ...[
          Container(
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: AppColors.border),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not read your list',
              style: AppTypography.titleMedium.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 5),
            Text(
              failure.userMessage,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand600,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    required this.label,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}
