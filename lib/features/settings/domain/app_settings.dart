import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

/// Phase 9: the user's own preferences. Stored on the device only — nothing
/// here is a security decision, but it does decide what the app *shows*.
class AppSettings {
  const AppSettings({
    this.notificationsEnabled = true,
    this.soundsEnabled = true,
    this.forceAudioAutoOpen = true,
    this.reduceMotion = false,
    this.textScale = 1.0,
  });

  final bool notificationsEnabled;
  final bool soundsEnabled;

  /// Whether a Force Audio alert takes over the screen the moment it lands.
  final bool forceAudioAutoOpen;
  final bool reduceMotion;

  /// Never outside what the app can lay out safely (0.9 – 1.6, §15).
  final double textScale;

  static const minTextScale = 0.9;
  static const maxTextScale = 1.6;

  AppSettings copyWith({
    bool? notificationsEnabled,
    bool? soundsEnabled,
    bool? forceAudioAutoOpen,
    bool? reduceMotion,
    double? textScale,
  }) => AppSettings(
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    soundsEnabled: soundsEnabled ?? this.soundsEnabled,
    forceAudioAutoOpen: forceAudioAutoOpen ?? this.forceAudioAutoOpen,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    textScale: (textScale ?? this.textScale).clamp(minTextScale, maxTextScale),
  );

  Map<String, dynamic> toMap() => {
    'notificationsEnabled': notificationsEnabled,
    'soundsEnabled': soundsEnabled,
    'forceAudioAutoOpen': forceAudioAutoOpen,
    'reduceMotion': reduceMotion,
    'textScale': textScale,
  };

  static AppSettings fromMap(Map<dynamic, dynamic> map) {
    final raw = map['textScale'];
    var scale = raw is num ? raw.toDouble() : 1.0;
    if (scale.isNaN || scale.isInfinite) scale = 1.0;
    return AppSettings(
      notificationsEnabled: (map['notificationsEnabled'] as bool?) ?? true,
      soundsEnabled: (map['soundsEnabled'] as bool?) ?? true,
      forceAudioAutoOpen: (map['forceAudioAutoOpen'] as bool?) ?? true,
      reduceMotion: (map['reduceMotion'] as bool?) ?? false,
      textScale: scale.clamp(minTextScale, maxTextScale),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.notificationsEnabled == notificationsEnabled &&
      other.soundsEnabled == soundsEnabled &&
      other.forceAudioAutoOpen == forceAudioAutoOpen &&
      other.reduceMotion == reduceMotion &&
      other.textScale == textScale;

  @override
  int get hashCode => Object.hash(
    notificationsEnabled,
    soundsEnabled,
    forceAudioAutoOpen,
    reduceMotion,
    textScale,
  );
}

/// Where the settings live. Abstract so tests never touch Hive.
abstract class SettingsStore {
  Future<AppSettings> read();
  Future<void> write(AppSettings settings);
}

class HiveSettingsStore implements SettingsStore {
  HiveSettingsStore({this.boxName = 'app_settings'});

  final String boxName;
  Future<Box<dynamic>>? _box;

  Future<Box<dynamic>> _open() =>
      _box ??= Hive.openBox<dynamic>(boxName, bytes: null);

  @override
  Future<AppSettings> read() async {
    final box = await _open();
    return AppSettings.fromMap(box.toMap());
  }

  @override
  Future<void> write(AppSettings settings) async {
    final box = await _open();
    await box.putAll(settings.toMap());
  }
}

class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([this._settings = const AppSettings()]);

  AppSettings _settings;
  int writes = 0;

  @override
  Future<AppSettings> read() async => _settings;

  @override
  Future<void> write(AppSettings settings) async {
    writes++;
    _settings = settings;
  }
}

final settingsStoreProvider = Provider<SettingsStore>((ref) {
  return HiveSettingsStore();
});

/// Settings are read once and then kept in memory; a write updates both.
class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsStoreProvider).read();

  Future<void> _update(AppSettings next) async {
    state = AsyncData(next);
    await ref.read(settingsStoreProvider).write(next);
  }

  Future<void> setNotifications(bool on) async => _update(
    (state.value ?? const AppSettings()).copyWith(notificationsEnabled: on),
  );

  Future<void> setSounds(bool on) async =>
      _update((state.value ?? const AppSettings()).copyWith(soundsEnabled: on));

  Future<void> setForceAudioAutoOpen(bool on) async => _update(
    (state.value ?? const AppSettings()).copyWith(forceAudioAutoOpen: on),
  );

  Future<void> setReduceMotion(bool on) async =>
      _update((state.value ?? const AppSettings()).copyWith(reduceMotion: on));

  Future<void> setTextScale(double scale) async =>
      _update((state.value ?? const AppSettings()).copyWith(textScale: scale));
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
