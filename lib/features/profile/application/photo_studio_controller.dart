import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../data/profile_photo_rasterizer.dart';
import '../../chat/application/chat_controller.dart';
import '../../explore/application/explore_providers.dart';
import '../domain/profile_photo.dart';
import 'profile_controller.dart';

/// The studio's own state: the file that was picked, how it is framed, and
/// whether it is on its way to storage.
class PhotoStudioState {
  const PhotoStudioState({
    this.bytes,
    this.mimeType,
    this.imageSize = Size.zero,
    this.crop = PhotoCrop.identity,
    this.busy = false,
    this.error,
  });

  final Uint8List? bytes;
  final String? mimeType;
  final Size imageSize;
  final PhotoCrop crop;
  final bool busy;
  final String? error;

  bool get hasPhoto => bytes != null;

  PhotoStudioState copyWith({
    Uint8List? bytes,
    String? mimeType,
    Size? imageSize,
    PhotoCrop? crop,
    bool? busy,
    String? error,
    bool clearError = false,
    bool clearPhoto = false,
  }) => PhotoStudioState(
    bytes: clearPhoto ? null : (bytes ?? this.bytes),
    mimeType: clearPhoto ? null : (mimeType ?? this.mimeType),
    imageSize: clearPhoto ? Size.zero : (imageSize ?? this.imageSize),
    crop: clearPhoto ? PhotoCrop.identity : (crop ?? this.crop),
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Drives the photo studio sheet.
///
/// It owns framing and the two writes (save, remove) and nothing else: the
/// upload itself lives in the repository, so this class is testable without a
/// network and the sheet is a pure view of [PhotoStudioState].
class PhotoStudioController extends Notifier<PhotoStudioState> {
  static const _rasterizer = ProfilePhotoRasterizer();

  @override
  PhotoStudioState build() => const PhotoStudioState();

  /// Called after the platform picker returns a file.
  void accept({
    required Uint8List bytes,
    required String mimeType,
    required Size imageSize,
  }) {
    final problem = ProfilePhoto.validate(bytes: bytes, mimeType: mimeType);
    if (problem != null) {
      state = state.copyWith(error: problem);
      return;
    }
    state = PhotoStudioState(
      bytes: bytes,
      mimeType: mimeType,
      imageSize: imageSize,
      crop: PhotoCrop.identity,
    );
  }

  void zoomTo(double value) {
    if (!state.hasPhoto) return;
    state = state.copyWith(
      crop: state.crop.zoomedTo(value).rebasedFor(state.imageSize),
    );
  }

  void panBy(Offset delta) {
    if (!state.hasPhoto) return;
    state = state.copyWith(
      crop: state.crop.pannedBy(delta, imageSize: state.imageSize),
    );
  }

  /// Throws the pick away — the studio's empty state (initials).
  void useInitials() {
    state = const PhotoStudioState();
  }

  void reset() => state = const PhotoStudioState();

  /// Crops, uploads, and tells the card about its new face.
  Future<AppFailure?> save({required String userId}) async {
    final picked = state;
    if (!picked.hasPhoto) return null;
    state = picked.copyWith(busy: true, clearError: true);
    try {
      final square = await _rasterizer.rasterize(
        bytes: picked.bytes!,
        crop: picked.crop,
      );
      final url = await ref
          .read(profileRepositoryProvider)
          .uploadAvatar(
            userId: userId,
            bytes: square,
            mimeType: 'image/png',
            takenAt: DateTime.now(),
          );
      ref.read(profileControllerProvider.notifier).applyAvatar(url);
      _spreadThePhoto();
      state = const PhotoStudioState();
      return null;
    } on AppFailure catch (f) {
      state = state.copyWith(busy: false, error: f.userMessage);
      return f;
    } catch (_) {
      state = state.copyWith(
        busy: false,
        error: 'That photo could not be saved. Try again.',
      );
      return const ServerFailure();
    }
  }

  /// The photo lives in one column, so every list that paints a face has to be
  /// told the column moved — otherwise the card shows the new picture while the
  /// chat list keeps the old one until the next launch.
  void _spreadThePhoto() {
    ref.invalidate(conversationsProvider);
    ref.invalidate(friendsProvider);
  }

  /// Back to initials. Also clears the column, so nobody is left looking at a
  /// photo its owner believes they removed.
  Future<AppFailure?> remove({
    required String userId,
    String? existingUrl,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .removeAvatar(userId: userId, existingUrl: existingUrl);
      ref.read(profileControllerProvider.notifier).applyAvatar(null);
      _spreadThePhoto();
      state = const PhotoStudioState();
      return null;
    } on AppFailure catch (f) {
      state = state.copyWith(busy: false, error: f.userMessage);
      return f;
    } catch (_) {
      state = state.copyWith(
        busy: false,
        error: 'That photo could not be removed. Try again.',
      );
      return const ServerFailure();
    }
  }
}

final photoStudioProvider =
    NotifierProvider<PhotoStudioController, PhotoStudioState>(
      PhotoStudioController.new,
    );
