#!/usr/bin/env python3
"""Record only selected hook metadata during an explicitly configured prototype."""
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

def main():
    destination = os.environ.get("DISPLAY_CORNERS_TRACE")
    if not destination:
        return
    try:
        event = json.load(sys.stdin)
        if not isinstance(event, dict):
            return
        event_name = event.get("hook_event_name")
        if event_name not in (
            "SessionStart", "UserPromptSubmit", "PermissionRequest", "PreToolUse",
            "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "SessionEnd",
        ):
            return
        session = event.get("session_id")
        notification = event.get("notification_type")
        if notification not in ("permission_prompt", "idle_prompt", "auth_success", "elicitation_dialog", "elicitation_url_dialog"):
            notification = None
        reason = event.get("reason")
        if reason not in ("clear", "resume", "logout", "prompt_input_exit", "other", "bypass_permissions_disabled"):
            reason = None
        record = {
            "time": datetime.now(timezone.utc).isoformat(),
            "event": event_name,
            "session": hashlib.sha256(session.encode()).hexdigest()[:12]
            if isinstance(session, str) else None,
            "notification_type": notification,
            "reason": reason,
        }
        with Path(destination).open("a", encoding="utf-8") as output:
            output.write(json.dumps(record, ensure_ascii=False) + "\n")
    except (OSError, ValueError, TypeError):
        # Observation is advisory and must never block the harness.
        return

if __name__ == "__main__":
    main()
