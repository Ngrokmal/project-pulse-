import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pulse/features/chat/data/replicated_outbox.dart';

void main() {
  late Directory dir;
  late Box<String> a;
  late Box<String> b;
  late ReplicatedOutbox outbox;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pulse-outbox-mirror-');
    Hive.init(dir.path);
    final key = Hive.generateSecureKey();
    a = await Hive.openBox<String>('a', encryptionCipher: HiveAesCipher(key));
    b = await Hive.openBox<String>('b', encryptionCipher: HiveAesCipher(key));
    outbox = ReplicatedOutbox(a, b);
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  String record(int revision, bool deleted, String? value) => jsonEncode({
    'version': 1,
    'revision': revision,
    'deleted': deleted,
    'value': value,
  });
  test('mirrors drafts and keeps tombstones across reopen', () async {
    await outbox.put('owner:draft', 'private');
    expect(await outbox.get('owner:draft'), 'private');
    await outbox.delete('owner:draft');
    expect(await outbox.get('owner:draft'), isNull);
    expect(jsonDecode(a.get('owner:draft')!)['deleted'], isTrue);
    expect(a.get('owner:draft'), b.get('owner:draft'));
  });
  test('interrupted mirror-first put is repaired into primary', () async {
    await b.put('key', record(1, false, 'draft'));
    expect(await outbox.get('key'), 'draft');
    await outbox.repair('key');
    expect(a.get('key'), b.get('key'));
  });
  test('interrupted mirror-first delete cannot resurrect old draft', () async {
    await outbox.put('key', 'draft');
    await b.put('key', record(2, true, null));
    expect(await outbox.get('key'), isNull);
    await outbox.repair('key');
    expect(a.get('key'), b.get('key'));
  });
  test(
    'same-revision conflict and corrupt records are not overwritten',
    () async {
      await a.put('key', record(1, false, 'first'));
      await b.put('key', record(1, false, 'other'));
      await expectLater(outbox.repair('key'), throwsStateError);
      await b.put('key', 'broken');
      await expectLater(outbox.repair('key'), throwsFormatException);
      expect(b.get('key'), 'broken');
    },
  );
  test('concurrent operations serialize and do not reuse a revision', () async {
    await Future.wait([
      outbox.put('key', 'a'),
      ReplicatedOutbox(a, b).put('key', 'b'),
    ]);
    expect(jsonDecode(a.get('key')!)['revision'], 2);
    expect(a.get('key'), b.get('key'));
  });
}
