# The update channel: why it went silent, and why it cannot again

## What happened

Builds 46, 47, 48, 49 and 50 were published. Not one of them was ever offered to
an installed copy. The app said *you are up to date* every single time.

It was not the SHA-256 verification, not the keystore, and not malformed JSON.
It was arithmetic.

```
flutter build apk --split-per-abi
  → each slice's versionCode becomes  ABI_INDEX * 1000 + build
  → arm64-v8a build 48 installs as   2048
  → armeabi-v7a build 48 installs as 1048

latest.json published the number the release was *named* after
  → "versionCode": 48

the installed app then asked
  → is 48 newer than 2048?
  → no.  "You are up to date."
```

Measured on the real artifacts, not inferred:

| release | file | versionName | versionCode | manifest said |
|---|---|---|---|---|
| build-46 | `pulse-arm64.apk` | 0.1.46 | **2046** | 46 |
| build-48 | `pulse-arm64.apk` | 0.1.48 | **2048** | 48 |
| build-50 | `pulse-arm64.apk` | 0.1.50 | **2050** | 50 |
| build-50 | `pulse-armv7.apk` | 0.1.50 | **1050** | 50 |

Both sides were internally correct. They meant different things by the same
word, and nothing anywhere checked that they agreed.

## The rule now

**One number means one thing: `channelBuild`.** It is the CI run number,
compiled into the APK (`--dart-define=CHANNEL_BUILD`) and written into the
manifest. The comparison is `channelBuild(channel) > channelBuild(installed)` and
nothing else.

`versionCode` still exists — Android owns it — but it is only ever used for
*identity* ("is this the exact file I am running?"), never for ordering.

```jsonc
{
  "versionName": "0.1.51",
  "channelBuild": 51,      // what the app compares
  "versionCode": 2051,     // arm64 file's versionCode — for copies that predate this fix
  "abis": {
    "arm64": { "versionCode": 2051, ... },
    "arm32": { "versionCode": 1051, ... }
  }
}
```

Every one of those numbers is **read out of the built APK** (`aapt2 dump
badging`), never computed by hand.

## The three gates that make silence impossible

1. **`tool/release_manifest.py`** — fails the build if a slice's `versionCode` is
   not exactly `ABI_INDEX * 1000 + run`. If Flutter ever changes the split
   scheme, the build goes red instead of the channel going quiet.
2. **`dart run tool/verify_manifest.dart latest.json <run>`** — re-reads the
   generated file **with the app's own parser** and asserts three things: the
   file names this build, it *is* offered to the build before it, and it is *not*
   offered to a phone already running it.
3. **`test/update_channel_build_test.dart`** — eleven assertions, including the
   literal `2048` vs `50` case that failed for six builds.

Also asserted in CI: the APK is signed with the pinned upload certificate
(`80:1B:67:A4…`), and the release manifest carries `INTERNET`,
`POST_NOTIFICATIONS`, `RECORD_AUDIO` and `REQUEST_INSTALL_PACKAGES` — the last
one because a missing permission downloads an update and then silently never
installs it.

## The copies already out there

Build 48 runs the broken comparison, so it cannot be fixed by publishing — it
has to be *satisfied*. That is what the flat `versionCode: 2051` is for:

```
installed build-48  →  versionCode 2048
published build-51  →  versionCode 2051
old rule            →  2051 > 2048  →  offered  ✔
```

So the phone updates itself to build 51 with no manual step, and from build 51
onward the `channelBuild` rule takes over. One release is the bridge; the next
one is normal.

Verified against the live channel: the published `pulse-arm64.apk` is 29,595,980
bytes with sha256 `fa99d4cf…`, both of which match the manifest exactly, and the
file declares `versionCode 2051`.

## If a phone is armeabi-v7a

The flat `apkUrl`/`versionCode` pair points at the arm64 slice, because that was
the only shape old builds understand. A 32-bit phone running an old build would
download a file it cannot install once; install `pulse-armv7.apk` from the
release page by hand, and every update after that arrives on its own.
