import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/force_audio_alert.dart';

/// Downloads an alert's audio to a private cache file, reporting **real**
/// received bytes. The receiver must fetch the file, not stream it: §5 requires
/// "Checking for new messages" to last as long as the download and then a local
/// playback, so the alert is never half-played on a dead connection.
class ForceAudioDownloader {
  ForceAudioDownloader({
    http.Client? client,
    AppLogger? logger,
    Future<Directory> Function()? directory,
  }) : _client = client ?? http.Client(),
       _log = logger ?? AppLogger('force_audio.download'),
       _directory = directory ?? getTemporaryDirectory;

  final http.Client _client;
  final AppLogger _log;

  /// Injectable so tests can download into a real temp dir without the
  /// path_provider platform channel.
  final Future<Directory> Function() _directory;

  Future<File> download(
    ForceAudioAlert alert, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _directory();
    final target = File('${dir.path}/force_audio_${alert.id}.m4a');

    // Already downloaded (retry after a failed playback): reuse, don't re-fetch.
    if (target.existsSync() &&
        alert.sizeBytes > 0 &&
        await target.length() == alert.sizeBytes) {
      onProgress?.call(1);
      return target;
    }

    if (alert.isExpired) {
      throw const ValidationFailure('force_audio', 'This alert has expired.');
    }

    final uri = Uri.tryParse(alert.mediaUrl);
    if (uri == null || uri.scheme != 'https') {
      throw const ValidationFailure('force_audio', 'Unusable audio link.');
    }

    final request = http.Request('GET', uri);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      _log.error('download_rejected', data: {'status': response.statusCode});
      throw ServerFailure(
        statusCode: response.statusCode,
        safeCode: 'force_audio_download',
      );
    }

    final expected = response.contentLength ?? alert.sizeBytes;
    final temp = File('${target.path}.part');
    final sink = temp.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > ForceAudioLimits.maxBytes) {
          throw const ValidationFailure(
            'force_audio',
            'That recording is larger than 10 MB.',
          );
        }
        sink.add(chunk);
        if (expected > 0) {
          onProgress?.call((received / expected).clamp(0.0, 1.0));
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (received == 0) {
      await temp.delete();
      throw const ValidationFailure('force_audio', 'The audio file was empty.');
    }

    await temp.rename(target.path);
    onProgress?.call(1);
    _log.info('download_ok', data: {'bytes': received});
    return target;
  }
}
