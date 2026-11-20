import 'app_update.dart';

/// Where the app asks "is there a newer build?".
///
/// One method, because that is the whole job: hand back the published manifest,
/// or `null` when the release channel has nothing usable (a release without an
/// APK, a manifest mid-upload). Network and parse failures are thrown as typed
/// `AppFailure`s by the data layer, so the caller can stay quiet on boot.
abstract interface class UpdateRepository {
  Future<AppUpdate?> latest();
}
