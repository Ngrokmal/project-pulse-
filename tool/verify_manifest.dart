// Checks a published release manifest with the *app's own parser*, before CI is
// allowed to publish it.
//
// The update channel once broke because CI and the app disagreed about what a
// number meant: CI wrote `versionCode: 50`, the APK installed as `2050`, and the
// app — comparing the two — decided every phone was already newer than the
// channel. Nothing failed; the update simply never arrived.
//
// A unit test cannot catch that, because both sides were individually correct.
// What catches it is running the shipped decision code over the shipped file:
//
//   dart run tool/verify_manifest.dart latest.json <this build number>
//
// It exits non-zero, failing the build, if the manifest is unreadable by
// `AppUpdate.tryParse`, if the build numbers disagree, or — the interesting one
// — if this release would not be offered to the build immediately before it, or
// would be offered to a phone already running it.
//
// The executable spec is test/update_channel_build_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:pulse/features/update/domain/app_update.dart';

Never _fail(String message) {
  stderr.writeln('::error::manifest contract: $message');
  exit(1);
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/verify_manifest.dart <latest.json> <build number>',
    );
    exit(64);
  }

  final path = args[0];
  final expectedBuild = int.tryParse(args[1]);
  if (expectedBuild == null || expectedBuild <= 0) {
    _fail('build number ${args[1]} is not a positive integer');
  }

  final file = File(path);
  if (!file.existsSync()) _fail('$path does not exist');

  AppUpdate? update;
  try {
    update = AppUpdate.tryParse(jsonDecode(file.readAsStringSync()));
  } on FormatException catch (error) {
    _fail('$path is not JSON the app can read: ${error.message}');
  }
  if (update == null) {
    _fail('$path parsed as JSON but not as a release the app would accept');
  }

  if (update.channelBuild != expectedBuild) {
    _fail(
      'channelBuild is ${update.channelBuild}, this build is $expectedBuild — '
      'the file would name a different build than the one published',
    );
  }

  // A release must be offered to the build before it, and to nothing else.
  if (!update.isNewerThan(expectedBuild - 1)) {
    _fail(
      'build $expectedBuild would NOT be offered to a phone on build '
      '${expectedBuild - 1} — this is the "update never arrives" failure',
    );
  }
  final ownCode = update.variants['arm64']?.versionCode;
  if (update.isNewerThan(expectedBuild)) {
    _fail(
      'build $expectedBuild would be offered to a phone already running it',
    );
  }
  if (ownCode != null && update.carriesVersionCode(ownCode) == false) {
    _fail('the manifest does not list its own arm64 versionCode $ownCode');
  }

  final arm64 = update.variants['arm64'];
  final arm32 = update.variants['arm32'];
  if (arm64 == null || arm32 == null) {
    final seen = update.variants.keys.join(', ');
    _fail(
      'expected arm64 and arm32 slices, found ${seen.isEmpty ? 'nothing' : seen}',
    );
  }

  // The per-ABI codes must exist: this is what lets the app say "that file is
  // the one I am running" without re-deriving Android's arithmetic.
  for (final abi in const ['arm64', 'arm32']) {
    final variant = update.variants[abi]!;
    if (variant.versionCode == null) {
      _fail('$abi slice has no versionCode — the app cannot verify identity');
    }
    if (!variant.isUsable) _fail('$abi slice is not usable (url/sha/size)');
  }
  if (arm64.versionCode == arm32.versionCode) {
    _fail(
      'arm64 and arm32 declare the same versionCode — one of them is wrong',
    );
  }

  stdout.writeln(
    'manifest verified: build ${update.channelBuild} (${update.versionName}), '
    'arm64 ${arm64.versionCode} ${arm64.sizeLabel}, '
    'arm32 ${arm32.versionCode} ${arm32.sizeLabel}',
  );
}
