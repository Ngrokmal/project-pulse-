import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/media_download.dart';

/// Fetches an attachment and writes it into the app's own files directory.
///
/// The point of this class is that **nothing opens a browser**. The bytes are
/// streamed to disk with real progress, and a Cloudinary 401 (its "Untrusted
/// File Access" page) becomes a typed [MediaFailure] instead of a web page the
/// user cannot leave.
class FileDownloader {
  FileDownloader({http.Client? client, AppLogger? logger})
    : _client = client ?? http.Client(),
      _log = logger ?? AppLogger('media');

  /// A phone is not a file server: 64 MiB is the ceiling we will write.
  static const int maxBytes = 64 * 1024 * 1024;

  static const String folderName = 'Pulse files';

  final http.Client _client;
  final AppLogger _log;

  /// Downloads [url] and saves it under [fileName] (the original name the sender
  /// had), reporting real byte progress in 0..1.
  Future<DownloadedFile> download({
    required String url,
    required String fileName,
    String fallbackName = 'attachment',
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw const MediaFailure(MediaFailureReason.badUrl);
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(http.Request('GET', uri));
    } on SocketException catch (error) {
      throw NetworkFailure(detail: error.message);
    } on TimeoutException {
      throw const NetworkFailure(timedOut: true);
    } on http.ClientException catch (error) {
      throw NetworkFailure(detail: error.message);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      // Cloudinary's "Untrusted File Access": the row is fine, the CDN refuses.
      _log.warning(
        'download_refused',
        data: {'status': response.statusCode, 'host': uri.host},
      );
      await response.stream.drain<void>();
      throw const MediaFailure(MediaFailureReason.unavailable);
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw ServerFailure(statusCode: response.statusCode);
    }

    final declared = response.contentLength ?? 0;
    if (declared > maxBytes) {
      await response.stream.drain<void>();
      throw const MediaFailure(MediaFailureReason.tooLarge);
    }

    final directory = await _targetDirectory();
    final safeName = uniqueName(
      sanitizeName(fileName, fallback: fallbackName),
      existing: await _namesIn(directory),
    );
    final file = File('${directory.path}/$safeName');
    final sink = file.openWrite();

    var written = 0;
    try {
      await for (final chunk in response.stream) {
        written += chunk.length;
        if (written > maxBytes) {
          throw const MediaFailure(MediaFailureReason.tooLarge);
        }
        sink.add(chunk);
        if (onProgress != null) {
          onProgress(declared > 0 ? (written / declared).clamp(0.0, 1.0) : 0.0);
        }
      }
      await sink.flush();
      await sink.close();
    } on MediaFailure {
      await _abort(sink, file);
      rethrow;
    } on Object catch (error) {
      await _abort(sink, file);
      _log.error('download_write_failed', error: error);
      throw const MediaFailure(MediaFailureReason.write);
    }

    if (written == 0) {
      await _abort(sink, file, alreadyClosed: true);
      throw const MediaFailure(MediaFailureReason.unavailable);
    }

    onProgress?.call(1);
    _log.info('download_ok', data: {'bytes': written});
    return DownloadedFile(path: file.path, fileName: safeName, bytes: written);
  }

  Future<void> _abort(
    IOSink sink,
    File file, {
    bool alreadyClosed = false,
  }) async {
    try {
      if (!alreadyClosed) await sink.close();
    } on Object {
      // Nothing to close.
    }
    try {
      if (file.existsSync()) await file.delete();
    } on Object {
      // Leaving a partial file behind is not worth another failure.
    }
  }

  /// Downloads first (public/Downloads), then the app's documents directory.
  /// Both are app-writable without any storage permission on modern Android.
  Future<Directory> _targetDirectory() async {
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } on Object {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/$folderName');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Set<String>> _namesIn(Directory directory) async {
    try {
      return {
        await for (final entity in directory.list())
          if (entity is File) entity.uri.pathSegments.last,
      };
    } on Object {
      return const {};
    }
  }

  /// Strips anything a filesystem would object to, keeps the extension, and
  /// never returns an empty name.
  static String sanitizeName(String raw, {String fallback = 'attachment'}) {
    var name = raw.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_').trim();
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    name = name.replaceAll(RegExp(r'^\.+'), '');
    if (name.isEmpty) name = fallback;
    if (!name.contains('.')) {
      // Keep a usable stem for the badge and for the OS to guess a type.
      name = '$name.${_extensionHint(fallback)}';
    }
    if (name.length > 120) {
      final dot = name.lastIndexOf('.');
      final ext = dot > 0 ? name.substring(dot) : '';
      final stem = dot > 0 ? name.substring(0, dot) : name;
      name = '${stem.substring(0, 120 - ext.length)}$ext';
    }
    return name;
  }

  static String _extensionHint(String fallback) =>
      fallback.contains('.') ? fallback.split('.').last : 'bin';

  /// `report.pdf`, `report (2).pdf`, `report (3).pdf` … so a second download of
  /// the same name never overwrites the first.
  static String uniqueName(String name, {required Set<String> existing}) {
    if (!existing.contains(name)) return name;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 2; i < 1000; i++) {
      final candidate = '$stem ($i)$ext';
      if (!existing.contains(candidate)) return candidate;
    }
    return '$stem (${DateTime.now().millisecondsSinceEpoch})$ext';
  }
}
