import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/error/app_failure.dart';
import '../domain/app_update.dart';
import '../domain/update_repository.dart';

/// Reads `latest.json` out of the newest GitHub Release.
///
/// The URL is GitHub's own `releases/latest/download/...` redirect, so the
/// manifest and the APK it points at always come from the same release. The
/// request is small (a few hundred bytes) and is sent once per launch, with a
/// hard timeout: a slow release channel must never hold the splash screen.
class GithubUpdateRepository implements UpdateRepository {
  GithubUpdateRepository(
    this._client, {
    required this.manifestUrl,
    this.timeout = const Duration(seconds: 8),
  });

  final http.Client _client;
  final String manifestUrl;
  final Duration timeout;

  @override
  Future<AppUpdate?> latest() async {
    late final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse(manifestUrl),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(timeout);
    } on Object {
      throw const NetworkFailure(timedOut: true);
    }

    // A project with no release yet answers 404 — that is "nothing to install",
    // not an error worth showing anyone.
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw ServerFailure(safeCode: 'update_http_${response.statusCode}');
    }

    try {
      return AppUpdate.tryParse(jsonDecode(response.body));
    } on FormatException {
      throw const ServerFailure(safeCode: 'update_manifest_invalid');
    }
  }
}
