import '../../chat/domain/message.dart';
import 'media_asset.dart';

/// What a media bubble is allowed to *call* a file.
///
/// The name comes from `messages.media_name` — the file name the sender's device
/// had. A Cloudinary URL is a random public id and must never be shown as a name;
/// when an older row has no stored name we fall back to a human label ("Photo"),
/// never to the URL.
class MediaLabels {
  MediaLabels._();

  static String name(Message message) {
    final stored = message.mediaName?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return _kindLabel(message.kind);
  }

  static String _kindLabel(MessageKind kind) => switch (kind) {
    MessageKind.text => 'Message',
    MessageKind.image => 'Photo',
    MessageKind.video => 'Video',
    MessageKind.audio => 'Voice note',
    MessageKind.forceAudio => 'Force Audio',
    MessageKind.file => 'File',
  };

  /// `Saiful → Mahmoud`: who sent it and who received it, in that order.
  ///
  /// [myName] is the signed-in user, [peerName] the other side of a direct chat,
  /// so the arrow always points from the sender to the receiver regardless of
  /// which side of the thread you are reading.
  static String? byline({
    required bool mine,
    String? myName,
    String? peerName,
  }) {
    final from = mine ? myName : peerName;
    final to = mine ? peerName : myName;
    if (from == null || to == null) return null;
    final cleanFrom = from.trim();
    final cleanTo = to.trim();
    if (cleanFrom.isEmpty || cleanTo.isEmpty) return null;
    return '$cleanFrom → $cleanTo';
  }

  /// `JPG`, `PDF`, `M4A` — the badge on the file card.
  static String extensionBadge(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return 'FILE';
    final ext = fileName.substring(dot + 1).toUpperCase();
    return ext.length > 4 ? ext.substring(0, 4) : ext;
  }

  /// `12.4 MB` when the size is known, else the kind label.
  static String? meta(Message message) {
    final bytes = message.mediaBytes;
    if (bytes == null || bytes <= 0) return null;
    return PickedMedia.humanSize(bytes);
  }

  /// `0:42` for a video with a known length.
  static String? duration(Message message) {
    final ms = message.durationMs;
    if (ms == null || ms <= 0) return null;
    final total = (ms / 1000).round();
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
