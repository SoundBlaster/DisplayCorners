#!/usr/bin/env python3
"""Install or remove only Display Corners' entries in Codex hooks.json."""
import argparse
import json
import os
import shlex
import shutil
import tempfile
from pathlib import Path
from paths import socket_directory

EVENTS = ("SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd")


def command_for(data):
    return f"/usr/bin/python3 {shlex.quote(str(data / 'hook.py'))} {shlex.quote(str(socket_directory(data) / 'events.sock'))}"


def load(path):
    if not path.exists():
        return {"hooks": {}}
    config = json.loads(path.read_text())
    if not isinstance(config, dict) or not isinstance(config.get("hooks", {}), dict):
        raise ValueError("hooks.json must contain a hooks object")
    return config


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    descriptor, temporary = tempfile.mkstemp(prefix=".displaycorners-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def contains(config, event, command):
    groups = config.get("hooks", {}).get(event, [])
    if not isinstance(groups, list):
        raise ValueError(f"{event} hooks must be an array")
    for group in groups:
        if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
            raise ValueError(f"invalid {event} hook group")
        if any(isinstance(item, dict) and item.get("command") == command for item in group["hooks"]):
            return True
    return False


def change(action, home, data, source):
    path = home / "hooks.json"
    if path.is_symlink():
        path = path.resolve(strict=True)
    config = load(path)
    hooks = config.setdefault("hooks", {})
    command = command_for(data)
    present = {event: contains(config, event, command) for event in EVENTS}
    if action == "status":
        return "installed" if all(present.values()) else "partial" if any(present.values()) else "not_installed"
    if action == "install":
        data.mkdir(parents=True, exist_ok=True, mode=0o700)
        destination = data / "hook.py"
        # Copy to a stable path, so moving or rebuilding the app does not break the hook.
        descriptor, temporary = tempfile.mkstemp(prefix=".hook-", dir=data)
        os.close(descriptor)
        try:
            shutil.copyfile(source, temporary)
            os.replace(temporary, destination)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        for event in EVENTS:
            if not present[event]:
                hooks.setdefault(event, []).append({"hooks": [{"type": "command", "command": command, "timeout": 2}]})
    elif action == "remove":
        if not path.exists():
            return "not_installed"
        for event in EVENTS:
            if event not in hooks:
                continue
            updated = []
            for group in hooks[event]:
                remaining = [item for item in group["hooks"] if not (isinstance(item, dict) and item.get("command") == command)]
                if len(remaining) == len(group["hooks"]):
                    updated.append(group)
                elif remaining:
                    updated.append({**group, "hooks": remaining})
            if updated:
                hooks[event] = updated
            else:
                hooks.pop(event)
    write_atomic(path, config)
    return "installed" if action == "install" else "not_installed"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("status", "install", "remove"))
    parser.add_argument("--home", type=Path, required=True)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--source", type=Path, default=Path(__file__).with_name("hook.py"))
    args = parser.parse_args()
    try:
        print(change(args.action, args.home.expanduser().resolve(), args.data.expanduser().resolve(), args.source.resolve()))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(1, f"Could not update Codex hooks: {error}\n")


if __name__ == "__main__":
    main()
