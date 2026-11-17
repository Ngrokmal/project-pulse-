import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../chat/domain/message.dart';
import '../domain/media_asset.dart';
import '../domain/media_labels.dart';
import 'file_attachment_card.dart';
import 'image_viewer.dart';
import 'video_player_view.dart';

/// Renders an attachment inside a chat bubble.
///
/// Rules that matter:
///  • the **name is the sender's original file name** (`messages.media_name`),
///    never something parsed out of a Cloudinary URL,
///  • every card says who sent it to whom — `Saiful → Mahmoud`,
///  • photos open the in-app viewer, videos open the in-app player, files open
///    the real URL. Nothing here is a dead button.
class MediaBubble extends StatelessWidget {
  const MediaBubble({
    super.key,
    required this.message,
    required this.mine,
    this.myName,
    this.peerName,
  });

  final Message message;
  final bool mine;

  /// The two people in the direct chat — `myName → peerName` on my files and the
  /// reverse on theirs.
  final String? myName;
  final String? peerName;

  String? get _byline =>
      MediaLabels.byline(mine: mine, myName: myName, peerName: peerName);

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl;
    if (url == null || url.isEmpty) {
      return Text(
        'This attachment is no longer available.',
        style: TextStyle(
          fontSize: 13.5,
          fontStyle: FontStyle.italic,
          color: mine ? Colors.white70 : AppColors.textMuted,
        ),
      );
    }

    final name = MediaLabels.name(message);
    final byline = _byline;

    return switch (message.kind) {
      MessageKind.image => _PhotoCard(
        url: url,
        name: name,
        byline: byline,
        mine: mine,
        onTap: () =>
            ImageViewer.show(context, url: url, title: name, byline: byline),
      ),
      MessageKind.video => _VideoCard(
        url: url,
        name: name,
        byline: byline,
        duration: MediaLabels.duration(message),
        size: MediaLabels.meta(message),
        mine: mine,
        onTap: () => VideoPlayerView.show(
          context,
          url: url,
          title: name,
          byline: byline,
        ),
      ),
      MessageKind.audio || MessageKind.forceAudio || MessageKind.file =>
        FileAttachmentCard(message: message, mine: mine, byline: byline),
      MessageKind.text => const SizedBox.shrink(),
    };
  }
}

/// A photo: the picture, then its real name and who sent it to whom.
class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.url,
    required this.name,
    required this.byline,
    required this.mine,
    required this.onTap,
  });

  final String url;
  final String name;
  final String? byline;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : AppColors.textPrimary;
    final muted = mine
        ? Colors.white.withValues(alpha: 0.76)
        : AppColors.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 226,
              height: 168,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const _PhotoPlaceholder();
                    },
                    errorBuilder: (_, _, _) =>
                        _Missing(label: 'This photo did not load', mine: mine),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.32),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.open_in_full_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
        if (byline != null)
          Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 2),
            child: Text(
              byline!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
      ],
    );
  }
}

/// A video: a deliberate dark tile with a play affordance, plus its real name.
class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.url,
    required this.name,
    required this.byline,
    required this.duration,
    required this.size,
    required this.mine,
    required this.onTap,
  });

  final String url;
  final String name;
  final String? byline;
  final String? duration;
  final String? size;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = mine
        ? Colors.white.withValues(alpha: 0.76)
        : AppColors.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 232,
              height: 132,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF241A4A), Color(0xFF0E0A22)],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 22,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 26,
                        color: AppColors.brand700,
                      ),
                    ),
                  ),
                  if (duration != null)
                    Positioned(
                      right: 9,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          duration!,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        _NameRow(name: name, mine: mine, icon: Icons.videocam_rounded),
        if (byline != null || size != null)
          Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 2),
            child: Text(
              [?byline, ?size].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
      ],
    );
  }
}

class _NameRow extends StatelessWidget {
  const _NameRow({required this.name, required this.mine, required this.icon});

  final String name;
  final bool mine;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: mine ? Colors.white70 : AppColors.brand600),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: mine ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB79CFF), Color(0xFF7E5CEC)],
        ),
      ),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.label, required this.mine});

  final String label;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mine ? Colors.white.withValues(alpha: 0.14) : AppColors.brand100,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 22,
              color: mine ? Colors.white70 : AppColors.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: mine ? Colors.white70 : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kept for the file-size formatting used by callers outside this file.
String humanSize(int bytes) => PickedMedia.humanSize(bytes);
