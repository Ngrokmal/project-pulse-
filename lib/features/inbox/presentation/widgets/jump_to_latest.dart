import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';
import 'inbox_pressable.dart';

/// "Jump to latest": a 38 px glass circle that only exists while you are reading
/// history, with a count badge for what arrived meanwhile.
class JumpToLatest extends StatelessWidget {
  const JumpToLatest({
    super.key,
    required this.visible,
    required this.count,
    required this.onTap,
  });

  final bool visible;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 240),
        child: AnimatedScale(
          scale: visible ? 1 : 0.9,
          duration: const Duration(milliseconds: 300),
          curve: InboxMotion.spring,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 0.25),
            duration: const Duration(milliseconds: 300),
            curve: InboxMotion.spring,
            child: InboxPressable(
              onTap: onTap,
              semanticLabel: 'Jump to latest',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      shape: BoxShape.circle,
                      border: Border.all(color: InboxPalette.hairline),
                      boxShadow: InboxPalette.roundButton,
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: InboxPalette.brand600,
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 17),
                        height: 17,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: InboxPalette.brand,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(
                            fontSize: 9.5,
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
          ),
        ),
      ),
    );
  }
}
