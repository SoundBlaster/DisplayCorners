#!/usr/bin/env python3
"""Create a disposable Codex project with a reviewable hook configuration."""
import argparse
import json
import shlex
from pathlib import Path

EVENTS = ("SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path, help="A new disposable project directory")
    parser.add_argument("event_socket", type=Path, help="EVENT_SOCKET printed by adapter.py")
    args = parser.parse_args()
    if not args.event_socket.is_socket():
        parser.error("event socket does not exist")
    project = args.project.resolve()
    project.mkdir(parents=True, exist_ok=False)
    directory = project / ".codex"
    directory.mkdir()
    hook = Path(__file__).with_name("hook.py").resolve()
    command = f"/usr/bin/python3 {shlex.quote(str(hook))} {shlex.quote(str(args.event_socket))}"
    config = {"hooks": {event: [{"hooks": [{"type": "command", "command": command, "timeout": 2}]}] for event in EVENTS}}
    (directory / "hooks.json").write_text(json.dumps(config, indent=2) + "\n")
    print(f"Project: {project}\nHook file: {directory / 'hooks.json'}\nHook script: {hook}")


if __name__ == "__main__":
    main()
