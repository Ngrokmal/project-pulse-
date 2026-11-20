import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../core/error/app_failure.dart';
import '../domain/profile_photo.dart';

/// Turns "these bytes + this crop" into the one square the app stores.
///
/// The studio preview and the uploaded file run through the *same*
/// [PhotoCrop], so what the person framed is what everyone else sees. Doing the
/// crop here (instead of storing four numbers and hoping every surface applies
/// them) means inbox, explore and chat need no crop logic at all.
class ProfilePhotoRasterizer {
  const ProfilePhotoRasterizer();

  /// A square PNG at [PhotoCrop.outputEdge]. Throws [ValidationFailure] when the
  /// file is not a decodable image.
  Future<Uint8List> rasterize({
    required Uint8List bytes,
    required PhotoCrop crop,
  }) async {
    final ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
    } catch (_) {
      throw const ValidationFailure(
        'photo',
        'That file is not a readable image.',
      );
    }

    try {
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final source = crop.sourceRect(size);
      final edge = PhotoCrop.outputEdge.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        source,
        Rect.fromLTWH(0, 0, edge, edge),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(
        PhotoCrop.outputEdge,
        PhotoCrop.outputEdge,
      );
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      output.dispose();
      if (data == null) {
        throw const ValidationFailure(
          'photo',
          'That photo could not be prepared.',
        );
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// The natural size of a picked file, so the preview can pan correctly.
  Future<Size> measure(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      return size;
    } catch (_) {
      return Size.zero;
    }
  }
}
