#!/usr/bin/env python3
"""Small opt-in Codex hook adapter for the existing debug client."""
import argparse
import contextlib
import concurrent.futures
import json
import os
import selectors
import signal
import socket
import stat
import sys
import tempfile
import time
from pathlib import Path
from paths import socket_directory as short_socket_directory
from title_lookup import read_title


class Adapter:
    def __init__(self, ttl):
        self.ttl = ttl
        self.sessions = {}

    def accept(self, event):
        session_id = event.get("session_id")
        kind = event.get("event")
        if not isinstance(session_id, str) or not session_id:
            return None
        if kind in ("Stop", "Interrupt", "SessionEnd"):
            self.sessions.pop(session_id, None)
            return {"type": "remove", "session_id": session_id}
        if kind not in ("SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest"):
            return None
        previous = self.sessions.get(session_id, {})
        project = event.get("project")
        if not isinstance(project, str) or not project:
            project = previous.get("session", {}).get("project")
        session = {"session_id": session_id, "state": "working" if kind == "PostToolUse" else "unknown",
                   "project": project, "agent": "Codex", "title": previous.get("session", {}).get("title")}
        self.sessions[session_id] = {"session": session, "until": time.monotonic() + self.ttl}
        return {"type": "update", "session": session}

    def expire(self):
        messages = []
        now = time.monotonic()
        for entry in self.sessions.values():
            if entry["session"]["state"] == "working" and now >= entry["until"]:
                entry["session"] = {**entry["session"], "state": "unknown"}
                messages.append({"type": "update", "session": entry["session"]})
        return messages


def encode(message):
    return (json.dumps(message, ensure_ascii=False) + "\n").encode()


@contextlib.contextmanager
def socket_directory(path):
    if path is None:
        with tempfile.TemporaryDirectory(prefix="displaycorners-codex-") as directory:
            with socket_directory(directory) as short_directory:
                yield short_directory
        return
    data_directory = Path(path).expanduser().resolve()
    data_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory = short_socket_directory(data_directory)
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError("Socket directory must be private and owned by the current user")
    server_path = directory / "adapter.sock"
    if server_path.exists():
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
            probe.settimeout(0.1)
            if probe.connect_ex(str(server_path)) == 0:
                raise RuntimeError("Codex adapter is already running")
    paths = [directory / "events.sock", server_path]
    for item in paths:
        if item.exists():
            info = item.lstat()
            if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
                raise RuntimeError(f"Refusing to replace {item}")
            item.unlink()
    try:
        yield directory
    finally:
        for item in paths:
            if item.exists() and stat.S_ISSOCK(item.lstat().st_mode):
                item.unlink()
        try:
            directory.rmdir()
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ttl", type=float, default=60, help="Seconds before activity becomes unknown")
    parser.add_argument("--directory", help="Stable private directory for adapter sockets")
    args = parser.parse_args()
    if args.ttl <= 0:
        parser.error("--ttl must be positive")
    adapter = Adapter(args.ttl)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    with socket_directory(args.directory) as directory:
        event_path = str(Path(directory) / "events.sock")
        client_path = str(Path(directory) / "adapter.sock")
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as events, \
             socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server, \
             selectors.DefaultSelector() as selector:
            events.bind(event_path)
            server.bind(client_path)
            server.listen()
            selector.register(events, selectors.EVENT_READ, "events")
            selector.register(server, selectors.EVENT_READ, "server")
            clients = {}
            title_cache = {}
            title_futures = {}
            title_next_lookup = {}
            executor = concurrent.futures.ThreadPoolExecutor(max_workers=2)
            print(f"EVENT_SOCKET={event_path}\nADAPTER_SOCKET={client_path}", flush=True)

            def drop(client):
                if client not in clients:
                    return
                selector.unregister(client)
                clients.pop(client, None)
                client.close()

            def broadcast(message):
                for client in list(clients):
                    try:
                        client.sendall(encode(message))
                    except OSError:
                        drop(client)

            while True:
                for key, _ in selector.select(timeout=min(args.ttl, 1)):
                    if key.data == "server":
                        client, _ = server.accept()
                        client.settimeout(0.1)
                        clients[client] = b""
                        selector.register(client, selectors.EVENT_READ, "client")
                        try:
                            client.sendall(encode({"type": "source", "source_id": "codex-local", "harness": "Codex", "can_open_session": False}))
                        except OSError:
                            drop(client)
                    elif key.data == "events":
                        try:
                            event = json.loads(events.recv(65536))
                            message = adapter.accept(event) if isinstance(event, dict) else None
                            if message:
                                session_id = message.get("session_id") or message.get("session", {}).get("session_id")
                                if message["type"] == "update":
                                    if session_id in title_cache:
                                        message["session"]["title"] = title_cache[session_id]
                                    if session_id not in title_futures and time.monotonic() >= title_next_lookup.get(session_id, 0):
                                        title_next_lookup[session_id] = time.monotonic() + 60
                                        title_futures[session_id] = executor.submit(read_title, session_id)
                                broadcast(message)
                        except (ValueError, TypeError):
                            pass
                    else:
                        client = key.fileobj
                        try:
                            data = client.recv(65536)
                        except OSError:
                            drop(client)
                            continue
                        if not data:
                            drop(client)
                            continue
                        clients[client] += data
                        while b"\n" in clients[client]:
                            line, clients[client] = clients[client].split(b"\n", 1)
                            try:
                                message = json.loads(line)
                                if message.get("type") == "snapshot_request":
                                    client.sendall(encode({"type": "snapshot", "complete": False,
                                                           "sessions": [entry["session"] for entry in adapter.sessions.values()]}))
                            except (OSError, ValueError, AttributeError):
                                drop(client)
                                break
                for session_id, future in list(title_futures.items()):
                    if not future.done():
                        continue
                    del title_futures[session_id]
                    try:
                        title = future.result()
                    except Exception:
                        title = None
                    if title:
                        title_cache[session_id] = title
                        entry = adapter.sessions.get(session_id)
                        if entry and entry["session"].get("title") != title:
                            entry["session"]["title"] = title
                            broadcast({"type": "update", "session": entry["session"]})
                for message in adapter.expire():
                    broadcast(message)


if __name__ == "__main__":
    main()
