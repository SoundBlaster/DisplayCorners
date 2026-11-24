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
    def make_session(session_id, state):
        return {"session_id": session_id, "state": state, "project": "DisplayCorners", "agent": "Mock Agent"}

    sessions = {"mock-1": make_session("mock-1", "working"),
                "mock-2": make_session("mock-2", "waiting_for_user")}
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
            print("Commands: working|waiting|unknown [id], add <id>, remove [id], reopen, quit", flush=True)
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
                        parts = sys.stdin.readline().strip().split()
                        if not parts or parts[0] == "quit":
                            return
                        command = parts[0]
                        session_id = parts[1] if len(parts) > 1 else "mock-1"
                        if command == "reopen":
                            if client:
                                send(client, {"type": "debug_reopen"})
                            print("Reopen requested", flush=True)
                        elif command in ("working", "waiting", "unknown", "add"):
                            if command == "add" and session_id in sessions:
                                print(f"Already exists: {session_id}", flush=True)
                                continue
                            if command != "add" and session_id not in sessions:
                                print(f"No session: {session_id}", flush=True)
                                continue
                            state = "waiting_for_user" if command == "waiting" else "working" if command == "add" else command
                            previous = sessions.get(session_id)
                            if previous is not None and previous["state"] != state:
                                sessions.pop(session_id)
                            session = make_session(session_id, state)
                            sessions[session_id] = session
                            if client:
                                send(client, {"type": "update", "session": session})
                            print(f"{session_id}: {state}", flush=True)
                        elif command == "remove":
                            if sessions.pop(session_id, None) is not None and client:
                                send(client, {"type": "remove", "session_id": session_id})
                            print(f"Removed: {session_id}", flush=True)
                        else:
                            print("Use working, waiting, unknown, add, remove, reopen, or quit", flush=True)
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
                                send(client, {"type": "snapshot", "complete": True, "sessions": list(sessions.values())})
                                print("Snapshot sent", flush=True)


if __name__ == "__main__":
    main()
