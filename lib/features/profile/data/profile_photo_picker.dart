import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

import '../domain/profile_photo.dart';

/// The bytes a person just picked, measured once so the studio never has to
/// guess the aspect ratio it is framing.
class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;

  ui.Size get size => ui.Size(width.toDouble(), height.toDouble());
}

/// Wraps the platform picker for the studio.
///
/// Camera and gallery are the same call with a different source, and the decode
/// happens here — the sheet receives a measured photo, never a path it must
/// probe in a build method.
class ProfilePhotoPicker {
  ProfilePhotoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<PickedPhoto?> fromGallery() => _pick(ImageSource.gallery);

  Future<PickedPhoto?> fromCamera() => _pick(ImageSource.camera);

  Future<PickedPhoto?> _pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      // The bucket stores one square, so asking for a large square first is
      // free quality: the studio still lets people reframe.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 92,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final decoded = await _decode(bytes);
    if (decoded == null) return null;
    return PickedPhoto(
      bytes: bytes,
      mimeType: _mimeFor(file),
      width: decoded.$1,
      height: decoded.$2,
    );
  }

  /// Width and height of the first frame, or null when the bytes are not an
  /// image this device can read.
  Future<(int, int)?> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = (image.width, image.height);
      image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  static String _mimeFor(XFile file) {
    final declared = file.mimeType;
    if (declared != null && ProfilePhoto.allowedMimeTypes.contains(declared)) {
      return declared;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
