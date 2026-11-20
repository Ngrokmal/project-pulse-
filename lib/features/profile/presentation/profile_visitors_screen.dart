import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../application/profile_visits_controller.dart';
import '../domain/profile_visitor.dart';
import 'widgets/orbit_ring.dart';
import 'widgets/pulse_ui.dart';

/// **Profile views.** Who opened this card, and when.
///
/// It is a short list on purpose. One row per person, the time of their last
/// open, and how many times they have come back — no device, no duration, no
/// map. The server is the only one who knows it (`profile_visitors()`, 0015) and
/// the only one who can read it, so nothing here can be inferred or replayed
/// from a cache.
class ProfileVisitorsScreen extends ConsumerWidget {
  const ProfileVisitorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitors = ref.watch(profileVisitorsProvider);

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
                _Header(
                  count: visitors.value?.length,
                  onRefresh: () async {
                    await ref.read(profileVisitorsProvider.notifier).refresh();
                  },
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppMotion.base,
                    switchInCurve: AppMotion.curve,
                    child: visitors.when(
                      loading: () => const _Loading(),
                      error: (error, _) => _Failed(
                        failure: error is AppFailure
                            ? error
                            : const ServerFailure(),
                        onRetry: () => ref.invalidate(profileVisitorsProvider),
                      ),
                      data: (rows) => KeyedSubtree(
                        key: ValueKey(rows.isEmpty ? 'empty' : 'list'),
                        child: rows.isEmpty
                            ? const _Empty()
                            : _List(visitors: rows),
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

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.11, 0.34],
          colors: [AppColors.navy800, AppColors.navy900, AppColors.bg],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.count, required this.onRefresh});

  final int? count;
  final Future<void> Function() onRefresh;

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
                  'Profile views',
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
                      ? 'Reading your visitors…'
                      : count == 0
                      ? 'Nobody yet'
                      : '$count ${count == 1 ? 'person' : 'people'} looked at your card',
                  style: AppTypography.micro.copyWith(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          _RoundButton(
            icon: Icons.refresh_rounded,
            label: 'Refresh',
            onTap: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white.withValues(alpha: 0.10),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.visitors});

  final List<ProfileVisitor> visitors;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
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
        for (final (index, visitor) in visitors.indexed) ...[
          _VisitorTile(
            visitor: visitor,
            now: now,
            index: index,
            onOpen: () => context.push('/u/${visitor.id}'),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Only you can see this list. Nobody is told they were here.',
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

/// What this page is, in three lines — including the two things it deliberately
/// does not do.
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
                  Icons.visibility_outlined,
                  size: 16,
                  color: AppColors.brand600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'How views work',
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
            icon: Icons.touch_app_rounded,
            text: 'A view is counted when someone opens your card — not a scroll.',
          ),
          const _Rule(
            icon: Icons.person_off_outlined,
            text: 'Blocked people disappear from here, in both directions.',
          ),
          const _Rule(
            icon: Icons.lock_outline_rounded,
            text: 'Only you can read this. No one is told they were here.',
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

class _VisitorTile extends StatelessWidget {
  const _VisitorTile({
    required this.visitor,
    required this.now,
    required this.index,
    required this.onOpen,
  });

  final ProfileVisitor visitor;
  final DateTime now;
  final int index;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final url = visitor.avatarUrl?.trim();
    final fresh = now.difference(visitor.lastSeenAt).inHours < 1;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.cardRadius,
        onTap: onOpen,
        child: PulseCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: OrbitRing(
                  faceSize: 40,
                  gap: 2,
                  spark: fresh && index == 0,
                  face: ClipOval(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: url == null || url.isEmpty
                          ? _Initials(visitor: visitor, size: 40)
                          : Image.network(
                              url,
                              fit: BoxFit.cover,
                              frameBuilder: (context, child, frame, sync) =>
                                  sync || frame != null
                                  ? child
                                  : _Initials(visitor: visitor, size: 40),
                              errorBuilder: (_, _, _) =>
                                  _Initials(visitor: visitor, size: 40),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            visitor.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleMedium.copyWith(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (visitor.atHandle.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              visitor.atHandle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.micro.copyWith(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      visitor.describe(now),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.micro.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand600.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFFB8B2C9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.visitor, required this.size});

  final ProfileVisitor visitor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand500, AppColors.brand700],
        ),
      ),
      child: Text(
        visitor.initials,
        style: AppTypography.micro.copyWith(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        24,
        AppSpacing.screenX,
        32,
      ),
      children: [
        Center(
          child: SizedBox(
            width: 132,
            height: 132,
            child: OrbitRing(
              faceSize: 96,
              gap: 4,
              spark: true,
              face: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.brand400, AppColors.brand700],
                  ),
                ),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: Icon(
                    Icons.visibility_outlined,
                    size: 38,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'No one has looked yet',
          textAlign: TextAlign.center,
          style: AppTypography.titleLarge.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'When somebody opens your card, they appear here with the time. '
          'You are the only one who can see it.',
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
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: AppColors.border),
              ),
            ),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
        child: PulseErrorState(failure: failure, onRetry: onRetry),
      ),
    );
  }
}
