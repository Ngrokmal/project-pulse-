import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// The one primary CTA of the product (§2 discipline: one gradient action per
/// screen). Handles disabled, loading, pressed and focus states.
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.height = 56,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final double height;
  final bool expand;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.reducedMotion(context);
    final scale = (_pressed && _enabled && !reduceMotion) ? 0.975 : 1.0;

    final content = AnimatedScale(
      scale: scale,
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      child: Opacity(
        opacity: _enabled ? 1 : 0.55,
        child: Container(
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          padding: widget.expand
              ? null
              : const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: AppRadius.pillRadius,
            boxShadow: _enabled ? AppShadows.glowPrimary : null,
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(AppColors.onPrimary),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.label, style: AppTypography.buttonLabel),
                      if (widget.icon != null) ...[
                        const SizedBox(width: 8),
                        Icon(widget.icon, size: 19, color: AppColors.onPrimary),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _enabled ? widget.onPressed : null,
        child: content,
      ),
    );
  }
}

/// Secondary action: lavender fill, no gradient.
class SoftButton extends StatelessWidget {
  const SoftButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: AppColors.cardAlt,
          shape: const StadiumBorder(),
          overlayColor: AppColors.brand200,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.brand600),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTypography.buttonLabel.copyWith(
                color: enabled ? AppColors.brand600 : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
