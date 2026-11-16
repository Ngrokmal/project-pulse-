import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../../../core/motion/pulse_icons.dart';
import '../../../../core/motion/pulse_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// One row of the notifications sheet.
///
/// There is no notifications table in the schema yet, so nothing is invented
/// here: the app passes an empty list and the sheet shows its quiet empty
/// state. The moment a source exists it renders with the same motion.
class PulseNoticeData {
  const PulseNoticeData({
    required this.title,
    required this.body,
    required this.when,
    required this.icon,
    this.danger = false,
  });

  final String title;
  final String body;
  final String when;
  final List<PulseShape> icon;
  final bool danger;
}

/// The bottom sheet from the reference: it drops in on a spring, each notice
/// arrives on its own beat (blur → sharp, up → settled, 140 ms + 90 ms each),
/// and on close they leave one after another before the sheet falls.
class PulseNotificationSheet extends StatefulWidget {
  const PulseNotificationSheet({
    super.key,
    required this.open,
    required this.notices,
    required this.onClose,
  });

  final bool open;
  final List<PulseNoticeData> notices;
  final VoidCallback onClose;

  @override
  State<PulseNotificationSheet> createState() => _PulseNotificationSheetState();
}

class _PulseNotificationSheetState extends State<PulseNotificationSheet>
    with TickerProviderStateMixin {
  late final AnimationController _sheet = AnimationController(
    vsync: this,
    duration: PulseMotion.sheetIn,
  );

  /// Notices leave first (55 ms apart, 340 ms each), then the sheet falls.
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: 55 * (widget.notices.length.clamp(1, 8) - 1) + 340,
    ),
  );

  late final Animation<double> _spring = CurvedAnimation(
    parent: _sheet,
    curve: PulseMotion.spring,
  );

  bool _entering = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      _entering = true;
      _sheet.forward();
    }
  }

  @override
  void didUpdateWidget(PulseNotificationSheet old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) {
      _entering = true;
      _leaving = false;
      _exit.value = 0;
      _sheet.forward();
    } else if (!widget.open && old.open) {
      _entering = false;
      _leaving = true;
      _exit.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() => _leaving = false);
        _sheet.reverse();
      });
    }
  }

  @override
  void dispose() {
    _sheet.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dragging = _sheet.value > 0.001 || widget.open;

    return IgnorePointer(
      ignoring: !dragging,
      child: Stack(
        children: [
          // backdrop: 32 % ink with a 2 px blur
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _spring,
              builder: (context, _) => Opacity(
                opacity: _spring.value.clamp(0.0, 1.0),
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 2 * _spring.value,
                      sigmaY: 2 * _spring.value,
                    ),
                    child: Container(color: const Color(0x52141228)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _spring,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, 360 * (1 - _spring.value)),
                child: child,
              ),
              child: _sheetBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetBody() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.76,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
          // 36 px on the bottom corners, as in the reference.
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x802A0E6B),
            offset: Offset(0, -20),
            blurRadius: 50,
            spreadRadius: -20,
          ),
        ],
      ),
      padding: const EdgeInsets.only(top: 10, left: 18, right: 18, bottom: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4.5,
              margin: const EdgeInsets.only(top: 4, bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE4E1F0),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Notifications',
              style: AppTypography.titleMedium.copyWith(
                fontSize: 17,
                letterSpacing: -0.2,
                color: const Color(0xFF141452),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.notices.isEmpty)
            _empty()
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < widget.notices.length; i++)
                      _NoticeTile(
                        key: ValueKey(i),
                        index: i,
                        data: widget.notices[i],
                        enter: _entering,
                        exit: _leaving,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9FE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0EDFA)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            size: 26,
            color: Color(0xFFA9A7B4),
          ),
          const SizedBox(height: 8),
          Text(
            'No notifications yet',
            style: AppTypography.caption.copyWith(
              color: const Color(0xFF7C7990),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeTile extends StatefulWidget {
  const _NoticeTile({
    super.key,
    required this.index,
    required this.data,
    required this.enter,
    required this.exit,
  });

  final int index;
  final PulseNoticeData data;
  final bool enter;
  final bool exit;

  @override
  State<_NoticeTile> createState() => _NoticeTileState();
}

class _NoticeTileState extends State<_NoticeTile>
    with TickerProviderStateMixin {
  late final AnimationController _in;
  late final AnimationController _out;

  @override
  void initState() {
    super.initState();
    final delay =
        PulseMotion.noticeInDelay.inMilliseconds +
        widget.index * PulseMotion.noticeStagger.inMilliseconds;
    _in = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: delay + PulseMotion.noticeIn.inMilliseconds,
      ),
    );
    _out = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds:
            widget.index * PulseMotion.noticeOutStagger.inMilliseconds +
            PulseMotion.noticeOut.inMilliseconds,
      ),
    );
    if (widget.enter) _in.forward();
  }

  @override
  void didUpdateWidget(_NoticeTile old) {
    super.didUpdateWidget(old);
    if (widget.enter && !old.enter) _in.forward(from: 0);
    if (widget.exit && !old.exit) _out.forward(from: 0);
    if (!widget.exit && old.exit) _out.value = 0;
  }

  @override
  void dispose() {
    _in.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delay =
        PulseMotion.noticeInDelay.inMilliseconds +
        widget.index * PulseMotion.noticeStagger.inMilliseconds;
    final total = delay + PulseMotion.noticeIn.inMilliseconds;

    final enter = CurvedAnimation(
      parent: _in,
      curve: Interval(delay / total, 1, curve: PulseMotion.easeOut),
    );

    final outDelay = widget.index * PulseMotion.noticeOutStagger.inMilliseconds;
    final outTotal = outDelay + PulseMotion.noticeOut.inMilliseconds;
    final exit = CurvedAnimation(
      parent: _out,
      curve: Interval(outDelay / outTotal, 1, curve: const Cubic(0.4, 0, 1, 1)),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_in, _out]),
      builder: (context, _) {
        final e = enter.value;
        final x = exit.value;
        if (x >= 1) return const SizedBox.shrink();

        final opacity = (e * (1 - x)).clamp(0.0, 1.0);
        final dy = (1 - e) * 18 - x * 10;
        final scale = (0.97 + 0.03 * e) * (1 - 0.02 * x);
        final blurPx = (1 - e) * 6 + x * 5;

        Widget tile = _tile();

        if (blurPx > 0.05) {
          tile = ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: blurPx / 2,
              sigmaY: blurPx / 2,
            ),
            child: tile,
          );
        }

        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: tile,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile() {
    final data = widget.data;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9FE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0EDFA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: data.danger ? const Color(0xFFFDECEE) : AppColors.brand100,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: PulseIcon(
              paths: data.icon,
              size: 17,
              color: data.danger ? AppColors.danger : AppColors.brand600,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: AppTypography.caption.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF141452),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.body,
                  style: AppTypography.caption.copyWith(
                    fontSize: 12.5,
                    height: 1.45,
                    color: const Color(0xFF7C7990),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            data.when,
            style: AppTypography.caption.copyWith(
              fontSize: 11,
              color: const Color(0xFFA9A7B4),
            ),
          ),
        ],
      ),
    );
  }
}
