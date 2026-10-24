"""Acceptance orchestration checks; real compiler validation runs on macOS."""
from __future__ import annotations
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest
from unittest import mock

import native_hook_cache_acceptance as acceptance


def snapshot(requests=0, hits=0, misses=0, reads=0, writes=0):
    return {"available": True, "counters": {
        "compile_requests": requests, "cache_hits": {"counts": {"Rust": hits}},
        "cache_misses": {"counts": {"Rust": misses}},
        "cache_read_errors": reads, "cache_write_errors": writes,
        "cache_errors": {"counts": {"Rust": 0}}}}


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.empty = acceptance.delta(snapshot(), snapshot())

    def test_cases_cover_real_rebuild_contract(self):
        self.assertEqual([x[0] for x in acceptance.CASES],
                         ["cache_off", "cache_populate", "source_changed", "config_changed"])
        self.assertEqual([x[4] for x in acceptance.CASES], [101, 101, 202, 1202])
        self.assertEqual(len(acceptance.PACKAGES), 2)

    def test_marker_is_observable_and_preserves_original_source(self):
        source = "pub fn existing() {}\n"
        result = acceptance.probe_source(source, 202)
        self.assertTrue(result.startswith(source))
        self.assertIn('extern "C"', result)
        self.assertIn("202 + if cfg!(ianvs_ci_cache_probe)", result)

    def test_existing_symbol_is_not_overwritten(self):
        with self.assertRaises(ValueError):
            acceptance.probe_source(acceptance.SYMBOL, 101)

    def test_valid_counter_delta(self):
        counts = acceptance.delta(snapshot(1, 0, 1), snapshot(5, 3, 2))
        self.assertEqual(counts["compile_requests"], 4)
        self.assertEqual(counts["cache_hits"], 3)
        self.assertEqual(counts["cache_misses"], 1)

    def test_unavailable_counters_are_not_zero(self):
        for bad in (None, {}, {"available": False}):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                acceptance.delta(bad, snapshot())

    def test_counter_reset_is_rejected(self):
        with self.assertRaises(ValueError):
            acceptance.delta(snapshot(5), snapshot(4))

    def test_invalid_counter_types_rejected(self):
        for value in (True, -1, None, "2"):
            bad = snapshot()
            bad["counters"]["compile_requests"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                acceptance.delta(bad, snapshot())

    def test_disabled_case_requires_no_cache_requests(self):
        acceptance.check_case("cache_off", self.empty, 101, 101)
        with self.assertRaises(RuntimeError):
            acceptance.check_case("cache_off", dict(self.empty, compile_requests=1), 101, 101)

    def test_enabled_case_requires_real_requests(self):
        with self.assertRaises(RuntimeError):
            acceptance.check_case("cache_populate", self.empty, 101, 101)

    def test_source_change_requires_warm_cache_and_new_value(self):
        valid = dict(self.empty, compile_requests=3, cache_hits=2, cache_misses=1)
        acceptance.check_case("source_changed", valid, 202, 202)
        with self.assertRaises(RuntimeError):
            acceptance.check_case("source_changed", valid, 101, 202)
        with self.assertRaises(RuntimeError):
            acceptance.check_case("source_changed", dict(valid, cache_hits=0), 202, 202)

    def test_config_change_requires_miss_and_changed_value(self):
        valid = dict(self.empty, compile_requests=3, cache_misses=3)
        acceptance.check_case("config_changed", valid, 1202, 1202)
        with self.assertRaises(RuntimeError):
            acceptance.check_case("config_changed", valid, 202, 1202)
        with self.assertRaises(RuntimeError):
            acceptance.check_case("config_changed", dict(valid, cache_misses=0), 1202, 1202)

    def test_cache_io_errors_cannot_pass(self):
        for key in ("cache_read_errors", "cache_write_errors", "cache_errors"):
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                acceptance.check_case("cache_off", dict(self.empty, **{key: 1}), 101, 101)

    def test_actual_process_failure_is_not_retried(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            counter = root / "count"
            args = [sys.executable, "-c", f"from pathlib import Path; p=Path({str(counter)!r}); p.write_text('one'); raise SystemExit(7)"]
            with self.assertRaises(subprocess.CalledProcessError) as error:
                acceptance.build(args, root, dict(__import__('os').environ), root / "command.log")
            self.assertEqual(error.exception.returncode, 7)
            self.assertEqual(counter.read_text(), "one")

    def test_dylib_probe_uses_a_new_process(self):
        with mock.patch.object(acceptance, "command_output", return_value="202") as output:
            self.assertEqual(acceptance.load_probe(Path("/tmp/native.dylib")), 202)
        args = output.call_args.args[0]
        self.assertEqual(args[:2], [sys.executable, "-c"])
        self.assertIn("ctypes.CDLL", args[2])
        self.assertEqual(args[-1], "/tmp/native.dylib")


if __name__ == "__main__":
    unittest.main()
