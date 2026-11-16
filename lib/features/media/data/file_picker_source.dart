import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../domain/media_asset.dart';

/// Wraps the platform picker (file_picker 13 API). Returns null when the user
/// cancels. Size validation happens before any upload, using the limit for the
/// detected media type.
class FilePickerSource {
  const FilePickerSource();

  /// Photo picker (image files only).
  Future<PickedMedia?> pickImage() => pick(type: FileType.image);

  /// Any file the platform allows; the resource type is derived from the name.
  Future<PickedMedia?> pickAny() => pick();

  Future<PickedMedia?> pick({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final files = await FilePicker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
    );
    if (files.isEmpty) return null;
    final file = files.first;
    final path = file.path;
    // file_picker hands us a real path on Android/iOS; without one we cannot
    // stream bytes with progress, so say so rather than upload nothing.
    if (path == null) return null;
    final size = await File(path).length();
    return PickedMedia(
      path: path,
      fileName: file.name,
      sizeBytes: size,
      resourceType: PickedMedia.resourceTypeFor(file.name),
    );
  }
}
