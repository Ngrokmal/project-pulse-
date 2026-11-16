import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

/// "You're offline — messages will send the moment you're back".
/// It expands to 40 px and collapses to nothing; the thread never jumps because
/// the height is animated, not the layout.
class OfflineBar extends StatelessWidget {
  const OfflineBar({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: InboxMotion.slowBar,
      curve: InboxMotion.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 260),
        child: visible
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: const BoxDecoration(
                  color: InboxPalette.offlineBg,
                  border: Border(bottom: BorderSide(color: Color(0x38D08A2A))),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: InboxPalette.offlineInk,
                    ),
                    SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        "You're offline — messages send the moment you're back",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: InboxPalette.offlineInk,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}
