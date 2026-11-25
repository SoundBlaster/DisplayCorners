"""Look up a Codex thread title without resuming it or loading its turns."""
import json
import os
import selectors
import shutil
import subprocess
import time
from pathlib import Path


def codex_executable():
    found = shutil.which("codex")
    if found:
        return found
    for candidate in ("/opt/homebrew/bin/codex", "/usr/local/bin/codex"):
        if Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def read_title(session_id):
    executable = codex_executable()
    if not executable:
        return None
    process = None
    try:
        process = subprocess.Popen([executable, "app-server"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        def send(message):
            process.stdin.write((json.dumps(message) + "\n").encode())
            process.stdin.flush()

        send({"id": 1, "method": "initialize", "params": {
            "clientInfo": {"name": "displaycorners", "version": "0.1"}}})
        deadline = time.monotonic() + 5
        buffer = b""
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while time.monotonic() < deadline:
                if not selector.select(deadline - time.monotonic()):
                    break
                data = os.read(process.stdout.fileno(), 65536)
                if not data:
                    break
                buffer += data
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    response = json.loads(line)
                    if response.get("id") == 1:
                        if "result" not in response:
                            return None
                        send({"method": "initialized", "params": {}})
                        send({"id": 2, "method": "thread/read", "params": {
                            "threadId": session_id, "includeTurns": False}})
                    elif response.get("id") == 2:
                        name = response.get("result", {}).get("thread", {}).get("name")
                        return name.strip() if isinstance(name, str) and name.strip() else None
    except (OSError, ValueError, TypeError, AttributeError):
        return None
    finally:
        if process:
            process.terminate()
            try:
                process.communicate(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
    return None
