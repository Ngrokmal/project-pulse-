import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../data/audio_recorder.dart';
import '../data/force_audio_downloader.dart';
import '../data/supabase_force_audio_repository.dart';
import '../domain/force_audio_played_store.dart';
import '../domain/force_audio_repository.dart';

/// Dependency wiring for Force Audio. Kept in its own file so the chat layer can
/// depend on the repository without importing the chat controller back.
final forceAudioRepositoryProvider = Provider<ForceAudioRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure('Supabase is not configured.');
  }
  return SupabaseForceAudioRepository(Supabase.instance.client);
});

final forceAudioDownloaderProvider = Provider<ForceAudioDownloader>(
  (ref) => ForceAudioDownloader(),
);

final forceAudioRecorderProvider = Provider<ForceAudioRecorder>(
  (ref) => ForceAudioRecorder(),
);

final playedAlertStoreProvider = Provider<PlayedAlertStore>(
  (ref) => HivePlayedAlertStore(),
);
