#!/usr/bin/env python3
"""Prepare disposable hook configurations without modifying user settings."""
import argparse
import json
import shlex
from pathlib import Path

EVENTS = (
    "SessionStart", "UserPromptSubmit", "PermissionRequest", "PreToolUse",
    "PostToolUse", "Stop", "SessionEnd",
)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path, help="A new, disposable directory")
    args = parser.parse_args()
    root = args.directory.resolve()
    root.mkdir(parents=True, exist_ok=False)
    command = f"/usr/bin/python3 {shlex.quote(str(Path(__file__).with_name('trace.py').resolve()))}"
    def config(events):
        return {
            "hooks": {
                event: [{"hooks": [{"type": "command", "command": command, "timeout": 3}]}]
                for event in events
            }
        }
    claude = root / "claude"
    codex = root / "codex"
    claude.mkdir()
    (codex / ".codex").mkdir(parents=True)
    claude_events = EVENTS + ("PostToolUseFailure", "Notification")
    (claude / "settings.json").write_text(json.dumps(config(claude_events), indent=2) + "\n")
    (codex / ".codex" / "hooks.json").write_text(json.dumps(config(EVENTS), indent=2) + "\n")
    print(f"Prepared disposable configurations in {root}")

if __name__ == "__main__":
    main()
