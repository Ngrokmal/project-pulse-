import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../data/file_downloader.dart';
import '../domain/media_download.dart';

final fileDownloaderProvider = Provider<FileDownloader>(
  (ref) => FileDownloader(),
);

/// One download state per message id.
///
/// The card only ever reads its own entry, so a second tap on the same file
/// resumes watching the download that is already running, and two different
/// files can download side by side.
class MediaDownloadController
    extends Notifier<Map<String, MediaDownloadState>> {
  @override
  Map<String, MediaDownloadState> build() => const {};

  MediaDownloadState stateFor(String messageId) =>
      state[messageId] ?? const MediaDownloadState.idle();

  /// Downloads the attachment behind [messageId] unless it is already saved.
  /// Returns the saved file, or null when it failed (the state carries why).
  Future<DownloadedFile?> save({
    required String messageId,
    required String url,
    required String fileName,
  }) async {
    final current = stateFor(messageId);
    if (current.isBusy) return null;

    _put(messageId, const MediaDownloadState.downloading(0));
    try {
      final file = await ref
          .read(fileDownloaderProvider)
          .download(
            url: url,
            fileName: fileName,
            onProgress: (progress) =>
                _put(messageId, MediaDownloadState.downloading(progress)),
          );
      _put(
        messageId,
        MediaDownloadState.saved(path: file.path, fileName: file.fileName),
      );
      return file;
    } on AppFailure catch (failure) {
      _put(messageId, MediaDownloadState.failed(failure.userMessage));
      return null;
    } on Object {
      _put(
        messageId,
        const MediaDownloadState.failed(
          "Couldn't save the file on this device.",
        ),
      );
      return null;
    }
  }

  /// Forgets the error so the next tap tries again from scratch.
  void reset(String messageId) {
    if (!state.containsKey(messageId)) return;
    final next = Map<String, MediaDownloadState>.from(state)..remove(messageId);
    state = next;
  }

  void _put(String messageId, MediaDownloadState value) {
    state = {...state, messageId: value};
  }
}

final mediaDownloadProvider =
    NotifierProvider<MediaDownloadController, Map<String, MediaDownloadState>>(
      MediaDownloadController.new,
    );
