import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/features/media/data/file_downloader.dart';
import 'package:pulse/features/media/domain/media_asset.dart';
import 'package:pulse/features/media/presentation/media_bubble.dart';

/// The attachment round: how a document survives Cloudinary, what a name may
/// contain on disk, and how the card reads before anything is tapped.
void main() {
  group('upload naming (Cloudinary refuses to serve some types)', () {
    PickedMedia pick(String name) => PickedMedia(
      path: '/tmp/$name',
      fileName: name,
      sizeBytes: 1024,
      resourceType: PickedMedia.resourceTypeFor(name),
    );

    test('documents the CDN blocks are sent as opaque .dat blobs', () {
      for (final name in [
        'report.pdf',
        'photos.zip',
        'bundle.rar',
        'archive.7z',
        'dump.gz',
        'bundle.bz2',
        'site.tgz',
      ]) {
        final media = pick(name);
        expect(media.uploadFilename, endsWith('.dat'), reason: name);
        expect(media.isDisguisedForDelivery, isTrue, reason: name);
      }
    });

    test('everything the CDN serves keeps its own name', () {
      for (final name in ['notes.txt', 'sheet.xlsx', 'doc.docx', 'a.tar']) {
        final media = pick(name);
        expect(media.uploadFilename, name);
        expect(media.isDisguisedForDelivery, isFalse);
      }
      // images and videos never go through `raw`
      expect(pick('photo.jpg').uploadFilename, 'photo.jpg');
      expect(pick('clip.mp4').uploadFilename, 'clip.mp4');
    });

    test(
      'the stem survives the rewrite, so the blob is still recognisable',
      () {
        expect(
          pick('Q3 board minutes.pdf').uploadFilename,
          'Q3 board minutes.dat',
        );
      },
    );

    test('types Cloudinary rejects outright are refused before the upload', () {
      expect(PickedMedia.unsupportedMessage('setup.exe'), contains('.exe'));
      expect(PickedMedia.unsupportedMessage('app.apk'), contains('.apk'));
      expect(PickedMedia.unsupportedMessage('installer.msi'), isNotNull);
      expect(PickedMedia.unsupportedMessage('report.pdf'), isNull);
      expect(PickedMedia.unsupportedMessage('photo.jpg'), isNull);
    });
  });

  group('file names on disk', () {
    test('path separators and control characters cannot escape the folder', () {
      final name = FileDownloader.sanitizeName('../../etc/passwd');
      expect(name.contains('/'), isFalse);
      expect(name.startsWith('/'), isFalse);
      expect(name.length, lessThanOrEqualTo(120));

      final weird = FileDownloader.sanitizeName('a\u0000b:c*d?.pdf');
      expect(weird.contains('\u0000'), isFalse);
      expect(weird.contains(':'), isFalse);
      expect(weird, endsWith('.pdf'));
    });

    test('an empty or dot-only name falls back instead of writing nothing', () {
      expect(FileDownloader.sanitizeName('   '), 'attachment.bin');
      expect(FileDownloader.sanitizeName('...'), 'attachment.bin');
    });

    test('a very long name keeps its extension', () {
      final long = '${'x' * 200}.pdf';
      final safe = FileDownloader.sanitizeName(long);
      expect(safe.length, lessThanOrEqualTo(120));
      expect(safe, endsWith('.pdf'));
    });

    test('a second download never overwrites the first', () {
      expect(FileDownloader.uniqueName('a.pdf', existing: {}), 'a.pdf');
      expect(
        FileDownloader.uniqueName('a.pdf', existing: {'a.pdf'}),
        'a (2).pdf',
      );
      expect(
        FileDownloader.uniqueName('a.pdf', existing: {'a.pdf', 'a (2).pdf'}),
        'a (3).pdf',
      );
      expect(
        FileDownloader.uniqueName('noext', existing: {'noext'}),
        'noext (2)',
      );
    });
  });

  group('failures are honest', () {
    test('a CDN 401 becomes "this file can no longer be downloaded"', () {
      const failure = MediaFailure(MediaFailureReason.unavailable);
      expect(failure.code, 'media_unavailable');
      expect(failure.userMessage, contains("can't be downloaded"));
      expect(failure.isRetryable, isTrue);
      // It must never leak Cloudinary's own wording to the user.
      expect(failure.userMessage.contains('Untrusted'), isFalse);
    });

    test('a full disk is not retryable', () {
      const failure = MediaFailure(MediaFailureReason.tooLarge);
      expect(failure.isRetryable, isFalse);
      expect(failure.userMessage, contains('too large'));
    });
  });

  group('the downloader turns HTTP answers into typed failures', () {
    FileDownloader withStatus(int status) => FileDownloader(
      client: MockClient(
        (request) async => http.Response(
          status == 200 ? 'bytes' : '{"success":false,"error":{"code":401,"message":"Untrusted File Access"}}',
          status,
        ),
      ),
    );

    test('401 is "unavailable", not a crash and not a browser page', () async {
      await expectLater(
        withStatus(401).download(
          url: 'https://res.cloudinary.com/x/raw/upload/v1/a.zip',
          fileName: 'a.zip',
        ),
        throwsA(
          isA<MediaFailure>().having(
            (f) => f.reason,
            'reason',
            MediaFailureReason.unavailable,
          ),
        ),
      );
    });

    test('a 5xx stays a server failure so the UI can offer a retry', () async {
      await expectLater(
        withStatus(503).download(
          url: 'https://res.cloudinary.com/x/raw/upload/v1/a.zip',
          fileName: 'a.zip',
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a nonsense url never reaches the network', () async {
      await expectLater(
        FileDownloader(client: MockClient((_) async => http.Response('', 200)))
            .download(url: 'not-a-url', fileName: 'a.zip'),
        throwsA(
          isA<MediaFailure>().having(
            (f) => f.reason,
            'reason',
            MediaFailureReason.badUrl,
          ),
        ),
      );
    });
  });

  group('the file bubble shows a download, not a browser', () {
    testWidgets('idle card says tap to download and shows the real name', (
      tester,
    ) async {
      final message = Message(
        id: 'm-file',
        conversationId: 'c1',
        senderId: 'u2',
        kind: MessageKind.file,
        createdAt: DateTime(2026, 11, 14, 12),
        mediaUrl: 'https://res.cloudinary.com/kojy/raw/upload/v1/x.dat',
        mediaName: 'eid_with_family.pdf',
        mediaBytes: 482913,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MediaBubble(
                message: message,
                mine: false,
                myName: 'Mahmoud',
                peerName: 'Saiful',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('eid_with_family.pdf'), findsOneWidget);
      expect(find.text('Saiful → Mahmoud'), findsOneWidget);
      expect(find.textContaining('tap to download'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
    });
  });
}
