import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloudinary_uploader.dart';
import '../domain/media_asset.dart';

final cloudinaryUploaderProvider = Provider<CloudinaryUploader>(
  (ref) => CloudinaryUploader(),
);

/// Progress of the attachment currently being uploaded.
/// The UI renders the real fraction, so a slow connection visibly moves slowly.
class UploadState {
  const UploadState({
    required this.fileName,
    required this.progress,
    this.error,
  });

  final String fileName;
  final double progress;
  final String? error;

  bool get isDone => progress >= 1 && error == null;

  UploadState copyWith({double? progress, String? error}) => UploadState(
    fileName: fileName,
    progress: progress ?? this.progress,
    error: error,
  );
}

class MediaUploadController extends Notifier<UploadState?> {
  @override
  UploadState? build() => null;

  /// Uploads [media] and returns the resulting asset. Failures are rethrown as
  /// typed AppFailures after being exposed through [state].
  Future<CloudinaryAsset> upload(PickedMedia media) async {
    state = UploadState(fileName: media.fileName, progress: 0);
    try {
      final asset = await ref
          .read(cloudinaryUploaderProvider)
          .upload(
            media,
            onProgress: (p) {
              final current = state;
              if (current == null) return;
              state = current.copyWith(progress: p);
            },
          );
      state = UploadState(fileName: media.fileName, progress: 1);
      return asset;
    } catch (e) {
      state = UploadState(
        fileName: media.fileName,
        progress: 0,
        error: e.toString(),
      );
      rethrow;
    }
  }

  void clear() => state = null;
}

final mediaUploadProvider =
    NotifierProvider<MediaUploadController, UploadState?>(
      MediaUploadController.new,
    );
