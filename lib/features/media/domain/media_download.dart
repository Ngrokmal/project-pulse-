/// Where a file download is right now. One value per message, so two files can
/// be downloading at once without fighting over a single spinner.
class MediaDownloadState {
  const MediaDownloadState._({
    required this.phase,
    this.progress = 0,
    this.path,
    this.fileName,
    this.error,
  });

  const MediaDownloadState.idle() : this._(phase: MediaDownloadPhase.idle);

  const MediaDownloadState.downloading(double progress)
    : this._(phase: MediaDownloadPhase.downloading, progress: progress);

  const MediaDownloadState.saved({
    required String path,
    required String fileName,
  }) : this._(
         phase: MediaDownloadPhase.saved,
         progress: 1,
         path: path,
         fileName: fileName,
       );

  const MediaDownloadState.failed(String message)
    : this._(phase: MediaDownloadPhase.failed, error: message);

  final MediaDownloadPhase phase;
  final double progress;

  /// Absolute path of the saved file, when [phase] is `saved`.
  final String? path;

  /// The name it was saved as (the original name, de-duplicated).
  final String? fileName;

  /// User-safe sentence, when [phase] is `failed`.
  final String? error;

  bool get isBusy => phase == MediaDownloadPhase.downloading;
  bool get isSaved => phase == MediaDownloadPhase.saved;
}

enum MediaDownloadPhase { idle, downloading, saved, failed }

/// The file that came out of the network.
class DownloadedFile {
  const DownloadedFile({
    required this.path,
    required this.fileName,
    required this.bytes,
  });

  final String path;
  final String fileName;
  final int bytes;
}
