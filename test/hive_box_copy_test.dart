import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pulse/features/chat/data/hive_box_copy.dart';

void main() {
  late Directory dir;
  late Box<String> source;
  late Box<String> encrypted;
  late List<int> key;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pulse-hive-copy-');
    Hive.init(dir.path);
    source = await Hive.openBox<String>('source');
    key = Hive.generateSecureKey();
    encrypted = await Hive.openBox<String>(
      'target',
      encryptionCipher: HiveAesCipher(key),
    );
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test('copies scoped, legacy and corrupt values without deletion or ownership inference', () async {
    const canary = 'legacy-private-unsent-3753';
    await source.put('legacy-key', canary);
    await source.put('v2:owner:key', '{"draft":"scoped"}');
    await source.put('corrupt', '{not valid json');
    expect(
      await copyHiveStringsWithoutDeleting(
        source: source,
        destination: encrypted,
      ),
      3,
    );
    expect(
      await copyHiveStringsWithoutDeleting(
        source: source,
        destination: encrypted,
      ),
      0,
    );
    expect(source.length, 3);
    await Hive.close();
    expect(
      latin1.decode(await File('${dir.path}/target.hive').readAsBytes()),
      isNot(contains(canary)),
    );
    Hive.init(dir.path);
    source = await Hive.openBox<String>('source');
    encrypted = await Hive.openBox<String>(
      'target',
      encryptionCipher: HiveAesCipher(key),
    );
    expect(encrypted.get('legacy-key'), canary);
    expect(encrypted.get('corrupt'), '{not valid json');
    expect(source.get('legacy-key'), canary);
  });
  test(
    'conflict prevents overwriting any destination and keeps source',
    () async {
      await source.put('one', 'source');
      await source.put('two', 'other');
      await encrypted.put('one', 'different');
      await expectLater(
        copyHiveStringsWithoutDeleting(source: source, destination: encrypted),
        throwsStateError,
      );
      expect(encrypted.get('one'), 'different');
      expect(encrypted.containsKey('two'), isFalse);
      expect(source.length, 2);
    },
  );
  test('source box cannot be the destination', () async {
    await expectLater(
      copyHiveStringsWithoutDeleting(source: source, destination: source),
      throwsArgumentError,
    );
  });
}
