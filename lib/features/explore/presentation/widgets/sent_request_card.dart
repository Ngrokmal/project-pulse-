import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_palette.dart';
import '../../domain/friend_request.dart';
import '../../domain/friend_state.dart';
import 'explore_card_shell.dart';
import 'explore_pills.dart';
import 'explore_pressable.dart';
import 'row_entrance.dart';
import 'friend_avatar.dart';

/// A request I sent that nobody has answered yet.
///
/// Waiting has to *look* like waiting: a warm PENDING pill with a slow shimmer
/// and a hairline travelling left to right, so the row reads as "in flight"
/// rather than "done".
class SentRequestCard extends StatelessWidget {
  const SentRequestCard({
    super.key,
    required this.request,
    required this.onCancel,
    this.entranceDelay = Duration.zero,
  });

  final FriendRequest request;
  final VoidCallback onCancel;
  final Duration entranceDelay;

  @override
  Widget build(BuildContext context) {
    final person = request.person;
    final age = DateTime.now().difference(request.sentAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: RowEntrance(
        delay: entranceDelay,
        child: ExploreCardShell(
          state: FriendState.requestedByMe,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FriendAvatar(person: person),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.15,
                            color: ExplorePalette.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        ExploreMetaLine(
                          parts: <String>[
                            'Sent ${_waiting(age)}',
                            person.atHandle,
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const PendingPill(),
                ],
              ),
              const SizedBox(height: 10),
              const _TravellingLine(),
              const SizedBox(height: 9),
              Align(
                alignment: Alignment.centerRight,
                child: ExplorePressable(
                  onTap: onCancel,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: ExplorePalette.brand100,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: ExplorePalette.brand500.withValues(alpha: 0.16),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Cancel request',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: ExplorePalette.brand700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _waiting(Duration age) {
    if (age.inMinutes < 1) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) {
      return '${age.inHours}h ago';
    }
    if (age.inDays == 1) return 'yesterday';
    return '${age.inDays}d ago';
  }
}

class _TravellingLine extends StatefulWidget {
  const _TravellingLine();

  @override
  State<_TravellingLine> createState() => _TravellingLineState();
}

class _TravellingLineState extends State<_TravellingLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reducedMotion(context);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 2,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: ExplorePalette.pendingLine.withValues(alpha: 0.16),
                ),
              ),
              if (!reduce)
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return FractionallySizedBox(
                      widthFactor: 0.38,
                      alignment: Alignment(-1 + 2.4 * _controller.value, 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              ExplorePalette.pendingLine.withValues(alpha: 0),
                              ExplorePalette.pendingLine,
                              ExplorePalette.pendingLine.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
