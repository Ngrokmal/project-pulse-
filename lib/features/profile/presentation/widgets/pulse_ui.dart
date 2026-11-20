import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The small vocabulary the card is built from.
///
/// Everything here is one visual idea used many times — a card, a row, an icon
/// chip, a switch — so the whole screen stays in one key instead of drifting
/// into a set of one-off containers.

/// A section title: small caps, wide tracking, and a hairline that fills the
/// rest of the line. The line is what makes a long page feel indexed.
class PulseEyebrow extends StatelessWidget {
  const PulseEyebrow(this.label, {super.key, this.rule = true, this.trailing});

  final String label;
  final bool rule;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.micro.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (rule) ...[
            const SizedBox(width: 10),
            const Expanded(child: _Hairline()),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.border, Color(0x00ECEAF4)],
      ),
    ),
  );
}

/// The standard white card.
class PulseCard extends StatelessWidget {
  const PulseCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.gradientHairline = false,
    this.radius = AppRadius.card,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;

  /// The identity card wears a gradient hairline; every other card wears the
  /// plain #ECEAF4 one.
  final bool gradientHairline;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.cardRadius,
        border: gradientHairline ? null : Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      foregroundDecoration: gradientHairline
          ? BoxDecoration(
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: Colors.transparent),
              gradient: const LinearGradient(
                colors: [
                  AppColors.brand300,
                  AppColors.blue300,
                  AppColors.brand200,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            )
          : null,
      child: child,
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: body,
      ),
    );
  }
}

/// The tint of an icon chip.
enum PulseTone { brand, blue, good, bad }

Color _toneFill(PulseTone tone) => switch (tone) {
  PulseTone.brand => AppColors.brand100,
  PulseTone.blue => AppColors.blue100.withValues(alpha: 0.55),
  PulseTone.good => const Color(0xFFE4F8EC),
  PulseTone.bad => const Color(0xFFFDE8EA),
};

Color _toneInk(PulseTone tone) => switch (tone) {
  PulseTone.brand => AppColors.brand600,
  PulseTone.blue => AppColors.blue500,
  PulseTone.good => AppColors.success,
  PulseTone.bad => AppColors.danger,
};

/// A 38 px rounded square holding one glyph.
class PulseIconChip extends StatelessWidget {
  const PulseIconChip({
    super.key,
    required this.icon,
    this.tone = PulseTone.brand,
    this.size = 38,
  });

  final IconData icon;
  final PulseTone tone;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _toneFill(tone),
      borderRadius: BorderRadius.circular(size * 0.34),
    ),
    child: Icon(icon, size: size * 0.52, color: _toneInk(tone)),
  );
}

/// One line of the card: icon chip, title, subtitle, and one trailing thing.
class PulseRow extends StatelessWidget {
  const PulseRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = PulseTone.brand,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final PulseTone tone;

  /// A chevron, a switch, a small meta label — whatever the row ends with.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Inside the tinted danger block the rows drop their own shadow.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: danger ? const Color(0xFFFBDDE1) : AppColors.border,
        ),
        boxShadow: danger ? null : AppShadows.card,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          PulseIconChip(icon: icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(fontSize: 14.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTypography.micro.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        borderRadius: AppRadius.cardRadius,
        onTap: onTap,
        child: body,
      ),
    );
  }
}

/// A stack of rows with the standard gap between them.
class PulseRowStack extends StatelessWidget {
  const PulseRowStack({super.key, required this.children, this.danger = false});

  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (index, child) in children.indexed) ...[
        if (index > 0) const SizedBox(height: 9),
        child,
      ],
    ],
  );
}

class PulseChevron extends StatelessWidget {
  const PulseChevron({super.key, this.icon = Icons.chevron_right_rounded});

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 19, color: const Color(0xFFB9B4CC));
}

/// The switch, with the brand gradient when it is on.
class PulseSwitch extends StatelessWidget {
  const PulseSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        width: 46,
        height: 27,
        decoration: BoxDecoration(
          gradient: value ? AppColors.primaryGradient : null,
          color: value ? null : const Color(0xFFE6E3F0),
          borderRadius: BorderRadius.circular(999),
          boxShadow: value
              ? const [
                  BoxShadow(
                    color: Color(0x337B5FED),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: AppMotion.base,
          curve: AppMotion.curve,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 21,
              height: 21,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
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

/// A Kept-close label chip.
class PulseTag extends StatelessWidget {
  const PulseTag({
    super.key,
    required this.label,
    this.onTap,
    this.plain = false,
    this.onRemove,
  });

  final String label;
  final VoidCallback? onTap;
  final bool plain;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: AppMotion.fast,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: plain ? Colors.transparent : AppColors.brand50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: plain ? AppColors.border : AppColors.brand200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.micro.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: plain ? AppColors.textMuted : AppColors.brand700,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(
                Icons.close_rounded,
                size: 13,
                color: AppColors.brand500,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

/// The floating receipt for an action: one line, check mark, gone in two ticks.
class PulseToast {
  const PulseToast._();

  static void show(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navy900,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          duration: const Duration(milliseconds: 2200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_rounded,
                size: 16,
                color: Color(0xFF7BFFB0),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: AppTypography.micro.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// The frosted disc the app bar buttons use over the hero.
class PulseGlassButton extends StatelessWidget {
  const PulseGlassButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.light = true,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final button = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withValues(alpha: 0.14)
                : AppColors.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: light
                  ? Colors.white.withValues(alpha: 0.22)
                  : AppColors.border,
            ),
          ),
          child: Icon(
            icon,
            size: 19,
            color: light ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
    final wrapped = tooltip == null
        ? button
        : Tooltip(message: tooltip!, child: button);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: wrapped,
    );
  }
}
