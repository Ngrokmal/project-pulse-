import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../core/logging/app_logger.dart';

/// Durable "this alert has already been played" record (§5 duplicate guard).
///
/// The server state is authoritative, but a push can arrive twice, the app can be
/// killed mid-playback, and the network can fail right after playback — so a
/// persisted local set is what actually prevents a second playback on this device.
abstract class PlayedAlertStore {
  Future<bool> isPlayed(String alertId);
  Future<void> markPlayed(String alertId);
}

class HivePlayedAlertStore implements PlayedAlertStore {
  HivePlayedAlertStore({Box<bool>? box}) : _injected = box;

  static const String boxName = 'force_audio_played';
  static const int maxEntries = 500;
  static final _log = AppLogger('force_audio.played');

  final Box<bool>? _injected;
  Box<bool>? _resolved;

  Future<Box<bool>?> _box() async {
    if (_injected != null) return _injected;
    final cached = _resolved;
    if (cached != null && cached.isOpen) return cached;
    try {
      _resolved = Hive.isBoxOpen(boxName)
          ? Hive.box<bool>(boxName)
          : await Hive.openBox<bool>(boxName);
      return _resolved;
    } on Object catch (e) {
      // Without storage the app still works; a repeated push may replay once.
      _log.error('played_box_failed', error: e);
      return null;
    }
  }

  @override
  Future<bool> isPlayed(String alertId) async {
    final box = await _box();
    return box?.get(alertId) ?? false;
  }

  @override
  Future<void> markPlayed(String alertId) async {
    final box = await _box();
    if (box == null) return;
    await box.put(alertId, true);
    if (box.length > maxEntries) {
      final stale = box.keys
          .cast<String>()
          .take(box.length - maxEntries)
          .toList();
      await box.deleteAll(stale);
    }
  }
}

/// Test double, and the fallback when Hive cannot be opened.
class InMemoryPlayedAlertStore implements PlayedAlertStore {
  InMemoryPlayedAlertStore([Set<String>? seed])
    : _played = seed == null ? <String>{} : {...seed};

  final Set<String> _played;

  @override
  Future<bool> isPlayed(String alertId) async => _played.contains(alertId);

  @override
  Future<void> markPlayed(String alertId) async => _played.add(alertId);
}
