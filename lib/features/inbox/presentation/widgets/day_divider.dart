import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

/// `Today` / `12 Nov 2026` above the first message of a calendar day.
class DayDivider extends StatelessWidget {
  const DayDivider({super.key, required this.when, required this.now});

  final DateTime when;
  final DateTime now;

  String get _label {
    final today =
        when.year == now.year && when.month == now.month && when.day == now.day;
    if (today) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        when.year == yesterday.year &&
        when.month == yesterday.month &&
        when.day == yesterday.day;
    if (isYesterday) return 'Yesterday';
    return DateFormat.yMMMd().format(when);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: InboxMotion.noteIn,
          curve: InboxMotion.spring,
          builder: (context, value, child) => Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: Transform.scale(scale: 0.94 + 0.06 * value, child: child),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: InboxPalette.hairline),
            ),
            child: Text(
              _label,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
