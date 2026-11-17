import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../chat/domain/message.dart';
import '../application/media_download_controller.dart';
import '../data/file_sharer.dart';
import '../domain/media_labels.dart';
import '../domain/media_download.dart';

/// The document / audio-file card, with a real download behind it.
///
/// Tapping it streams the file to the device (progress shown inline, in place),
/// then offers the system share sheet. **It never opens a browser**: the old
/// behaviour handed the URL to `url_launcher`, which meant a tab showing
/// Cloudinary's 401 page for any file type the CDN refuses to serve.
class FileAttachmentCard extends ConsumerWidget {
  const FileAttachmentCard({
    super.key,
    required this.message,
    required this.mine,
    this.byline,
  });

  final Message message;
  final bool mine;
  final String? byline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = message.mediaUrl ?? '';
    final name = MediaLabels.name(message);
    final state =
        ref.watch(mediaDownloadProvider)[message.id] ??
        const MediaDownloadState.idle();
    final isAudio = message.kind == MessageKind.audio;
    final fg = mine ? Colors.white : AppColors.textPrimary;
    final muted = mine
        ? Colors.white.withValues(alpha: 0.76)
        : AppColors.textMuted;

    Future<void> onTap() async {
      final messenger = ScaffoldMessenger.of(context);
      if (state.isSaved) {
        final ok = await const FileSharer().share(
          path: state.path!,
          fileName: state.fileName ?? name,
          originNote: byline,
        );
        if (!ok && context.mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Saved as ${state.fileName ?? name}')),
          );
        }
        return;
      }

      if (state.phase == MediaDownloadPhase.failed) {
        ref.read(mediaDownloadProvider.notifier).reset(message.id);
      }

      final file = await ref
          .read(mediaDownloadProvider.notifier)
          .save(messageId: message.id, url: url, fileName: name);
      if (!context.mounted) return;

      if (file == null) {
        final failure =
            ref.read(mediaDownloadProvider)[message.id]?.error ??
            "Couldn't download this file.";
        messenger.showSnackBar(
          SnackBar(
            content: Text(failure),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () =>
                  ref.read(mediaDownloadProvider.notifier).reset(message.id),
            ),
          ),
        );
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved · ${file.fileName}'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => const FileSharer().share(
              path: file.path,
              fileName: file.fileName,
              originNote: byline,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 240,
      child: Row(
        children: [
          _Badge(label: MediaLabels.extensionBadge(name), isAudio: isAudio),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  if (byline != null)
                    Text(
                      byline!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  Text(
                    _subtitle(state, message),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: state.phase == MediaDownloadPhase.failed
                          ? (mine ? const Color(0xFFFFD9D9) : AppColors.danger)
                          : muted.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Action(state: state, mine: mine, isAudio: isAudio, onTap: onTap),
        ],
      ),
    );
  }

  static String _subtitle(MediaDownloadState state, Message message) {
    final size = MediaLabels.meta(message);
    switch (state.phase) {
      case MediaDownloadPhase.downloading:
        return 'Downloading ${(state.progress * 100).round()}%';
      case MediaDownloadPhase.saved:
        return 'Saved${size != null ? ' · $size' : ''} · tap to share';
      case MediaDownloadPhase.failed:
        return 'Not available · tap to retry';
      case MediaDownloadPhase.idle:
        return size == null ? 'Tap to download' : '$size · tap to download';
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.isAudio});

  final String label;
  final bool isAudio;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: isAudio
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8E7BF6), Color(0xFF4F25C4)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF8A8A), Color(0xFFE23D4B)],
              ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D4F25C4),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9.5,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.state,
    required this.mine,
    required this.isAudio,
    required this.onTap,
  });

  final MediaDownloadState state;
  final bool mine;
  final bool isAudio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = mine
        ? Colors.white.withValues(alpha: 0.22)
        : AppColors.brand100;
    final foreground = mine ? Colors.white : AppColors.brand700;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Center(
          child: switch (state.phase) {
            MediaDownloadPhase.downloading => SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: state.progress == 0 ? null : state.progress,
                strokeWidth: 2.2,
                color: foreground,
                backgroundColor: foreground.withValues(alpha: 0.25),
              ),
            ),
            MediaDownloadPhase.saved => Icon(
              Icons.check_rounded,
              size: 18,
              color: mine ? Colors.white : const Color(0xFF16A34A),
            ),
            MediaDownloadPhase.failed => Icon(
              Icons.refresh_rounded,
              size: 18,
              color: mine ? Colors.white : AppColors.danger,
            ),
            MediaDownloadPhase.idle => Icon(
              isAudio ? Icons.download_rounded : Icons.download_rounded,
              size: 18,
              color: foreground,
            ),
          },
        ),
      ),
    );
  }
}
