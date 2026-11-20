#!/usr/bin/env python3
"""Writes the release manifest (`latest.json`) that the app's update check reads.

Why this is a script and not a `printf` block in the workflow: the manifest *is*
the update channel, and the one thing it must never be is invalid JSON or out of
step with the APKs next to it. Everything here is read from the files that were
actually built, and the numbers are checked against the scheme the app uses
before the file is allowed to exist.

Inputs are the same environment variables the build step already exports:

    RUN        the CI run number — the one build number everyone agrees on
    VERSION    0.1.<RUN>
    BASE       https://github.com/<owner>/<repo>/releases/latest/download
    APK64/32   file names of the two slices
    SHA64/32   sha256 of each slice
    SIZE64/32  size in bytes of each slice
    CODE64/32  the `versionCode` each slice declares — read from the APK, never
               computed here, because Android's per-ABI split rule owns that
               arithmetic (`ABI_INDEX * 1000 + build`)
    NOTES      the commit subject and body, one note per line
    OUT        where to write (default: latest.json)

The two numbers in the output mean two different things, on purpose:

    channelBuild  the build number (run number). This is what the app compares.
    versionCode   `versionCode` of the arm64 file. Kept for builds published
                  before `channelBuild` existed: an installed copy of one of
                  those compares against this field, so it must stay a value
                  such a copy considers *newer* than itself.
"""

from __future__ import annotations

import json
import os
import sys


def env(name: str, *, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None or value == "":
        sys.exit(f"::error::release manifest: {name} is not set")
    return value


def positive_int(name: str) -> int:
    raw = env(name)
    try:
        value = int(raw)
    except ValueError:
        sys.exit(f"::error::release manifest: {name}={raw!r} is not a number")
    if value <= 0:
        sys.exit(f"::error::release manifest: {name}={value} is not positive")
    return value


def checkout_scheme(code: int, abi_index: int, run: int) -> None:
    """Fail the build if Android's split scheme ever changes under us.

    Every update in the app's history broke on exactly this arithmetic being
    assumed instead of checked. A mismatch here is not a warning: publishing a
    manifest whose numbers disagree with the binaries is the bug.
    """
    expected = abi_index * 1000 + run
    if code != expected:
        sys.exit(
            f"::error::versionCode contract broken: an ABI slice reports {code}, "
            f"expected {expected} ({abi_index} * 1000 + {run}). The app's build "
            "comparison and this manifest both assume `ABI_INDEX * 1000 + build`; "
            "if Flutter changed that, update AppConfig/InstalledBuild and this "
            "script together before publishing."
        )


def main() -> None:
    run = positive_int("RUN")
    if run >= 1000:
        sys.exit(
            "::error::run number reached 1000 — the per-ABI versionCode scheme "
            "(`ABI_INDEX * 1000 + build`) runs out of room here. Move the "
            "channel to a new numbering range before publishing."
        )

    version = env("VERSION")
    base = env("BASE").rstrip("/")
    apk64 = env("APK64")
    apk32 = env("APK32")
    sha64 = env("SHA64")
    sha32 = env("SHA32")
    size64 = positive_int("SIZE64")
    size32 = positive_int("SIZE32")
    code64 = positive_int("CODE64")
    code32 = positive_int("CODE32")
    notes_raw = os.environ.get("NOTES", "")

    # arm64-v8a is ABI index 2, armeabi-v7a is index 1 (Android's own table).
    checkout_scheme(code64, 2, run)
    checkout_scheme(code32, 1, run)

    for label, url in (("arm64", f"{base}/{apk64}"), ("arm32", f"{base}/{apk32}")):
        if not url.startswith("https://"):
            sys.exit(f"::error::{label} url is not https: {url}")

    for label, digest in (("arm64", sha64), ("arm32", sha32)):
        if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            sys.exit(f"::error::{label} sha256 is not lowercase hex: {digest}")

    notes = [line.strip() for line in notes_raw.splitlines() if line.strip()][:4]

    manifest = {
        "versionName": version,
        # What the app compares. One meaning, everywhere.
        "channelBuild": run,
        # What a pre-`channelBuild` build compares. It is the *installed*
        # `versionCode` of this release on arm64, so a copy running 2048 sees
        # 2051 and updates; a copy that already has this build sees 2051 and
        # does not.
        "versionCode": code64,
        "publishedAt": __import__("datetime").datetime.now(
            __import__("datetime").timezone.utc
        ).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "apkUrl": f"{base}/{apk64}",
        "sizeBytes": size64,
        "sha256": sha64,
        "abis": {
            "arm64": {
                "apkUrl": f"{base}/{apk64}",
                "sizeBytes": size64,
                "sha256": sha64,
                "versionCode": code64,
            },
            "arm32": {
                "apkUrl": f"{base}/{apk32}",
                "sizeBytes": size32,
                "sha256": sha32,
                "versionCode": code32,
            },
        },
        "notes": notes,
    }

    out = os.environ.get("OUT", "latest.json")
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    print(
        f"manifest ok: build {run} ({version}) — "
        f"arm64 {code64} / {size64} B, arm32 {code32} / {size32} B → {out}"
    )


if __name__ == "__main__":
    main()
