#!/usr/bin/env python3
"""
Apply targeted patches to the installed dmgbuild core module and licensing module.

Run this after `pip install dmgbuild` and before archiving the bundle.
Exits non-zero if any expected pattern is not found — the build will then
fail loudly rather than silently ship an unpatched bundle.
"""

import os
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

    print(f"patch-dmgbuild: all core patches applied to {path}")


def apply_patches_licensing(path: str) -> None:
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()

    patches = [
        (
            # Fix L1: The language_info_map uses "multibyte": True for CJK
            # entries, but the code reads "multibyte_encoding" — a key that
            # never exists — so the LPic "2-byte language" field is always 0
            # for CJK languages.  This corrects the key name so the field is
            # set properly.
            'multibyte_encoding = language_info.get("multibyte_encoding", False)',
            'multibyte_encoding = language_info.get("multibyte", False)',
            "licensing: fix multibyte key name (multibyte_encoding → multibyte)",
        ),
        (
            # Fix L2: When the bundled Python does not include a CJK codec
            # (e.g. shift_jis for Japanese), license_data.encode() raises
            # LookupError and aborts the entire DMG build.  Fall back to
            # UTF-8 so the license body is still embedded; modern macOS SLA
            # dialogs render UTF-8 TEXT resources correctly.
            "            licenseDataFormat = \"TEXT\"\n"
            "            license_data = license_data.encode(language_encoding)",
            "            licenseDataFormat = \"TEXT\"\n"
            "            try:\n"
            "                license_data = license_data.encode(language_encoding)\n"
            "            except LookupError:\n"
            "                license_data = license_data.encode(\"utf-8\")",
            "licensing: UTF-8 fallback for license body when target codec is unavailable",
        ),
        (
            # Fix L3: Same LookupError problem for button-label encoding.
            # Default buttons for Japanese/Korean/Chinese contain Unicode text
            # that must be encoded into the STR# resource.  Fall back to UTF-8
            # so button labels are still present rather than crashing the build.
            #
            # Additional care: some default messages (e.g. Japanese at 90 chars)
            # exceed 255 bytes when encoded as UTF-8 (3 bytes/char × 90 = 270).
            # The STR# length prefix is a single byte, so anything > 255 raises
            # OverflowError on the next line.  We truncate to ≤255 bytes while
            # preserving valid UTF-8 by round-tripping through decode(errors=
            # 'ignore') before the final encode.
            "        buttons = [b.encode(language_encoding) for b in buttons]",
            "        try:\n"
            "            buttons = [b.encode(language_encoding) for b in buttons]\n"
            "        except LookupError:\n"
            "            buttons = [\n"
            "                b.encode(\"utf-8\")[:255].decode(\"utf-8\", errors=\"ignore\").encode(\"utf-8\")\n"
            "                for b in buttons\n"
            "            ]",
            "licensing: UTF-8 fallback for button encoding with safe 255-byte truncation",
        ),
    ]

    for old, new, label in patches:
        if old not in src:
            sys.exit(
                f"patch-dmgbuild: FAILED to find pattern for patch '{label}'.\n"
                f"The upstream dmgbuild licensing.py may have changed; review and update the patch."
            )
        src = src.replace(old, new, 1)
        print(f"  ✓ Applied patch: {label}")

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)

    print(f"patch-dmgbuild: all licensing patches applied to {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} <path/to/dmgbuild/core.py>")

    core_path = sys.argv[1]
    apply_patches(core_path)

    licensing_path = os.path.join(os.path.dirname(core_path), "licensing.py")
    apply_patches_licensing(licensing_path)
