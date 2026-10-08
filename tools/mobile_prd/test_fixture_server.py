"""Fixture contracts without a Docker daemon, SSH session or simulator."""

import base64
from http.client import HTTPConnection
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from threading import Thread
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("fixture_server", Path(__file__).with_name("fixture_server.py"))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class Oracle:
    def __init__(self):
        self.count = 0

    def execution_count(self):
        return self.count


class FixtureContractsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mobile-prd-fixture-test-")
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        self.oracle = Oracle()
        self.state = fixture.FixtureState(self.output, self.oracle)

    def proposal(self):
        messages = [{"role": "user", "content": json.dumps({
            "request": "Diagnose this fixture failure", "selected_blocks": [{
                "id": "failure-1", "exit_code": 2,
                "output": "dev-box: configuration is missing (fixture only).",
                "citation": "[block:failure-1:1-1]",
            }],
        })}]
        reply = fixture.model_reply(messages, 1)
        return messages, reply

    def test_first_model_turn_only_proposes_fixture_repair(self):
        _, reply = self.proposal()
        call = reply["tool_calls"][0]["function"]
        self.assertEqual(call["name"], "run_command")
        self.assertEqual(json.loads(call["arguments"])["command"], "trail-fixture repair")
        self.assertIn("missing configuration", reply["content"])
        self.assertIn("[block:failure-1:1-1]", reply["content"])
        self.assertIn("unknown until", reply["content"])
        self.assertEqual(self.oracle.count, 0)

    def test_single_block_diagnosis_uses_only_supplied_citation(self):
        for citation in ("[block:single-1:2-3]", None, "invented"):
            messages = [{"role": "user", "content": json.dumps({
                "selected_block": {"citation": citation},
            })}]
            reply = fixture.model_reply(messages, 1)
            self.assertTrue(reply["content"].strip())
            if citation == "[block:single-1:2-3]":
                self.assertIn(citation, reply["content"])
            else:
                self.assertNotIn("[block:", reply["content"])

    def test_summary_requires_native_block_exit_and_output(self):
        messages, proposal = self.proposal()
        result = {"terminal_context": {"last_command": {"id": "block-1", "command": "trail-fixture repair",
                  "exit_code": 0, "output": "TRAIL_FIXTURE_REPAIRED", "citation": "[block:block-1:1-1]"}}}
        reply = fixture.model_reply(messages + [proposal, {"role": "tool", "content": json.dumps(result)}], 2)
        self.assertNotIn("tool_calls", reply)
        self.assertIn("[block:block-1:1-1]", reply["content"])
        self.assertEqual(self.oracle.count, 0)
        result["terminal_context"]["last_command"]["exit_code"] = None
        reply = fixture.model_reply(messages + [proposal, {"role": "tool", "content": json.dumps(result)}], 3)
        self.assertEqual(reply["tool_calls"][0]["function"]["name"], "read_screen")

    def test_unknown_or_cancelled_receipt_never_resubmits(self):
        messages, proposal = self.proposal()
        for result in ({"error": "unknown"}, {"confirmation_pending": True}, {"cancelled": True}):
            reply = fixture.model_reply(messages + [proposal, {"role": "tool", "content": json.dumps(result)}], 2)
            self.assertNotIn("tool_calls", reply)
            self.assertIn("do not resend", reply["content"])

    def test_public_event_metadata_cannot_contain_credentials_or_device_ids(self):
        for value in ({"password": "fixture"}, {"nested": {"UDID": "private"}}, {"path": "/Users/person/private"}):
            with self.subTest(key=next(iter(value))):
                with self.assertRaises(ValueError):
                    self.state.event(value)
        self.assertFalse((self.output / "events.jsonl").exists())
        self.state.event({"event": "approval", "operationId": "op-1", "writes": 1})
        self.assertEqual(json.loads((self.output / "events.jsonl").read_text())["writes"], 1)

    def test_checkpoint_requires_explicit_simulator_and_safe_filename(self):
        for name in ("../outside", "valid-name"):
            with patch.object(fixture.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    self.state.checkpoint(name, {})
                run.assert_not_called()

    def test_raw_checkpoint_keeps_original_png_and_omits_private_simulator_id(self):
        data = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")
        self.state.simulator = "private-simulator-marker"

        def screenshot(args, **_):
            self.assertEqual(args[:4], ["xcrun", "simctl", "io", "private-simulator-marker"])
            Path(args[-1]).write_bytes(data)
            return subprocess.CompletedProcess(args, 0)

        with patch.object(fixture.subprocess, "run", side_effect=screenshot):
            record = self.state.checkpoint("review", {"owner": "approval", "model_requests": 1})
        image = self.output / record["file"]
        self.assertEqual(image.read_bytes(), data)
        self.assertEqual((record["width"], record["height"]), (1, 1))
        self.assertNotIn("private-simulator-marker", image.with_suffix(".json").read_text())
        self.assertFalse(record["physical"])

    def test_oracle_only_reads_counter_and_cleanup_requires_owned_label(self):
        docker = fixture.DockerFixture("test-context", "test-run", self.output)
        docker.container = "a" * 64
        with patch.object(docker, "call", return_value=subprocess.CompletedProcess([], 0, "2\n")) as call:
            self.assertEqual(docker.execution_count(), 2)
            self.assertEqual(call.call_args.args[:2], ("exec", docker.container))
            self.assertIn("wc -c", call.call_args.args[-1])
            self.assertNotIn("trail-fixture repair", call.call_args.args[-1])
        with patch.object(docker, "call", return_value=subprocess.CompletedProcess([], 0, "other-run\n")) as call:
            docker.close()
            self.assertEqual(call.call_count, 1)
        docker.container = "a" * 64
        with patch.object(docker, "call", return_value=subprocess.CompletedProcess([], 0, "test-run\n")) as call:
            docker.close()
            self.assertEqual(call.call_args_list[1].args[:2], ("rm", "--force"))

    def test_http_model_events_and_state_have_independent_counts(self):
        server = fixture.FixtureServer(("127.0.0.1", 0), self.state)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        connection = HTTPConnection("127.0.0.1", server.server_port, timeout=5)
        self.addCleanup(connection.close)
        connection.request("POST", "/v1/chat/completions", json.dumps({"model": "trail-mobile-prd", "messages": [{"role": "user", "content": "fixture"}]}), {"Content-Type": "application/json"})
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        self.assertIn("tool_calls", json.loads(response.read())["choices"][0]["message"])
        connection.request("GET", "/state")
        response = connection.getresponse()
        self.assertEqual(json.loads(response.read()), {"model_requests": 1, "execution_count": 0})
        self.oracle.count = 1
        connection.request("POST", "/events", json.dumps({"event": "native_receipt", "outcome": "accepted", "blockId": "block-1"}), {"Content-Type": "application/json"})
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        response.read()
        connection.request("GET", "/state")
        response = connection.getresponse()
        self.assertEqual(json.loads(response.read()), {"model_requests": 1, "execution_count": 1})


if __name__ == "__main__":
    unittest.main()
