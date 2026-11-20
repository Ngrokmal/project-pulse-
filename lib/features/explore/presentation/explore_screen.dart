import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/widgets/state_views.dart';
import '../application/explore_feedback_controller.dart';
import '../application/explore_providers.dart';
import '../application/friend_actions_controller.dart';
import '../domain/explore_motion.dart';
import '../domain/explore_palette.dart';
import '../domain/explore_section.dart';
import '../domain/friend_request.dart';
import '../domain/person.dart';
import 'explore_chat.dart';
import 'widgets/explore_backdrop.dart';
import 'widgets/explore_empty_state.dart';
import 'widgets/explore_header.dart';
import 'widgets/explore_segments.dart';
import 'widgets/explore_skeleton.dart';
import 'widgets/explore_toast_host.dart';
import 'widgets/friend_tile.dart';
import 'widgets/incoming_request_card.dart';
import 'widgets/search_sheet.dart';
import 'widgets/sent_request_card.dart';

/// Explore — requests, sent and the circle, behind one tab, with a search that
/// only runs when it is asked to.
///
/// One `IndexedStack` keeps all three lists alive so switching segments never
/// re-runs a query; every list is a `ListView.builder`, so a hundred friends cost
/// the same as ten. Motion lives in the widgets; this screen only decides what is
/// on screen and what a tap means.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();

  ExploreSection _section = ExploreSection.requests;

  /// Rows that already finished their exit animation. They stay hidden until the
  /// provider refreshes, so a slow network never resurrects a card the user just
  /// dealt with.
  final Set<String> _dismissed = <String>{};

  /// Friendships made in this session — they get the NEW chip and the
  /// "just became friends" line, exactly like the reference.
  final Set<String> _justAdded = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(incomingRequestsProvider)
      ..invalidate(sentRequestsProvider)
      ..invalidate(friendsProvider)
      ..invalidate(friendsCountProvider);
    try {
      await Future.wait<void>(<Future<void>>[
        ref.read(incomingRequestsProvider.future),
        ref.read(sentRequestsProvider.future),
        ref.read(friendsProvider.future),
        ref.read(friendsCountProvider.future),
      ]);
    } on Object {
      // The error view of each section says what happened; a pull-to-refresh that
      // throws must not also throw at the gesture layer.
    }
  }

  Future<void> _openSearch({String initialQuery = ''}) {
    return openExploreSearch(
      context,
      initialQuery: initialQuery,
      autofocus: initialQuery.isEmpty,
    );
  }

  void _accept(FriendRequest request) {
    setState(() => _justAdded.add(request.person.id));
    ref.read(friendActionsProvider).accept(request);
  }

  void _decline(FriendRequest request) {
    ref.read(friendActionsProvider).decline(request);
  }

  void _cancelSent(FriendRequest request) {
    ref.read(friendActionsProvider).cancel(request);
  }

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(exploreCountsProvider);

    return Stack(
      children: [
        const Positioned.fill(child: ExploreBackdrop()),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              ExploreHeader(
                pendingRequests: counts.requests,
                friends: counts.friends,
                searchController: _searchController,
                onSubmitSearch: (query) => _openSearch(initialQuery: query),
                onOpenSearch: () => _openSearch(),
                onFilter: () => ref
                    .read(exploreFeedbackProvider.notifier)
                    .show(
                      const ExploreToast(
                        message: 'Filters are coming',
                        detail: 'Mutual friends · online now · new on Pulse',
                      ),
                    ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ExploreSegments(
                  selected: _section,
                  counts: counts,
                  onSelect: (section) {
                    if (section != _section) {
                      setState(() => _section = section);
                    }
                  },
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: IndexedStack(
                  index: _section.index,
                  children: <Widget>[
                    _RequestsSection(
                      dismissed: _dismissed,
                      onAccept: _accept,
                      onDecline: _decline,
                      onRefresh: _refresh,
                      onFindPeople: _openSearch,
                    ),
                    _SentSection(
                      dismissed: _dismissed,
                      onCancel: _cancelSent,
                      onRefresh: _refresh,
                      onFindPeople: _openSearch,
                    ),
                    _FriendsSection(
                      justAdded: _justAdded,
                      onRefresh: _refresh,
                      onFindPeople: _openSearch,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const ExploreToastHost(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────── sections

class _RequestsSection extends ConsumerWidget {
  const _RequestsSection({
    required this.dismissed,
    required this.onAccept,
    required this.onDecline,
    required this.onRefresh,
    required this.onFindPeople,
  });

  final Set<String> dismissed;
  final ValueChanged<FriendRequest> onAccept;
  final ValueChanged<FriendRequest> onDecline;
  final Future<void> Function() onRefresh;
  final VoidCallback onFindPeople;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(incomingRequestsProvider);

    return requests.when(
      skipLoadingOnRefresh: true,
      data: (list) {
        final visible = list
            .where((r) => !dismissed.contains(r.id))
            .toList(growable: false);

        return RefreshIndicator(
          onRefresh: onRefresh,
          color: ExplorePalette.brand600,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              8,
              20,
              ExploreMotion.listBottomPadding,
            ),
            children: [
              const _SectionHead(
                heading: 'Friend requests',
                trailingKey: 'requests',
              ),
              const SizedBox(height: 4),
              const _SwipeHint(),
              const SizedBox(height: 10),
              if (visible.isEmpty)
                const ExploreEmptyState(
                  key: ValueKey<String>('empty-requests'),
                  title: 'All caught up',
                  body:
                      'No friend requests waiting. New ones land here the moment '
                      'someone asks — and you can swipe each one away.',
                )
              else
                for (var i = 0; i < visible.length; i++)
                  IncomingRequestCard(
                    key: ValueKey<String>(visible[i].id),
                    request: visible[i],
                    entranceDelay: ExploreMotion.rowStagger * (i.clamp(0, 6)),
                    onAccept: () => onAccept(visible[i]),
                    onDecline: () => onDecline(visible[i]),
                  ),
            ],
          ),
        );
      },
      loading: () => const _SectionSkeleton(heading: 'Friend requests'),
      error: (failure, _) =>
          _SectionError(failure: failure, onRetry: onRefresh),
    );
  }
}

class _SentSection extends ConsumerWidget {
  const _SentSection({
    required this.dismissed,
    required this.onCancel,
    required this.onRefresh,
    required this.onFindPeople,
  });

  final Set<String> dismissed;
  final ValueChanged<FriendRequest> onCancel;
  final Future<void> Function() onRefresh;
  final VoidCallback onFindPeople;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sent = ref.watch(sentRequestsProvider);

    return sent.when(
      skipLoadingOnRefresh: true,
      data: (list) {
        final visible = list
            .where((r) => !dismissed.contains(r.id))
            .toList(growable: false);

        return RefreshIndicator(
          onRefresh: onRefresh,
          color: ExplorePalette.brand600,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              8,
              20,
              ExploreMotion.listBottomPadding,
            ),
            children: [
              const _SectionHead(
                heading: 'Waiting for them',
                trailingKey: 'sent',
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                ExploreEmptyState(
                  key: const ValueKey<String>('empty-sent'),
                  title: 'Nothing in flight',
                  body:
                      'Requests you send and cancel live here, so you always know '
                      'where you stand with someone.',
                  actionLabel: 'Find someone',
                  onAction: onFindPeople,
                )
              else
                for (var i = 0; i < visible.length; i++)
                  SentRequestCard(
                    key: ValueKey<String>(visible[i].id),
                    request: visible[i],
                    entranceDelay: ExploreMotion.rowStagger * (i.clamp(0, 6)),
                    onCancel: () => onCancel(visible[i]),
                  ),
            ],
          ),
        );
      },
      loading: () => const _SectionSkeleton(heading: 'Waiting for them'),
      error: (failure, _) =>
          _SectionError(failure: failure, onRetry: onRefresh),
    );
  }
}

class _FriendsSection extends ConsumerStatefulWidget {
  const _FriendsSection({
    required this.justAdded,
    required this.onRefresh,
    required this.onFindPeople,
  });

  final Set<String> justAdded;
  final Future<void> Function() onRefresh;
  final VoidCallback onFindPeople;

  @override
  ConsumerState<_FriendsSection> createState() => _FriendsSectionState();
}

class _FriendsSectionState extends ConsumerState<_FriendsSection> {
  /// Who is being opened right now — one tap per person, never two requests.
  final Set<String> _opening = <String>{};

  Future<void> _open(Person person) async {
    if (!_opening.add(person.id)) return;
    setState(() {});
    try {
      await openExploreChat(context, ref, person);
    } finally {
      if (mounted) {
        _opening.remove(person.id);
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final count = ref.watch(friendsCountProvider).value ?? 0;
    final justAdded = widget.justAdded;
    final onRefresh = widget.onRefresh;
    final onFindPeople = widget.onFindPeople;

    return friends.when(
      skipLoadingOnRefresh: true,
      data: (list) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          color: ExplorePalette.brand600,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              8,
              20,
              ExploreMotion.listBottomPadding,
            ),
            itemCount: list.isEmpty ? 2 : list.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SectionHead(
                    heading: 'Your circle',
                    trailingKey: 'friends',
                    trailing: FriendCountPill(count: count),
                  ),
                );
              }
              if (list.isEmpty) {
                return ExploreEmptyState(
                  key: const ValueKey<String>('empty-friends'),
                  title: 'Your circle starts here',
                  body:
                      'Accept a request, or search for someone by name. The people '
                      'you add will live here, with an honest presence line.',
                  actionLabel: 'Find people',
                  onAction: onFindPeople,
                );
              }
              final person = list[index - 1];
              return FriendTile(
                key: ValueKey<String>(person.id),
                person: person,
                isNew: justAdded.contains(person.id),
                busy: _opening.contains(person.id),
                entranceDelay:
                    ExploreMotion.rowStagger * ((index - 1).clamp(0, 6)),
                onMessage: () => _open(person),
              );
            },
          ),
        );
      },
      loading: () => const _SectionSkeleton(heading: 'Your circle'),
      error: (failure, _) =>
          _SectionError(failure: failure, onRetry: onRefresh),
    );
  }
}

// ──────────────────────────────────────────────────────────────── chrome

class _SectionHead extends ConsumerWidget {
  const _SectionHead({
    required this.heading,
    required this.trailingKey,
    this.trailing,
  });

  final String heading;
  final String trailingKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(exploreCountsProvider);
    final meta = switch (trailingKey) {
      'requests' =>
        counts.requests == 0 ? 'all caught up' : '${counts.requests} waiting',
      'sent' => counts.sent == 0 ? 'nothing pending' : '${counts.sent} sent',
      _ => null,
    };

    final icon = switch (trailingKey) {
      'requests' => Icons.person_add_alt_1_rounded,
      'sent' => Icons.outbox_rounded,
      _ => Icons.diversity_3_rounded,
    };

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            gradient: ExplorePalette.brand,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x335F3FDC),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 13, color: Colors.white),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            heading,
            style: const TextStyle(
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: ExplorePalette.ink,
            ),
          ),
        ),
        if (trailing != null)
          trailing!
        else if (meta != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: ExplorePalette.brand500.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(ExploreMotion.pillRadius),
            ),
            child: Text(
              meta,
              style: const TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: ExplorePalette.brand700,
              ),
            ),
          ),
      ],
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '← decline      ·      accept →',
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: Color(0xFFB8A2FA),
        ),
      ),
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({required this.heading});

  final String heading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      children: [
        _SectionHead(heading: heading, trailingKey: 'none'),
        const SizedBox(height: 14),
        const ExploreSkeleton(rows: 3),
      ],
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.failure, required this.onRetry});

  /// Riverpod hands the error up as `Object`. Every Explore read throws an
  /// [AppFailure]; anything unexpected is reported as an unavailable feature
  /// instead of tearing the tab down.
  final Object failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final error = failure;
    return PulseErrorState(
      failure: error is AppFailure
          ? error
          : const FeatureUnavailableFailure('explore'),
      onRetry: () => onRetry(),
    );
  }
}
