import json
import socket
import subprocess
import sys
import unittest
from pathlib import Path


class MockAgentIntegrationTests(unittest.TestCase):
    def test_snapshot_updates_and_removal(self):
        script = Path(__file__).with_name("mock_agent.py")
        with subprocess.Popen([sys.executable, "-u", str(script)], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
            try:
                path = process.stdout.readline().strip().removeprefix("SOCKET=")
                self.assertTrue(path.endswith("/agent.sock"))
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                    client.settimeout(3)
                    client.connect(path)
                    with client.makefile("rb") as stream:
                        def read():
                            return json.loads(stream.readline())
                        self.assertEqual(read()["type"], "source")
                        client.sendall(b'{"type":"snapshot_request"}\n')
                        snapshot = read()
                        self.assertTrue(snapshot["complete"])
                        self.assertEqual(snapshot["sessions"][0]["state"], "working")
                        for command, expected in [("waiting", "waiting_for_user"), ("unknown", "unknown")]:
                            process.stdin.write(command + "\n")
                            process.stdin.flush()
                            self.assertEqual(read()["session"]["state"], expected)
                        process.stdin.write("remove\n")
                        process.stdin.flush()
                        self.assertEqual(read()["type"], "remove")
                        process.stdin.write("working\n")
                        process.stdin.flush()
                        self.assertEqual(read()["session"]["state"], "working")
            finally:
                process.stdin.write("quit\n")
                process.stdin.flush()
                process.wait(timeout=3)


if __name__ == "__main__":
    unittest.main()
