import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';

/// Tap feedback with the reference's spring: scale .9 on press, spring back on
/// release. Transform-only, so it never re-lays-out anything.
class InboxPressable extends StatefulWidget {
  const InboxPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.pressedScale = 0.9,
    this.behavior = HitTestBehavior.opaque,
    this.semanticLabel,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final double pressedScale;
  final HitTestBehavior behavior;
  final String? semanticLabel;

  @override
  State<InboxPressable> createState() => _InboxPressableState();
}

class _InboxPressableState extends State<InboxPressable> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: widget.onTap == null ? null : (_) => _set(true),
        onTapUp: widget.onTap == null ? null : (_) => _set(false),
        onTapCancel: widget.onTap == null ? null : () => _set(false),
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 140),
          curve: InboxMotion.spring,
          child: widget.child,
        ),
      ),
    );
  }
}
