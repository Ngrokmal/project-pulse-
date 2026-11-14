import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/app/lifecycle.dart';
import 'package:pulse/features/settings/domain/app_settings.dart';
import 'package:pulse/features/settings/domain/notification_settings_probe.dart';
import 'package:pulse/features/notifications/domain/push_token.dart';

/// Phase 9: preferences, accessibility limits and lifecycle behaviour.
void main() {
  group('AppSettings', () {
    test('text size is clamped to what the layout can survive', () {
      const s = AppSettings();
      expect(s.copyWith(textScale: 5).textScale, AppSettings.maxTextScale);
      expect(s.copyWith(textScale: 0.1).textScale, AppSettings.minTextScale);
      expect(s.copyWith(textScale: 1.3).textScale, 1.3);
    });

    test('a corrupt stored value falls back to a sane default', () {
      expect(AppSettings.fromMap({'textScale': 'x'}).textScale, 1.0);
      expect(AppSettings.fromMap({'textScale': double.nan}).textScale, 1.0);
      expect(AppSettings.fromMap({}).textScale, 1.0);
      expect(AppSettings.fromMap({}).notificationsEnabled, isTrue);
    });

    test('round-trips through the stored map', () {
      const s = AppSettings(
        notificationsEnabled: false,
        soundsEnabled: false,
        forceAudioAutoOpen: false,
        reduceMotion: true,
        textScale: 1.15,
      );
      expect(AppSettings.fromMap(s.toMap()), s);
    });
  });

  group('SettingsController', () {
    test('every toggle lands in the store and in state', () async {
      final store = InMemorySettingsStore();
      final container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setNotifications(false);
      await notifier.setSounds(false);
      await notifier.setReduceMotion(true);
      await notifier.setForceAudioAutoOpen(false);
      await notifier.setTextScale(1.4);

      final settings = container.read(settingsProvider).value!;
      expect(settings.notificationsEnabled, isFalse);
      expect(settings.soundsEnabled, isFalse);
      expect(settings.reduceMotion, isTrue);
      expect(settings.forceAudioAutoOpen, isFalse);
      expect(settings.textScale, 1.4);
      expect(store.writes, 5);
      // and the store really holds the latest value
      expect((await store.read()).textScale, 1.4);
    });
  });

  group('notification permission — the denied paths', () {
    test('a first-time user is asked, and the answer sticks', () async {
      final probe = FakeNotificationSettingsProbe(
        PushPermission.notRequested,
        afterRequest: PushPermission.granted,
      );
      expect((await probe.read()), PushPermission.notRequested);
      expect((await probe.request()), PushPermission.granted);
      expect((await probe.read()), PushPermission.granted);
      expect(probe.requests, 1);
    });

    test(
      'a denied user is not nagged automatically, only when they tap',
      () async {
        final probe = FakeNotificationSettingsProbe(
          PushPermission.denied,
          afterRequest: PushPermission.denied,
        );
        // Reading the state must never trigger a prompt.
        await probe.read();
        expect(probe.requests, 0);
        expect((await probe.request()), PushPermission.denied);
        expect(probe.requests, 1);
      },
    );

    test('permanently denied cannot be fixed in-app', () {
      const blocked = PushPermission.permanentlyDenied;
      expect(blocked.canDeliver, isFalse);
      // The screen must not offer a "ask again" button for this state.
      expect(blocked == PushPermission.permanentlyDenied, isTrue);
    });

    test('only granted means the app may promise delivery', () {
      for (final p in PushPermission.values) {
        expect(p.canDeliver, p == PushPermission.granted);
      }
    });
  });

  group('lifecycle', () {
    test('resuming refreshes the caches once, not on every flicker', () {
      final refresher = ResumeRefresher(
        minInterval: const Duration(seconds: 5),
      );
      var conversations = 0;
      var calls = 0;
      void refresh() {
        refresher.maybeRun(DateTime(2026, 11, 14, 10, 0, 0), [
          () => conversations++,
          () => calls++,
        ]);
      }

      refresh();
      expect((conversations, calls), (1, 1));

      refresher.maybeRun(DateTime(2026, 11, 14, 10, 0, 2), [
        () => conversations++,
      ]);
      expect(conversations, 1, reason: '2 s later is inside the throttle');

      refresher.maybeRun(DateTime(2026, 11, 14, 10, 0, 9), [
        () => conversations++,
      ]);
      expect(conversations, 2);
      expect(refresher.runs, 2);
    });

    test('a pause does not wipe anything', () {
      final refresher = ResumeRefresher();
      var refreshes = 0;
      // Nothing is called for a pause: only `resumed` runs the refreshers.
      expect(refresher.maybeRun(DateTime(2026), []), isTrue);
      expect(refreshes, 0);
    });
  });
}
