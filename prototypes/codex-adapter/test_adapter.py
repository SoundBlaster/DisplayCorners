import json
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent


class CodexAdapterTests(unittest.TestCase):
    def test_socket_observation_is_minimal_and_expires(self):
        with subprocess.Popen([sys.executable, "-u", str(HERE / "adapter.py"), "--ttl", "0.3"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
            try:
                event_socket = process.stdout.readline().strip().removeprefix("EVENT_SOCKET=")
                adapter_socket = process.stdout.readline().strip().removeprefix("ADAPTER_SOCKET=")
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                    client.settimeout(3)
                    client.connect(adapter_socket)
                    with client.makefile("rb") as lines:
                        read = lambda: json.loads(lines.readline())
                        self.assertEqual(read()["harness"], "Codex")
                        client.sendall(b'{"type":"snapshot_request"}\n')
                        self.assertEqual(read(), {"type": "snapshot", "complete": False, "sessions": []})

                        def emit(event):
                            result = subprocess.run([sys.executable, str(HERE / "hook.py"), event_socket],
                                                    input=json.dumps(event), text=True, capture_output=True, check=True)
                            self.assertEqual(json.loads(result.stdout), {})
                            return read()

                        base = {"session_id": "s1", "cwd": "/tmp/Project", "prompt": "DO NOT SEND",
                                "tool_input": {"secret": "DO NOT SEND"}, "transcript_path": "/secret"}
                        working = emit({**base, "hook_event_name": "PostToolUse"})
                        self.assertEqual(working["session"], {"session_id": "s1", "state": "working", "project": "Project", "agent": "Codex"})
                        self.assertEqual(read()["session"]["state"], "unknown")
                        waiting = emit({**base, "hook_event_name": "PermissionRequest"})
                        self.assertEqual(waiting["session"]["state"], "unknown")
                        self.assertEqual(emit({**base, "hook_event_name": "Stop"})["type"], "remove")
            finally:
                process.terminate()
                process.wait(timeout=3)

    def test_hook_is_nonblocking_when_receiver_is_absent(self):
        event = {"session_id": "s1", "hook_event_name": "PermissionRequest", "prompt": "private"}
        result = subprocess.run([sys.executable, str(HERE / "hook.py"), "/tmp/nonexistent-displaycorners.sock"],
                                input=json.dumps(event), text=True, capture_output=True, timeout=2, check=True)
        self.assertEqual(json.loads(result.stdout), {})
        self.assertEqual(result.stderr, "")

    def test_subagent_event_is_not_forwarded_as_parent_activity(self):
        with tempfile.TemporaryDirectory() as directory, socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as receiver:
            path = str(Path(directory) / "events.sock")
            receiver.bind(path)
            receiver.settimeout(0.1)
            event = {"session_id": "parent", "agent_id": "child", "hook_event_name": "PostToolUse"}
            result = subprocess.run([sys.executable, str(HERE / "hook.py"), path], input=json.dumps(event),
                                    text=True, capture_output=True, check=True)
            self.assertEqual(json.loads(result.stdout), {})
            with self.assertRaises(socket.timeout):
                receiver.recv(1024)

    def test_stable_short_sockets_are_removed_on_shutdown_and_recreated(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory) / ("long-directory-name-" * 6)
            event_paths = []
            for _ in range(2):
                process = subprocess.Popen([sys.executable, "-u", str(HERE / "adapter.py"), "--directory", str(data)],
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                try:
                    event_path = Path(process.stdout.readline().strip().removeprefix("EVENT_SOCKET="))
                    process.stdout.readline()
                    self.assertTrue(event_path.is_socket())
                    self.assertLess(len(str(event_path).encode()), 104)
                    event_paths.append(event_path)
                finally:
                    process.terminate()
                    process.wait(timeout=3)
                    process.stdout.close()
                    process.stderr.close()
                self.assertFalse(event_path.exists())
            self.assertEqual(event_paths[0], event_paths[1])


if __name__ == "__main__":
    unittest.main()
