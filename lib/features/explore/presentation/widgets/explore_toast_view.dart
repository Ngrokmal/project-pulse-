import 'package:material_ui/material_ui.dart';

import '../../application/explore_feedback_controller.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import 'friend_avatar.dart';

/// The one message Explore shows at a time.
///
/// It carries a face (the person the sentence is about), a cyan hairline that
/// drains over 4.2 s, and at most one Undo. Motion: 280 ms in, 220 ms out — and
/// the surrounding area ignores pointers, so a toast never eats a tap meant for
/// the list underneath.
class ExploreToastView extends StatefulWidget {
  const ExploreToastView({
    super.key,
    required this.toast,
    required this.onUndo,
  });

  final ExploreToast? toast;
  final VoidCallback onUndo;

  @override
  State<ExploreToastView> createState() => _ExploreToastViewState();
}

class _ExploreToastViewState extends State<ExploreToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drain = AnimationController(
    vsync: this,
    duration: ExploreMotion.toastLife,
  );

  @override
  void initState() {
    super.initState();
    if (widget.toast != null) _drain.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant ExploreToastView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final toast = widget.toast;
    if (oldWidget.toast != toast && toast != null) {
      _drain.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _drain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toast = widget.toast;

    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: toast == null
            ? ExploreMotion.toastOut
            : ExploreMotion.toastIn,
        switchInCurve: ExploreMotion.spring,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: toast == null
            ? const SizedBox.shrink(key: ValueKey<String>('no-toast'))
            : _ToastBody(
                key: ValueKey<String>(toast.message),
                toast: toast,
                drain: _drain,
                onUndo: widget.onUndo,
              ),
      ),
    );
  }
}

class _ToastBody extends StatelessWidget {
  const _ToastBody({
    super.key,
    required this.toast,
    required this.drain,
    required this.onUndo,
  });

  final ExploreToast toast;
  final AnimationController drain;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 400;

    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 300 : 336),
      decoration: BoxDecoration(
        color: ExplorePalette.toastFill,
        borderRadius: BorderRadius.circular(ExploreMotion.toastRadius),
        boxShadow: ExplorePalette.toast,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
            child: Row(
              children: [
                _ToastChip(toast: toast),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        toast.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: ExplorePalette.toastInk,
                        ),
                      ),
                      if (toast.detail != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          toast.detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: ExplorePalette.toastSubInk,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (toast.hasUndo) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onUndo,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Text(
                        toast.undoLabel,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: ExplorePalette.toastBar,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedBuilder(
                animation: drain,
                builder: (context, _) => FractionallySizedBox(
                  widthFactor: (1 - drain.value).clamp(0.0, 1.0),
                  child: const SizedBox(
                    height: 2,
                    child: ColoredBox(color: ExplorePalette.toastBar),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToastChip extends StatelessWidget {
  const _ToastChip({required this.toast});

  final ExploreToast toast;

  @override
  Widget build(BuildContext context) {
    final person = toast.person;
    if (person != null) {
      return FriendAvatar(
        person: person,
        size: 30,
        showPresence: false,
        ring: FriendAvatarRing.none,
      );
    }

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: toast.tick
            ? const LinearGradient(
                colors: <Color>[Color(0xFF34C48E), Color(0xFF128A63)],
              )
            : const LinearGradient(
                colors: <Color>[Color(0xFFF87171), Color(0xFFC0392B)],
              ),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(
        toast.tick ? Icons.check_rounded : Icons.close_rounded,
        size: 16,
        color: Colors.white,
      ),
    );
  }
}
