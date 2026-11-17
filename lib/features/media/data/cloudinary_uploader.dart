import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/media_asset.dart';

/// Uploads to Cloudinary with **real** byte-level progress.
///
/// The bytes are streamed through a counter, so the reported percentage is what
/// actually left the device — not an animation that guesses (§16 "real upload
/// progress").
///
/// Authenticity note: this build uses a restricted **unsigned** upload preset
/// (`pulse_unsigned`: folder `pulse/messages`, 50 MB ceiling). Signing uploads
/// server-side requires the Edge Function deployment, which is blocked on a
/// Supabase PAT; when that lands, only `_signatureParams` changes.
class CloudinaryUploader {
  CloudinaryUploader({http.Client? client, AppLogger? logger})
    : _client = client ?? http.Client(),
      _log = logger ?? AppLogger('media');

  static const String uploadPreset = 'pulse_unsigned';

  final http.Client _client;
  final AppLogger _log;

  String get _base =>
      'https://api.cloudinary.com/v1_1/${AppConfig.cloudinaryCloudName}';

  bool get isConfigured =>
      AppConfig.cloudinaryCloudName.isNotEmpty && uploadPreset.isNotEmpty;

  /// Uploads [media], reporting progress in 0..1.
  Future<CloudinaryAsset> upload(
    PickedMedia media, {
    void Function(double progress)? onProgress,
  }) async {
    if (!isConfigured) {
      throw const ConfigurationFailure('Cloudinary cloud name missing.');
    }
    final sizeError = PickedMedia.validateSize(
      media.resourceType,
      media.sizeBytes,
    );
    if (sizeError != null) throw ValidationFailure('media', sizeError);

    final file = File(media.path);
    if (!file.existsSync()) {
      throw const StorageFailure(insufficientSpace: false);
    }

    final resource = switch (media.resourceType) {
      MediaResourceType.image => 'image',
      MediaResourceType.video => 'video',
      MediaResourceType.raw => 'raw',
    };

    var sent = 0;
    final total = media.sizeBytes;
    final stream = file.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          sent += chunk.length;
          onProgress?.call(total == 0 ? 0 : (sent / total).clamp(0.0, 1.0));
          sink.add(chunk);
        },
      ),
    );

    final request =
        http.MultipartRequest('POST', Uri.parse('$_base/$resource/upload'))
          ..fields['upload_preset'] = uploadPreset
          ..fields['folder'] = 'pulse/messages'
          ..files.add(
            // `.pdf` / `.zip` / archives are served by Cloudinary as HTTP 401
            // "Untrusted File Access"; the same bytes under `.dat` are served
            // normally, and the original name is stored in `media_name`.
            http.MultipartFile(
              'file',
              stream,
              total,
              filename: media.uploadFilename,
            ),
          );

    try {
      // 49 MiB on a slow mobile link needs room; anything longer is a dead
      // connection, not a slow one.
      final response = await _client
          .send(request)
          .timeout(const Duration(minutes: 5));
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200) {
        _log.error('upload_rejected', data: {'status': response.statusCode});
        throw ServerFailure(
          statusCode: response.statusCode,
          safeCode: 'upload_rejected',
        );
      }
      final json = _decode(body);
      final asset = CloudinaryAsset.fromJson(json, media.resourceType);
      onProgress?.call(1);
      _log.info(
        'upload_ok',
        data: {'type': asset.resourceType.name, 'bytes': asset.bytes},
      );
      return asset;
    } on AppFailure {
      rethrow;
    } on SocketException catch (e) {
      throw NetworkFailure(detail: e.message);
    } on TimeoutException {
      throw const NetworkFailure(timedOut: true);
    } on http.ClientException catch (e) {
      throw NetworkFailure(detail: e.message);
    } catch (e) {
      _log.error('upload_failed', error: e);
      throw const ServerFailure(safeCode: 'upload_failed');
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['secure_url'] is String) {
        return decoded;
      }
      throw const FormatException('unexpected upload response');
    } catch (_) {
      _log.error('upload_bad_json');
      throw const ServerFailure(safeCode: 'upload_bad_response');
    }
  }
}
