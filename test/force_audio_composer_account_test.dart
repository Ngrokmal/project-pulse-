import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/auth/application/auth_controller.dart';
import 'package:pulse/features/auth/domain/auth_repository.dart';
import 'package:pulse/features/chat/application/chat_controller.dart';
import 'package:pulse/features/chat/domain/chat_repository.dart';
import 'package:pulse/features/force_audio/application/force_audio_controllers.dart';
import 'package:pulse/features/force_audio/data/audio_recorder.dart';
import 'package:pulse/features/media/data/cloudinary_uploader.dart';
import 'package:pulse/features/media/domain/media_asset.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(PulseUser(id: 'first', email: null));
  void switchTo(String id) =>
      state = AuthSignedIn(PulseUser(id: id, email: null));
}

class _Recorder implements ForceAudioRecorder {
  String? path;
  Completer<bool>? permissionGate;
  @override
  Future<bool> ensurePermission() async => permissionGate?.future ?? true;
  @override
  Future<void> start(String path) async {
    this.path = path;
    await File(path).writeAsBytes([1, 2, 3]);
  }

  @override
  Future<String?> stop() async => path;
  @override
  Stream<double> amplitude(Duration interval) => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

class _Upload extends CloudinaryUploader {
  final pending = Completer<CloudinaryAsset>();
  int calls = 0;
  void Function(double)? progress;
  @override
  Future<CloudinaryAsset> upload(
    PickedMedia media, {
    void Function(double)? onProgress,
  }) {
    calls++;
    progress = onProgress;
    return pending.future;
  }
}

class _Repo implements ChatRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('unexpected chat request');
  }
}

void main() {
  test('account switch while microphone permission is pending cannot start recording', () async {
    final recorder = _Recorder()..permissionGate = Completer<bool>();
    ForceAudioComposerController.debugRecorderOverride = recorder;
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(_Auth.new)],
    );
    addTearDown(() {
      container.dispose();
      ForceAudioComposerController.debugRecorderOverride = null;
    });
    final provider = forceAudioComposerProvider('conv');
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final start = container.read(provider.notifier).start();
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(
      'second',
    );
    recorder.permissionGate!.complete(true);
    await start;
    expect(recorder.path, isNull);
    expect(container.read(provider).stage, ComposerStage.idle);
  });
  for (final switchBeforeUpload in [true, false]) {
    test(
      switchBeforeUpload
          ? 'old recording cannot be uploaded after account switch'
          : 'account switch during upload prevents send and stale progress',
      () async {
        final recorder = _Recorder();
        final upload = _Upload();
        final repo = _Repo();
        ForceAudioComposerController.debugRecorderOverride = recorder;
        ForceAudioComposerController.debugUploaderOverride = upload;
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(_Auth.new),
            chatRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(() async {
          container.dispose();
          ForceAudioComposerController.debugRecorderOverride = null;
          ForceAudioComposerController.debugUploaderOverride = null;
          final path = recorder.path;
          if (path != null && await File(path).exists()) {
            await File(path).delete();
          }
        });
        final provider = forceAudioComposerProvider('conv');
        final sub = container.listen(provider, (_, _) {});
        addTearDown(sub.close);
        await container.read(provider.notifier).start();
        await Future<void>.delayed(const Duration(milliseconds: 650));
        await container.read(provider.notifier).stop();
        expect(container.read(provider).stage, ComposerStage.recorded);
        if (switchBeforeUpload) {
          (container.read(authControllerProvider.notifier) as _Auth).switchTo(
            'second',
          );
          await container.read(provider.notifier).send();
          expect(upload.calls, 0);
        } else {
          final send = container.read(provider.notifier).send();
          await container.pump();
          expect(container.read(provider).stage, ComposerStage.uploading);
          (container.read(authControllerProvider.notifier) as _Auth).switchTo(
            'second',
          );
          upload.progress?.call(.5);
          expect(container.read(provider).progress, 0);
          upload.pending.complete(
            const CloudinaryAsset(
              secureUrl: 'https://example.invalid/a',
              publicId: 'test',
              resourceType: MediaResourceType.video,
              bytes: 100,
            ),
          );
          await send;
        }
        expect(repo.calls, 0);
      },
    );
  }
}
