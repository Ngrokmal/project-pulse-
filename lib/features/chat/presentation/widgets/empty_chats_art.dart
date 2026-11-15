import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The "no conversations yet" screen.
///
/// Three soft brand-coloured rings breathe behind a chat bubble, then a second
/// bubble slides in — the app's own colours, no assets, and it stops animating
/// when Settings → Reduce motion is on.
class EmptyChatsArt extends ConsumerStatefulWidget {
  const EmptyChatsArt({super.key, required this.onStartChat});

  final VoidCallback onStartChat;

  @override
  ConsumerState<EmptyChatsArt> createState() => _EmptyChatsArtState();
}

class _EmptyChatsArtState extends ConsumerState<EmptyChatsArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = reduceMotionNotifier.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 190,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _RingsPainter(
                  progress: reduceMotion ? 0.35 : _controller.value,
                ),
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: Center(
                    child: _Bubbles(
                      progress: reduceMotion ? 0.5 : _controller.value,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'No conversations yet',
            textAlign: TextAlign.center,
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a chat or a group and it lands right here. Messages arrive '
            'instantly, and stay readable when you are offline.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: widget.onStartChat,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand600,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_rounded, size: 18),
            label: const Text('Start a chat'),
          ),
        ],
      ),
    );
  }
}

class _Bubbles extends StatelessWidget {
  const _Bubbles({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    // A gentle up/down float, and the second bubble slides in slightly later.
    final float = math.sin(progress * math.pi * 2) * 5;
    final entry = ((progress * 2) % 1.0);
    return Transform.translate(
      offset: Offset(0, float),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand600.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.chat_bubble_rounded,
              color: AppColors.onPrimary,
              size: 44,
            ),
          ),
          Positioned(
            right: 6,
            bottom: 4,
            child: Opacity(
              opacity: 0.55 + 0.45 * entry,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.brand100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.brand200, width: 1.5),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  size: 20,
                  color: AppColors.brand500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 3; i++) {
      // Each ring breathes with a third of a cycle of offset.
      final phase = (progress + i / 3) % 1.0;
      final radius = 42 + (size.width / 2 - 46) * phase;
      final opacity = (1 - phase) * 0.30;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = (i.isEven ? AppColors.brand400 : AppColors.brand300)
            .withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
    }
    // A soft halo behind the bubbles.
    canvas.drawCircle(
      center,
      size.width * 0.30,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                AppColors.brand300.withValues(alpha: 0.22),
                AppColors.brand100.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(center: center, radius: size.width * 0.3),
            ),
    );
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
