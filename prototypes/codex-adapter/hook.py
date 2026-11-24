#!/usr/bin/env python3
"""Forward selected Codex hook metadata to the local debug adapter."""
import json
import os
import socket
import sys

EVENTS = {"SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd"}


def main():
    try:
        payload = json.load(sys.stdin)
        if payload.get("agent_id"):
            return
        event = payload.get("hook_event_name")
        session_id = payload.get("session_id")
        if event not in EVENTS or not isinstance(session_id, str) or not session_id:
            return
        cwd = payload.get("cwd")
        project = os.path.basename(os.path.normpath(cwd)) if isinstance(cwd, str) and cwd else None
        message = {"event": event, "session_id": session_id, "project": project}
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as channel:
            channel.settimeout(0.1)
            channel.sendto(json.dumps(message).encode(), sys.argv[1])
    except (OSError, ValueError, TypeError, AttributeError, IndexError):
        pass
    finally:
        # An empty JSON result neither answers approvals nor steers Codex.
        print("{}")


if __name__ == "__main__":
    main()
