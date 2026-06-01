#!/usr/bin/env python3
"""
Apply targeted patches to the installed dmgbuild core module.

Run this after `pip install dmgbuild` and before archiving the bundle.
Exits non-zero if any expected pattern is not found — the build will then
fail loudly rather than silently ship an unpatched bundle.
"""

import sys


def apply_patches(path: str) -> None:
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()

    patches = [
        (
            # Fix 1: The auto-size formula divided bytes by 1000 and then
            # passed the result with a "K" suffix to hdiutil.  hdiutil treats
            # "K" as 1024 bytes, so the actual divisor was 1000, leaving only
            # ~2.4 % headroom over the raw payload.  For large Electron apps
            # (1-2 GB+) this can be smaller than the HFS+ catalog B-tree,
            # journal, and allocation bitmap, causing ditto writes to fail with
            # "No space left on device" — but silently, because the exit code
            # was not checked (see Fix 2 below).
            #
            # The corrected formula:
            #   • Converts bytes → kilobytes with the proper divisor (1024).
            #   • Adds a 20 % overhead margin for filesystem metadata so that
            #     even pathological cases (many small files → large catalog)
            #     have breathing room.
            #   • Uses integer arithmetic to avoid passing a float string to
            #     hdiutil (e.g. "134217.728K").
            'total_size = str(max(total_size / 1000, 1024)) + "K"',
            'total_size = str(int(max(total_size * 1.2 / 1024, 1024))) + "K"',
            "size-calculation: use 1024 divisor with 20% overhead",
        ),
        (
            # Fix 2: ditto's exit code was discarded via subprocess.call, so a
            # "No space left on device" failure during file copy produced a
            # corrupt (truncated) entry in the DMG without raising any error.
            # check_call raises CalledProcessError on non-zero exit, which is
            # then caught by the outer try/except in build_dmg and surfaced as
            # a DMGError — giving the caller a clear failure instead of a
            # silently incomplete image.
            'subprocess.call(["/usr/bin/ditto", f, f_in_image])',
            'subprocess.check_call(["/usr/bin/ditto", f, f_in_image])',
            "ditto: check exit code so copy failures are not silently swallowed",
        ),
    ]

    for old, new, label in patches:
        if old not in src:
            sys.exit(
                f"patch-dmgbuild: FAILED to find pattern for patch '{label}'.\n"
                f"The upstream dmgbuild source may have changed; review and update the patch."
            )
        src = src.replace(old, new, 1)
        print(f"  ✓ Applied patch: {label}")

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)

    print(f"patch-dmgbuild: all patches applied to {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} <path/to/dmgbuild/core.py>")
    apply_patches(sys.argv[1])
