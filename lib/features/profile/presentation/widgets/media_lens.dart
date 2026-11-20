import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile_media.dart';
import 'pulse_ui.dart';

/// Media: the last things this account actually sent.
///
/// Not a decorative mosaic — the tiles come from `messages.media_url`, and when
/// there is nothing to show the lens says so and offers the gallery instead.
class MediaLens extends StatelessWidget {
  const MediaLens({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onOpen,
    required this.onOpenGallery,
    required this.onKeepOriginals,
  });

  final AsyncValue<List<ProfileMedia>> state;
  final VoidCallback onRetry;
  final ValueChanged<ProfileMedia> onOpen;
  final VoidCallback onOpenGallery;
  final VoidCallback onKeepOriginals;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        state.when(
          loading: () => const _MosaicSkeleton(),
          error: (_, _) => _MosaicError(onRetry: onRetry),
          data: (items) => items.isEmpty
              ? const _MosaicEmpty()
              : _Mosaic(items: items, onOpen: onOpen),
        ),
        const SizedBox(height: 14),
        PulseRowStack(
          children: [
            PulseRow(
              icon: Icons.photo_library_outlined,
              title: 'Everything you both shared',
              subtitle: 'Photos, clips and voice notes',
              trailing: const PulseChevron(),
              onTap: onOpenGallery,
            ),
            PulseRow(
              icon: Icons.ios_share_rounded,
              tone: PulseTone.good,
              title: 'Keep the originals',
              subtitle: 'Exports at the quality they were sent',
              onTap: onKeepOriginals,
            ),
          ],
        ),
      ],
    );
  }
}

class _Mosaic extends StatelessWidget {
  const _Mosaic({required this.items, required this.onOpen});

  final List<ProfileMedia> items;
  final ValueChanged<ProfileMedia> onOpen;

  @override
  Widget build(BuildContext context) {
    // Two columns; the first tile spans both, exactly like the card.
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final cell = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (index, item) in items.indexed)
              SizedBox(
                width: index == 0 ? constraints.maxWidth : cell,
                height: index == 0 ? cell * 0.86 : cell * 0.72,
                child: _Tile(item: item, onTap: () => onOpen(item), wide: index == 0),
              ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onTap, required this.wide});

  final ProfileMedia item;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final preview = item.previewUrl;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preview != null)
              Image.network(
                preview,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _Wash(index: item.id.hashCode),
              )
            else
              _Wash(index: item.id.hashCode),
            // The shade, so white captions survive any photo.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x99000000)],
                  stops: [0.45, 1],
                ),
              ),
            ),
            if (item.isVideo || item.isAudio)
              Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.42),
                  ),
                  child: Icon(
                    item.isVideo
                        ? Icons.play_arrow_rounded
                        : Icons.graphic_eq_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Text(
                item.label,
                style: AppTypography.micro.copyWith(
                  color: Colors.white,
                  fontSize: wide ? 11.5 : 10.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A brand wash for tiles whose file has no thumbnail.
class _Wash extends StatelessWidget {
  const _Wash({required this.index});

  final int index;

  static const List<List<Color>> _washes = <List<Color>>[
    <Color>[Color(0xFF7B3FF2), Color(0xFF4818A8), Color(0xFF191B73)],
    <Color>[Color(0xFF9B8AF5), Color(0xFF7B5FED)],
    <Color>[Color(0xFF3768D2), Color(0xFF191B73)],
    <Color>[Color(0xFFB8A2FA), Color(0xFF5F3FDC)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _washes[index.abs() % _washes.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          size: 22,
          color: Color(0x66FFFFFF),
        ),
      ),
    );
  }
}

class _MosaicSkeleton extends StatelessWidget {
  const _MosaicSkeleton();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      final cell = (constraints.maxWidth - gap) / 2;
      return Column(
        children: [
          _block(constraints.maxWidth, cell * 0.86),
          const SizedBox(height: gap),
          Row(
            children: [
              _block(cell, cell * 0.72),
              const SizedBox(width: gap),
              _block(cell, cell * 0.72),
            ],
          ),
        ],
      );
    },
  );

  Widget _block(double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.brand50,
      borderRadius: BorderRadius.circular(AppRadius.sm + 4),
    ),
  );
}

class _MosaicEmpty extends StatelessWidget {
  const _MosaicEmpty();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
    decoration: BoxDecoration(
      color: AppColors.brand50,
      borderRadius: AppRadius.cardRadius,
      border: Border.all(color: const Color(0xFFEDE9FA)),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.photo_camera_back_outlined,
          size: 26,
          color: AppColors.brand400,
        ),
        const SizedBox(height: 10),
        Text(
          'Nothing sent yet',
          style: AppTypography.titleMedium.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          'The first photo or voice note you send lands here.',
          textAlign: TextAlign.center,
          style: AppTypography.micro.copyWith(
            fontSize: 11.5,
            height: 1.5,
            color: AppColors.textMuted,
          ),
        ),
      ],
    ),
  );
}

class _MosaicError extends StatelessWidget {
  const _MosaicError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: AppRadius.cardRadius,
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        Text(
          'The gallery could not be read.',
          style: AppTypography.titleMedium.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
