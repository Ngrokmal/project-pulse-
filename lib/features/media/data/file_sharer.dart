import 'package:share_plus/share_plus.dart';

/// Hands a saved file to the system sheet: Save to Files, open in a PDF reader,
/// send it on — the user's choice, never a forced browser tab.
class FileSharer {
  const FileSharer();

  Future<bool> share({
    required String path,
    required String fileName,
    String? originNote,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, name: fileName)],
          subject: fileName,
          text: originNote ?? fileName,
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }
}
