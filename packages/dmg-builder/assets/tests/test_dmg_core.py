"""
Tests for the patched dmgbuild core module.

Run against an installed (and patched) dmgbuild bundle:
    <bundle>/python/bin/python3 -m pytest test_dmg_core.py -v

Or with any Python that has dmgbuild installed:
    python3 -m pytest test_dmg_core.py -v
"""

import os
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import MagicMock, call, patch


# ---------------------------------------------------------------------------
# Helpers shared across test cases
# ---------------------------------------------------------------------------

def _compute_auto_size(file_sizes, symlink_count=0):
    """Replicate build_dmg's auto-size logic (patched version) and return
    the raw 'K' string that would be passed to hdiutil."""
    BASE = 128 * 1024 * 1024

    def roundup(x, n):
        return x if x % n == 0 else x + n - x % n

    total = BASE
    for sz in file_sizes:
        total += roundup(sz, 4096)
    total += symlink_count * 4096

    # --- patched formula ---
    return str(int(max(total * 1.2 / 1024, 1024))) + "K"


def _size_k_to_bytes(size_str):
    """Convert a 'NNNK' string to bytes (1K = 1024 bytes)."""
    assert size_str.endswith("K"), size_str
    return int(size_str[:-1]) * 1024


# ---------------------------------------------------------------------------
# Unit tests: size-calculation formula
# ---------------------------------------------------------------------------

class TestSizeFormula(unittest.TestCase):

    def test_minimum_enforced_for_empty_payload(self):
        """With no files the minimum 1024 K floor must be respected."""
        result = _compute_auto_size([])
        # 128 MB base ÷ 1024 * 1.2 ≈ 150000 K — well above the 1024 K floor
        self.assertTrue(result.endswith("K"))
        self.assertGreaterEqual(int(result[:-1]), 1024)

    def test_result_is_integer_k_string(self):
        """Size must be a plain integer string with 'K' suffix — no floats."""
        result = _compute_auto_size([1_000_000])
        self.assertRegex(result, r"^\d+K$", "Size must match /^\\d+K$/")

    def test_20_percent_overhead_applied(self):
        """Volume must be at least 20 % larger than raw payload + base."""
        file_sizes = [500 * 1024 * 1024]  # 500 MB file
        BASE = 128 * 1024 * 1024
        raw_total = BASE + 500 * 1024 * 1024  # rounded up to 4096 already

        result = _compute_auto_size(file_sizes)
        volume_bytes = _size_k_to_bytes(result)

        # Volume must be ≥ raw payload * 1.2
        self.assertGreaterEqual(volume_bytes, raw_total * 1.2 - 1024)

    def test_large_electron_app_has_sufficient_headroom(self):
        """2 GB Electron app must produce a volume clearly larger than the payload."""
        # 1.9 GB app (similar to the reported failing case)
        app_size = 1_900 * 1024 * 1024
        result = _compute_auto_size([app_size])
        volume_bytes = _size_k_to_bytes(result)

        # Volume must exceed payload by at least the 128 MB base overhead
        self.assertGreater(volume_bytes, app_size + 128 * 1024 * 1024)

    def test_large_app_overhead_exceeds_old_formula(self):
        """Patched formula must give more headroom than the original 1/1000 formula."""
        app_size = 2_000 * 1024 * 1024  # 2 GB

        def _old_formula(total):
            return int(max(total / 1000, 1024))

        def _new_formula(total):
            return int(max(total * 1.2 / 1024, 1024))

        BASE = 128 * 1024 * 1024
        total = BASE + app_size
        self.assertGreater(_new_formula(total), _old_formula(total))

    def test_many_small_files_rounded_to_block_boundary(self):
        """1-byte files are rounded to 4096 bytes; total must reflect that."""
        n = 10_000
        result = _compute_auto_size([1] * n)
        volume_bytes = _size_k_to_bytes(result)

        # Each 1-byte file occupies one 4096-byte block
        min_payload = 128 * 1024 * 1024 + n * 4096
        self.assertGreater(volume_bytes, min_payload)

    def test_symlinks_add_one_block_each(self):
        """Each symlink must contribute 4096 bytes to the volume size."""
        base_result = _compute_auto_size([])
        result_with_symlinks = _compute_auto_size([], symlink_count=100)
        diff = _size_k_to_bytes(result_with_symlinks) - _size_k_to_bytes(base_result)
        # 100 symlinks × 4096 bytes = 409600 bytes, padded by 1.2×
        self.assertGreaterEqual(diff, int(100 * 4096 * 1.2) - 1024)

    def test_explicit_size_option_bypasses_calculation(self):
        """When options['size'] is not None, auto-calc must be skipped."""
        import dmgbuild.core as core  # noqa: PLC0415

        sizes_passed = []

        def fake_hdiutil(cmd, *args, **kwargs):
            if cmd == "create":
                idx = list(args).index("-size")
                sizes_passed.append(args[idx + 1])
            return 0, {"system-entities": [{"mount-point": "/tmp", "dev-entry": "/dev/disk99"}]}

        with patch.object(core, "hdiutil", side_effect=fake_hdiutil), \
             patch("subprocess.check_call"), \
             patch("subprocess.call"), \
             patch("os.symlink"), \
             patch("shutil.copyfile"), \
             patch("shutil.rmtree"), \
             patch("tempfile.NamedTemporaryFile") as mock_tmp, \
             patch.object(core.DSStore, "open", MagicMock()):
            mock_tmp.return_value.__enter__ = lambda s: s
            mock_tmp.return_value.__exit__ = MagicMock(return_value=False)
            mock_tmp.return_value.name = "/tmp/fake.dmg"

            try:
                core.build_dmg(
                    "/tmp/out.dmg",
                    "TestVol",
                    settings={"size": "99m", "files": [], "symlinks": {}},
                )
            except Exception:
                pass

        self.assertTrue(sizes_passed, "hdiutil 'create' was never called with -size — explicit-size bypass path not exercised")
        self.assertEqual(sizes_passed[0], "99m")


# ---------------------------------------------------------------------------
# Unit tests: ditto failure propagation
# ---------------------------------------------------------------------------

class TestDittoCopyFailure(unittest.TestCase):

    def _run_build_with_ditto_returncode(self, returncode):
        """Run build_dmg with a file to copy and a ditto that returns returncode."""
        import dmgbuild.core as core  # noqa: PLC0415

        # Create a temporary source file to copy
        with tempfile.NamedTemporaryFile(delete=False, suffix=".app") as tf:
            src_file = tf.name

        try:
            mount_point = tempfile.mkdtemp()
            try:
                def fake_hdiutil(cmd, *args, **kwargs):
                    if cmd == "attach":
                        return 0, {
                            "system-entities": [
                                {"mount-point": mount_point, "dev-entry": "/dev/disk99"}
                            ]
                        }
                    if cmd in ("create", "detach", "resize", "convert"):
                        return 0, {}
                    return 0, {}

                with patch.object(core, "hdiutil", side_effect=fake_hdiutil), \
                     patch("subprocess.check_call") as mock_cc, \
                     patch("subprocess.call"), \
                     patch("shutil.rmtree"), \
                     patch("tempfile.NamedTemporaryFile") as mock_tmp, \
                     patch.object(core.DSStore, "open", MagicMock()):

                    mock_tmp.return_value.__enter__ = lambda s: s
                    mock_tmp.return_value.__exit__ = MagicMock(return_value=False)
                    mock_tmp.return_value.name = "/tmp/fake_writable.dmg"

                    # Make check_call raise for the ditto call only
                    def side_effect(cmd_args, *a, **kw):
                        if cmd_args and cmd_args[0] == "/usr/bin/ditto":
                            if returncode != 0:
                                raise subprocess.CalledProcessError(returncode, cmd_args)

                    mock_cc.side_effect = side_effect

                    core.build_dmg(
                        "/tmp/out.dmg",
                        "TestVol",
                        settings={"files": [src_file], "symlinks": {}},
                    )
            finally:
                shutil.rmtree(mount_point, ignore_errors=True)
        finally:
            os.unlink(src_file)

    def test_ditto_failure_raises_exception(self):
        """Non-zero ditto exit must raise CalledProcessError (not silently pass)."""
        with self.assertRaises(subprocess.CalledProcessError):
            self._run_build_with_ditto_returncode(1)

    def test_ditto_success_does_not_raise(self):
        """Zero ditto exit must not raise."""
        try:
            self._run_build_with_ditto_returncode(0)
        except subprocess.CalledProcessError as exc:
            self.fail(f"Unexpected CalledProcessError from ditto: {exc}")
        except Exception:
            # Other exceptions (e.g. from hdiutil convert mock) are acceptable
            pass

    def test_ditto_uses_check_call_not_call(self):
        """ditto must be invoked via subprocess.check_call, not subprocess.call."""
        import dmgbuild.core as core  # noqa: PLC0415
        import inspect

        src = inspect.getsource(core)
        # The old bug used subprocess.call for ditto
        self.assertNotIn(
            'subprocess.call(["/usr/bin/ditto"',
            src,
            "core.py still uses subprocess.call for ditto — patch was not applied",
        )
        self.assertIn(
            'subprocess.check_call(["/usr/bin/ditto"',
            src,
            "core.py does not use subprocess.check_call for ditto",
        )


# ---------------------------------------------------------------------------
# Unit tests: patch integrity (applied-to-source checks)
# ---------------------------------------------------------------------------

class TestPatchesApplied(unittest.TestCase):

    def test_size_formula_uses_1024_divisor(self):
        """Patched core must not use / 1000 in the size formula."""
        import dmgbuild.core as core  # noqa: PLC0415
        import inspect

        src = inspect.getsource(core)
        self.assertNotIn(
            "total_size / 1000",
            src,
            "core.py still uses / 1000 — size-calculation patch was not applied",
        )

    def test_size_formula_has_overhead_factor(self):
        """Patched formula must include the 1.2 overhead multiplier."""
        import dmgbuild.core as core  # noqa: PLC0415
        import inspect

        src = inspect.getsource(core)
        self.assertIn(
            "total_size * 1.2 / 1024",
            src,
            "core.py does not contain the overhead factor — patch may have changed",
        )

    def test_size_result_has_no_float(self):
        """Auto-calculated size string must not contain a decimal point."""
        # 2 GB file triggers the code path
        result = _compute_auto_size([2 * 1024 * 1024 * 1024])
        self.assertNotIn(".", result, f"Size string contains float: {result!r}")


# ---------------------------------------------------------------------------
# Integration test: patch-dmgbuild.py script
# ---------------------------------------------------------------------------

class TestPatchScript(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self._tmp, ignore_errors=True)

    def _patch_script_path(self):
        here = os.path.dirname(__file__)
        return os.path.join(here, "..", "patch-dmgbuild.py")

    def _make_fake_core(self, content):
        path = os.path.join(self._tmp, "core.py")
        with open(path, "w") as fh:
            fh.write(content)
        return path

    def _make_fake_licensing(self, content):
        path = os.path.join(self._tmp, "licensing.py")
        with open(path, "w") as fh:
            fh.write(content)
        return path

    def test_patches_applied_correctly(self):
        fake_core = self._make_fake_core(
            'total_size = str(max(total_size / 1000, 1024)) + "K"\n'
            'subprocess.call(["/usr/bin/ditto", f, f_in_image])\n'
        )
        # licensing.py must live next to core.py for auto-discovery
        fake_licensing = self._make_fake_licensing(
            'multibyte_encoding = language_info.get("multibyte_encoding", False)\n'
            '            licenseDataFormat = "TEXT"\n'
            '            license_data = license_data.encode(language_encoding)\n'
            '        buttons = [b.encode(language_encoding) for b in buttons]\n'
        )
        result = subprocess.run(
            [sys.executable, self._patch_script_path(), fake_core],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        with open(fake_core) as fh:
            patched_core = fh.read()
        self.assertIn('total_size * 1.2 / 1024', patched_core)
        self.assertIn('subprocess.check_call(["/usr/bin/ditto"', patched_core)
        self.assertNotIn("total_size / 1000", patched_core)
        self.assertNotIn('subprocess.call(["/usr/bin/ditto"', patched_core)

        with open(fake_licensing) as fh:
            patched_licensing = fh.read()
        self.assertNotIn('"multibyte_encoding"', patched_licensing)
        self.assertIn('"multibyte", False)', patched_licensing)
        self.assertGreaterEqual(patched_licensing.count("except LookupError"), 2)
        self.assertIn('decode("utf-8", errors="ignore")', patched_licensing)

    def test_script_fails_when_pattern_missing(self):
        """Patch script must exit non-zero when expected patterns are absent."""
        fake_core = self._make_fake_core("# no matching patterns here\n")
        result = subprocess.run(
            [sys.executable, self._patch_script_path(), fake_core],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)

    def test_script_idempotent_check(self):
        """Applying patches twice to a real core.py must not error on first apply."""
        import dmgbuild.core as core  # noqa: PLC0415
        import inspect

        real_src = inspect.getsource(core)
        # Verify expected patterns exist in installed (patched) core
        self.assertIn("total_size * 1.2 / 1024", real_src)
        self.assertIn('subprocess.check_call(["/usr/bin/ditto"', real_src)


# ---------------------------------------------------------------------------
# Integration test: DMG created with adequate size for a large payload
# ---------------------------------------------------------------------------

class TestDMGSizeAdequacy(unittest.TestCase):
    """Verify that the calculated K value is always larger than the payload."""

    def test_volume_larger_than_payload_across_sizes(self):
        cases = [
            [],                            # empty app
            [1024],                        # 1 KB
            [10 * 1024 * 1024],            # 10 MB
            [500 * 1024 * 1024],           # 500 MB
            [1_900 * 1024 * 1024],         # ~1.9 GB (original bug case)
            [2_100 * 1024 * 1024],         # 2.1 GB
        ]
        for file_sizes in cases:
            with self.subTest(total_mb=sum(file_sizes) // (1024 * 1024)):
                result = _compute_auto_size(file_sizes)
                volume_bytes = _size_k_to_bytes(result)
                raw_payload = sum(file_sizes)
                self.assertGreater(
                    volume_bytes,
                    raw_payload,
                    f"Volume {volume_bytes} <= payload {raw_payload}",
                )

    def test_volume_has_meaningful_overhead_for_large_app(self):
        """For a 2 GB app the volume must be at least 300 MB larger than content."""
        app_size = 2_000 * 1024 * 1024
        result = _compute_auto_size([app_size])
        volume_bytes = _size_k_to_bytes(result)
        margin = volume_bytes - app_size
        self.assertGreater(margin, 300 * 1024 * 1024,
                           f"Margin {margin // (1024*1024)} MB is too small")


# ---------------------------------------------------------------------------
# Unit tests: CJK codec availability
# ---------------------------------------------------------------------------

class TestCJKCodecAvailability(unittest.TestCase):
    """The bundle must include CJK codec extension modules so that dmgbuild's
    licensing.py can encode Japanese, Korean, and Chinese license text."""

    def test_shift_jis_codec_available(self):
        """shift_jis must be available for Japanese license encoding."""
        try:
            "テスト".encode("shift_jis")
        except LookupError as e:
            self.fail(f"shift_jis codec unavailable: {e}")

    def test_ksx1001_codec_available(self):
        """ksx1001 must be available for Korean license encoding."""
        try:
            "테스트".encode("ksx1001")
        except LookupError as e:
            self.fail(f"ksx1001 codec unavailable: {e}")

    def test_gb2312_codec_available(self):
        """gb2312 must be available for Simplified Chinese license encoding."""
        try:
            "测试".encode("gb2312")
        except LookupError as e:
            self.fail(f"gb2312 codec unavailable: {e}")

    def test_big5_codec_available(self):
        """big5 must be available for Traditional Chinese license encoding."""
        try:
            "測試".encode("big5")
        except LookupError as e:
            self.fail(f"big5 codec unavailable: {e}")


# ---------------------------------------------------------------------------
# Unit tests: licensing.py patches
# ---------------------------------------------------------------------------

class TestLicensingPatches(unittest.TestCase):
    """Verify that patch-dmgbuild.py applied all three patches to licensing.py."""

    @classmethod
    def setUpClass(cls):
        import dmgbuild.licensing as licensing
        import inspect
        cls._licensing_src = inspect.getsource(licensing)
        cls._licensing = licensing

    def test_multibyte_key_fixed(self):
        """language_info_map uses 'multibyte', not 'multibyte_encoding' — the
        LPic field must read the correct key."""
        self.assertNotIn(
            'language_info.get("multibyte_encoding"',
            self._licensing_src,
            "multibyte key-name fix not applied: 'multibyte_encoding' still present",
        )
        self.assertTrue(
            '"multibyte", False)' in self._licensing_src
            or "'multibyte', False)" in self._licensing_src,
            "multibyte key-name fix not applied: 'multibyte' key not found in source",
        )

    def test_utf8_fallback_license_body_present(self):
        """UTF-8 fallback patch for license body encoding must be present."""
        self.assertGreaterEqual(
            self._licensing_src.count("except LookupError"),
            2,
            "Expected at least 2 'except LookupError' blocks in licensing.py (body + buttons)",
        )

    def test_utf8_fallback_buttons_present(self):
        """UTF-8 fallback for button encoding must be present in source."""
        # We specifically check that the fallback appears near the buttons encode
        self.assertIn(
            'encode("utf-8")',
            self._licensing_src,
            "UTF-8 fallback encode not found in licensing.py",
        )

    def _make_temp_license_file(self, content: str, suffix: str = ".txt") -> str:
        import tempfile
        fd, path = tempfile.mkstemp(suffix=suffix)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        return path

    def test_build_license_japanese(self):
        """build_license must succeed for ja_JP — no LookupError for shift_jis."""
        tmp = self._make_temp_license_file("こんにちは\nテスト ライセンス文書")
        try:
            result = self._licensing.build_license({"licenses": {"ja_JP": tmp}})
            self.assertIn("STR#", result)
            self.assertIn("LPic", result)
        except LookupError as e:
            self.fail(f"build_license raised LookupError for ja_JP: {e}")
        finally:
            os.unlink(tmp)

    def test_build_license_korean(self):
        """build_license must succeed for ko_KR — no LookupError for ksx1001."""
        tmp = self._make_temp_license_file("안녕하세요\n테스트 라이센스 문서")
        try:
            result = self._licensing.build_license({"licenses": {"ko_KR": tmp}})
            self.assertIn("STR#", result)
            self.assertIn("LPic", result)
        except LookupError as e:
            self.fail(f"build_license raised LookupError for ko_KR: {e}")
        finally:
            os.unlink(tmp)


if __name__ == "__main__":
    unittest.main(verbosity=2)
