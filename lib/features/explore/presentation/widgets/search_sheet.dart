import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/state_views.dart';
import '../../application/explore_feedback_controller.dart';
import '../../application/explore_providers.dart';
import '../../application/friend_actions_controller.dart';
import '../../application/people_search_controller.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import '../../domain/friend_state.dart';
import '../../domain/people_search.dart';
import '../../domain/person.dart';
import 'explore_skeleton.dart';
import 'explore_search_bar.dart';
import 'explore_toast_host.dart';
import 'friend_avatar.dart';
import 'search_lens_mascot.dart';
import 'search_result_tile.dart';

/// The invite link the sheet copies. One constant, so it can be swapped for the
/// real deep link in one place when the route exists.
const String exploreInviteLink = 'https://pulse.app/invite';

/// Opens the search sheet.
///
/// It grows out of the header (scale from the top, 480 ms on the spring) instead
/// of sliding over the whole app, because the reference's sheet is an extension
/// of the search field, not a new place.
Future<void> openExploreSearch(
  BuildContext context, {
  String initialQuery = '',
  bool autofocus = false,
}) {
  final reduce = AppMotion.reducedMotion(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close search',
    barrierColor: Colors.transparent,
    transitionDuration: reduce ? Duration.zero : ExploreMotion.sheetOpen,
    pageBuilder: (context, _, _) =>
        ExploreSearchSheet(initialQuery: initialQuery, autofocus: autofocus),
    transitionBuilder: (context, animation, _, child) {
      if (reduce) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: ExploreMotion.spring,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          alignment: const Alignment(0, -0.9),
          child: child,
        ),
      );
    },
  );
}

/// The sheet itself: idle → loading → results / empty, one explicit submit at a
/// time.
class ExploreSearchSheet extends ConsumerStatefulWidget {
  const ExploreSearchSheet({
    super.key,
    this.initialQuery = '',
    this.autofocus = false,
  });

  final String initialQuery;
  final bool autofocus;

  @override
  ConsumerState<ExploreSearchSheet> createState() => _ExploreSearchSheetState();
}

class _ExploreSearchSheetState extends ConsumerState<ExploreSearchSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    if (widget.initialQuery.trim().isNotEmpty) {
      // Opened from the header with a query already typed: ask once, now.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(widget.initialQuery);
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final state = ref.read(peopleSearchProvider);
    if (_controller.text.trim().isEmpty && state is! SearchIdle) {
      ref.read(peopleSearchProvider.notifier).reset();
    } else {
      setState(() {});
    }
  }

  void _submit(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    ref.read(peopleSearchProvider.notifier).submit(query);
  }

  void _pickSuggestion(String name) {
    _controller.text = name;
    _submit(name);
  }

  Future<void> _copyInvite(String name) async {
    final text = name.isEmpty
        ? 'Come find me on Pulse — $exploreInviteLink'
        : '$name is not on Pulse yet. Invite them: $exploreInviteLink';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ref
        .read(exploreFeedbackProvider.notifier)
        .show(
          ExploreToast(
            message: 'Invite link copied',
            detail: name.isEmpty ? exploreInviteLink : 'Send it to “$name”',
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(peopleSearchProvider);
    final networkSize = ref.watch(exploreNetworkSizeProvider).value ?? 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Material(
        color: ExplorePalette.shellTop,
        child: Stack(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xFFF6F3FE),
                    Color(0xFFFBFAFE),
                    ExplorePalette.shellBottom,
                  ],
                  stops: <double>[0, 0.34, 1],
                ),
              ),
              child: const SizedBox.expand(),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: ExploreSearchBar(
                      controller: _controller,
                      onSubmit: _submit,
                      autofocus: widget.autofocus,
                      showBack: true,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  _HintLine(state: state),
                  Expanded(child: _buildBody(state, networkSize)),
                ],
              ),
            ),
            const ExploreToastHost(bottomInset: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SearchUiState state, int networkSize) {
    return switch (state) {
      SearchIdle() => _IdleView(
        onPick: _pickSuggestion,
        onInvite: () => _copyInvite(''),
      ),
      SearchLoading(:final query) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
        children: [
          _SearchingLine(query: query, networkSize: networkSize),
          const SizedBox(height: 10),
          const ExploreSkeleton(rows: 3),
        ],
      ),
      SearchResults(:final result) => _ResultsView(result: result),
      SearchEmpty(:final result, :final nearMisses) => _EmptyView(
        result: result,
        nearMisses: nearMisses,
        onPick: _pickSuggestion,
        onInvite: () => _copyInvite(result.query),
      ),
      SearchFailed(:final failure) => Center(
        child: PulseErrorState(
          failure: failure,
          onRetry: () => _submit(_controller.text),
        ),
      ),
    };
  }
}

class _HintLine extends StatelessWidget {
  const _HintLine({required this.state});

  final SearchUiState state;

  @override
  Widget build(BuildContext context) {
    final text = switch (state) {
      SearchIdle() => 'Type a name — nothing is fetched until you ask',
      SearchLoading() => 'One request to the server',
      SearchResults() => 'Sorted by match · Add sends the request',
      SearchEmpty() => 'Nothing matched — nothing was sent either',
      SearchFailed() => 'The search did not finish',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 12,
            color: ExplorePalette.placeholder,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: ExploreMotion.press,
              child: Text(
                text,
                key: ValueKey<String>(text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: ExplorePalette.placeholder,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchingLine extends StatelessWidget {
  const _SearchingLine({required this.query, required this.networkSize});

  final String query;
  final int networkSize;

  @override
  Widget build(BuildContext context) {
    final size = networkSize > 0 ? _thousands(networkSize) : 'everyone';
    return Row(
      children: [
        const Icon(
          Icons.search_rounded,
          size: 15,
          color: ExplorePalette.brand500,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Searching $size people for “$query”…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: ExplorePalette.metaInk,
            ),
          ),
        ),
      ],
    );
  }

  static String _thousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

class _ResultsView extends ConsumerWidget {
  const _ResultsView({required this.result});

  final PeopleSearch result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(friendActionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '${result.hits.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: ExplorePalette.brand700,
                        ),
                      ),
                      TextSpan(
                        text: result.hits.length == 1
                            ? ' person matches “'
                            : ' people match “',
                      ),
                      TextSpan(
                        text: result.query,
                        style: const TextStyle(color: ExplorePalette.ink),
                      ),
                      const TextSpan(text: '”'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.15,
                    color: ExplorePalette.ink,
                  ),
                ),
              ),
              if (result.networkSize > 0)
                Text(
                  'of ${_SearchingLine._thousands(result.networkSize)}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: ExplorePalette.placeholder,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            itemCount: result.hits.length + 1,
            itemBuilder: (context, index) {
              if (index == result.hits.length) {
                return _SheetFooter(
                  count: result.hits.length,
                  networkSize: result.networkSize,
                  onInvite: () => Clipboard.setData(
                    const ClipboardData(
                      text: 'Come find me on Pulse — $exploreInviteLink',
                    ),
                  ),
                );
              }
              final hit = result.hits[index];
              return SearchResultTile(
                key: ValueKey<String>(hit.person.id),
                hit: hit,
                actions: actions,
                entranceDelay: ExploreMotion.rowStagger * (index.clamp(0, 6)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SheetFooter extends StatelessWidget {
  const _SheetFooter({
    required this.count,
    required this.networkSize,
    required this.onInvite,
  });

  final int count;
  final int networkSize;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    if (count >= 6) return const SizedBox(height: 8);
    final size = networkSize > 0
        ? _SearchingLine._thousands(networkSize)
        : 'everyone';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFFBFAFF), Color(0xFFF7F4FE)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ExplorePalette.brand500.withValues(alpha: 0.26),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '$count',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: ExplorePalette.brand700,
                    ),
                  ),
                  TextSpan(
                    text: count == 1
                        ? ' of $size cleared the 50 % letter rule — the rest scored lower.'
                        : ' of $size cleared the 50 % letter rule — the rest scored lower.',
                  ),
                ],
              ),
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7C7890),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onInvite,
              child: Container(
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: ExplorePalette.brand500.withValues(alpha: 0.24),
                  ),
                ),
                child: const Text(
                  'Invite a friend instead',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: ExplorePalette.brand700,
                    height: 1,
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

class _IdleView extends ConsumerWidget {
  const _IdleView({required this.onPick, required this.onInvite});

  final ValueChanged<String> onPick;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider).value ?? const <Person>[];
    final online = friends
        .where(presenceIsOnline)
        .take(9)
        .toList(growable: false);
    final recent = friends.take(6).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
      children: [
        if (online.isNotEmpty) ...[
          const _SectionLabel('Active now'),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: online.length,
              separatorBuilder: (_, _) => const SizedBox(width: 11),
              itemBuilder: (context, i) => _PersonChip(
                person: online[i],
                onTap: () => onPick(online[i].displayName),
                stacked: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (recent.isNotEmpty) ...[
          const _SectionLabel('In your circle'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final person in recent)
                _PersonChip(
                  person: person,
                  onTap: () => onPick(person.displayName),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ExplorePalette.brand500.withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: ExplorePalette.brand400,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Search runs on the server, once, when you press the button or '
                  'hit search — so a slow name costs one request, not fifteen.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6C6784),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFFF3EEFF), Color(0xFFEDE7FE)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: ExplorePalette.brand500.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pulse is better with your people',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                        color: Color(0xFF2A1D57),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Copy a link and drop it in any chat.',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6C6784),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onInvite,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: ExplorePalette.brand,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: ExplorePalette.primaryButton,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Copy link',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 9),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          color: ExplorePalette.placeholder,
        ),
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.person,
    required this.onTap,
    this.stacked = false,
  });

  final Person person;
  final VoidCallback onTap;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return SizedBox(
        width: 58,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            children: [
              FriendAvatar(person: person, size: 50),
              const SizedBox(height: 6),
              Text(
                person.displayName.split(' ').first,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: ExplorePalette.chipInk,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ExplorePalette.hairline),
          boxShadow: ExplorePalette.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FriendAvatar(person: person, size: 24, showPresence: false),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                person.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF26232F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.result,
    required this.nearMisses,
    required this.onPick,
    required this.onInvite,
  });

  final PeopleSearch result;
  final List<SearchHit> nearMisses;
  final ValueChanged<String> onPick;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final trimmed = result.query.trim();
    final shorter = trimmed.length > 4
        ? trimmed.substring(0, 4)
        : (trimmed.length > 2 ? trimmed.substring(0, 2) : null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
      children: [
        const SizedBox(height: 14),
        const Center(child: SearchLensMascot(query: '')),
        const SizedBox(height: 4),
        const Text(
          'Even my lens is squinting',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.25,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: ExplorePalette.ink,
          ),
        ),
        const SizedBox(height: 7),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              const TextSpan(text: 'No one by '),
              TextSpan(
                text: '“${result.query}”',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: ExplorePalette.brand700,
                ),
              ),
              const TextSpan(
                text: ' — not even half of those letters matched anyone here.',
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.55,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7C7890),
          ),
        ),
        if (nearMisses.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'CLOSEST NAMES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: ExplorePalette.placeholder,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final hit in nearMisses)
                _PersonChip(
                  person: hit.person,
                  onTap: () => onPick(hit.person.displayName),
                ),
            ],
          ),
        ],
        if (shorter != null) ...[
          const SizedBox(height: 14),
          Center(
            child: GestureDetector(
              onTap: () => onPick(shorter),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: ExplorePalette.brand100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ExplorePalette.brand500.withValues(alpha: 0.2),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Try “$shorter”',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: ExplorePalette.brand700,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onInvite,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: ExplorePalette.brand100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ExplorePalette.brand500.withValues(alpha: 0.24),
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 15,
                  color: ExplorePalette.brand700,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'Invite “$trimmed” to Pulse',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: ExplorePalette.brand700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Re-exported so the tile can be built elsewhere without importing the sheet.
typedef ExploreResultTile = SearchResultTile;

/// Kept for the tab: the same rule the sheet explains, in one sentence.
String friendStateLabel(FriendState state) => switch (state) {
  FriendState.none => 'Add',
  FriendState.requestedByMe => 'Requested',
  FriendState.requestedMe => 'Asked you',
  FriendState.friend => 'Friends',
  FriendState.self => 'That’s you',
};
