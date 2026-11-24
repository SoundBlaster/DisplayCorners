#!/usr/bin/env python3
"""A disposable, interactive JSONL adapter for the DisplayCorners debug client."""
import json
import selectors
import socket
import sys
import tempfile
from pathlib import Path


def send(connection, message):
    connection.sendall((json.dumps(message) + "\n").encode())


def main():
    state = "working"
    session = {"session_id": "mock-1", "state": state, "project": "DisplayCorners", "agent": "Mock Agent"}
    with tempfile.TemporaryDirectory(prefix="displaycorners-mock-") as directory:
        path = str(Path(directory) / "agent.sock")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server, selectors.DefaultSelector() as selector:
            server.bind(path)
            server.listen(1)
            selector.register(server, selectors.EVENT_READ, "server")
            selector.register(sys.stdin, selectors.EVENT_READ, "stdin")
            client = None
            pending = b""
            print(f"SOCKET={path}", flush=True)
            print("Commands: working, waiting, unknown, remove, quit", flush=True)
            while True:
                for key, _ in selector.select():
                    if key.data == "server":
                        incoming, _ = server.accept()
                        if client is not None:
                            incoming.close()
                            continue
                        client = incoming
                        selector.register(client, selectors.EVENT_READ, "client")
                        send(client, {"type": "source", "source_id": "mock-agent", "harness": "Mock Agent", "can_open_session": False})
                        print("Connected", flush=True)
                    elif key.data == "stdin":
                        command = sys.stdin.readline().strip()
                        if command in ("quit", ""):
                            return
                        if command in ("working", "waiting", "unknown"):
                            if session is None:
                                session = {"session_id": "mock-1", "project": "DisplayCorners", "agent": "Mock Agent"}
                            session["state"] = "waiting_for_user" if command == "waiting" else command
                            if client:
                                send(client, {"type": "update", "session": session})
                            print(f"State: {session['state']}", flush=True)
                        elif command == "remove":
                            session = None
                            if client:
                                send(client, {"type": "remove", "session_id": "mock-1"})
                            print("Session removed; set a state to restore it", flush=True)
                        else:
                            print("Use working, waiting, unknown, remove, or quit", flush=True)
                    else:
                        chunk = client.recv(4096)
                        if not chunk:
                            selector.unregister(client)
                            client.close()
                            client = None
                            pending = b""
                            print("Disconnected", flush=True)
                            continue
                        pending += chunk
                        while b"\n" in pending:
                            line, pending = pending.split(b"\n", 1)
                            try:
                                message = json.loads(line)
                            except (ValueError, UnicodeDecodeError):
                                continue
                            if message.get("type") == "snapshot_request":
                                send(client, {"type": "snapshot", "complete": True, "sessions": [session] if session else []})
                                print("Snapshot sent", flush=True)


if __name__ == "__main__":
    main()
