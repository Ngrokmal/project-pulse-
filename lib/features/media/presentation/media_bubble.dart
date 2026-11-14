import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../chat/domain/message.dart';
import '../domain/media_asset.dart';

/// Renders an attachment inside a chat bubble. Images load from Cloudinary;
/// video/raw/audio show a real file card that opens the actual URL — no fake
/// player and no dead button.
class MediaBubble extends StatelessWidget {
  const MediaBubble({super.key, required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl;
    if (url == null) {
      return Text(
        'Attachment unavailable',
        style: AppTypography.bodyMedium.copyWith(
          color: mine ? AppColors.onPrimary : AppColors.textMuted,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (message.kind == MessageKind.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.34,
            maxWidth: MediaQuery.sizeOf(context).width * 0.62,
          ),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              final total = progress.expectedTotalBytes;
              final value = total == null
                  ? null
                  : progress.cumulativeBytesLoaded / total;
              return SizedBox(
                height: 140,
                width: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    value: value,
                    strokeWidth: 2,
                    color: mine ? AppColors.onPrimary : AppColors.brand500,
                  ),
                ),
              );
            },
            errorBuilder: (_, _, _) => _FileCard(
              label: 'Photo',
              detail: 'Tap to open',
              mine: mine,
              onOpen: () => _open(url),
            ),
          ),
        ),
      );
    }

    final isVideo = message.kind == MessageKind.video;
    final label = isVideo
        ? 'Video'
        : _fileNameFrom(url) ??
              (message.kind == MessageKind.audio ? 'Audio' : 'File');
    final detail = message.mediaBytes == null
        ? 'Tap to open'
        : PickedMedia.humanSize(message.mediaBytes!);

    return _FileCard(
      label: label,
      detail: detail,
      mine: mine,
      icon: isVideo
          ? Icons.play_circle_fill_rounded
          : message.kind == MessageKind.audio
          ? Icons.graphic_eq_rounded
          : Icons.insert_drive_file_rounded,
      onOpen: () => _open(url),
    );
  }

  static String? _fileNameFrom(String url) {
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments == null || segments.isEmpty) return null;
    final last = segments.last;
    return last.isEmpty ? null : Uri.decodeComponent(last);
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.label,
    required this.detail,
    required this.mine,
    required this.onOpen,
    this.icon = Icons.insert_drive_file_rounded,
  });

  final String label;
  final String detail;
  final bool mine;
  final VoidCallback onOpen;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final fg = mine ? AppColors.onPrimary : AppColors.brand700;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: fg),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: mine
                        ? AppColors.onPrimary.withValues(alpha: 0.75)
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.open_in_new_rounded, size: 13, color: fg),
        ],
      ),
    );
  }
}
