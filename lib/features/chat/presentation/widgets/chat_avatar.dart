import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// One avatar for both kinds of conversation.
///
/// A real profile picture is shown when there is one (and the initials are used
/// while it loads, or if it fails — a chat list must never show a broken image),
/// groups get the brand gradient plus a group badge so the two are never
/// confused at a glance.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.label,
    required this.isGroup,
    this.imageUrl,
    this.size = 52,
    this.showOnlineDot = false,
    this.online = false,
  });

  final String label;
  final bool isGroup;
  final String? imageUrl;
  final double size;
  final bool showOnlineDot;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;

    Widget fallback(String initials) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: isGroup
            ? AppColors.primaryGradient
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brand500, AppColors.brand700],
              ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTypography.titleMedium.copyWith(
          color: AppColors.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );

    return Semantics(
      label: isGroup ? 'Group $label' : label,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: hasImage
                  ? Image.network(
                      url,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => fallback(label),
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : fallback(label),
                    )
                  : fallback(label),
            ),
            if (isGroup)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    size: 12,
                    color: AppColors.brand700,
                  ),
                ),
              ),
            if (showOnlineDot && !isGroup)
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: online ? AppColors.success : AppColors.textMuted,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
