"""Regression tests for the package updater helpers."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))

from updater.files import atomic_write_text, file_transaction
from updater.hash import extract_hash_from_build_error
from updater.hashes_file import load_hashes, save_hashes
from updater.http import fetch_text
from updater.nix import NixCommandError, run_command
from updater.version import compare_versions, fetch_npm_version


class VersionTests(unittest.TestCase):
    def test_numeric_prerelease_identifiers_are_compared_numerically(self) -> None:
        self.assertLess(compare_versions("1.0.0-beta.2", "1.0.0-beta.10"), 0)

    def test_build_metadata_does_not_change_precedence(self) -> None:
        self.assertEqual(compare_versions("1.0.0+build.1", "1.0.0+build.2"), 0)

    def test_stable_release_beats_prerelease(self) -> None:
        self.assertGreater(compare_versions("1.0.0", "1.0.0-rc.1"), 0)


class HashParsingTests(unittest.TestCase):
    def test_known_nix_hash_error_formats(self) -> None:
        expected = "sha256-AbCdEf0123456789+/="
        for output in (
            f"got: {expected}",
            f"got {expected}",
            f"actual: {expected}",
        ):
            with self.subTest(output=output):
                self.assertEqual(extract_hash_from_build_error(output), expected)


class FileSafetyTests(unittest.TestCase):
    def test_hash_file_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "hashes.json"
            save_hashes(path, {"version": "1.2.3", "hash": "sha256-test"})
            self.assertEqual(
                load_hashes(path),
                {"version": "1.2.3", "hash": "sha256-test"},
            )
            self.assertEqual(json.loads(path.read_text())["version"], "1.2.3")

    def test_transaction_restores_changed_and_new_files_on_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            old_path = Path(tmpdir) / "old.txt"
            new_path = Path(tmpdir) / "new.txt"
            old_path.write_text("old\n")

            with self.assertRaisesRegex(RuntimeError, "boom"):
                with file_transaction(old_path, new_path):
                    atomic_write_text(old_path, "new\n")
                    atomic_write_text(new_path, "created\n")
                    raise RuntimeError("boom")

            self.assertEqual(old_path.read_text(), "old\n")
            self.assertFalse(new_path.exists())

    def test_transaction_restores_files_on_interruption(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "hashes.json"
            path.write_text('{"version": "old"}\n')

            with self.assertRaises(SystemExit):
                with file_transaction(path):
                    atomic_write_text(path, '{"version": "half-written"}\n')
                    raise SystemExit(130)

            self.assertEqual(path.read_text(), '{"version": "old"}\n')

    def test_malformed_hash_file_fails_without_rewriting_it(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "hashes.json"
            malformed = '{"version": '
            path.write_text(malformed)

            with self.assertRaises(json.JSONDecodeError):
                load_hashes(path)

            self.assertEqual(path.read_text(), malformed)

    def test_unicode_hash_data_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "hashes.json"
            data = {"version": "1.0.0-洞穴", "note": "🪨" * 1024}
            save_hashes(path, data)
            self.assertEqual(load_hashes(path), data)


class NetworkTests(unittest.TestCase):
    def test_http_retries_transient_failure(self) -> None:
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b"ok"
        with (
            mock.patch(
                "updater.http.urllib.request.urlopen",
                side_effect=[URLError("temporary"), response],
            ) as urlopen,
            mock.patch("updater.http.time.sleep") as sleep,
        ):
            self.assertEqual(fetch_text("https://example.invalid", retries=2), "ok")

        self.assertEqual(urlopen.call_count, 2)
        sleep.assert_called_once()

    def test_http_retry_count_is_bounded(self) -> None:
        with (
            mock.patch(
                "updater.http.urllib.request.urlopen",
                side_effect=URLError("still broken"),
            ) as urlopen,
            mock.patch("updater.http.time.sleep") as sleep,
            self.assertRaises(URLError),
        ):
            fetch_text("https://example.invalid", retries=3, retry_backoff=0)

        self.assertEqual(urlopen.call_count, 3)
        self.assertEqual(sleep.call_count, 2)

    def test_http_does_not_retry_permanent_client_error(self) -> None:
        error = HTTPError(
            "https://example.invalid/missing",
            404,
            "Not Found",
            hdrs=None,
            fp=None,
        )
        with (
            mock.patch(
                "updater.http.urllib.request.urlopen",
                side_effect=error,
            ) as urlopen,
            mock.patch("updater.http.time.sleep") as sleep,
            self.assertRaises(HTTPError),
        ):
            fetch_text("https://example.invalid/missing", retries=3)

        self.assertEqual(urlopen.call_count, 1)
        sleep.assert_not_called()

    def test_npm_command_failure_falls_back_to_registry(self) -> None:
        with (
            mock.patch(
                "updater.version.run_command",
                side_effect=NixCommandError("npm failed"),
            ),
            mock.patch(
                "updater.version.fetch_json",
                return_value={"version": "2.3.4"},
            ),
        ):
            self.assertEqual(fetch_npm_version("demo"), "2.3.4")


class CommandTests(unittest.TestCase):
    def test_nonzero_exit_cannot_hide_behind_success_text(self) -> None:
        error = subprocess.CalledProcessError(
            7,
            ["fake-command"],
            output="SUCCESS: everything worked",
            stderr="real failure",
        )
        with (
            mock.patch("updater.nix.subprocess.run", side_effect=error),
            self.assertRaises(NixCommandError) as raised,
        ):
            run_command(["fake-command"])

        self.assertIn("Exit code: 7", str(raised.exception))
        self.assertIn("real failure", str(raised.exception))

    def test_hung_command_is_bounded_and_reported(self) -> None:
        error = subprocess.TimeoutExpired(
            ["slow-command"],
            timeout=0.01,
            output="partial output",
            stderr="still running",
        )
        with (
            mock.patch("updater.nix.subprocess.run", side_effect=error),
            self.assertRaises(NixCommandError) as raised,
        ):
            run_command(["slow-command"], timeout=0.01)

        self.assertIn("timed out", str(raised.exception).lower())
        self.assertIn("partial output", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
