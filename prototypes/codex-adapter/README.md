# Codex hook adapter — debug prototype

The debug app can install and remove its Codex hooks from **Agent Settings** in the menu bar. Installing does not approve them: review and trust them with `/hooks` in Codex. Other hook entries and inline configuration are left in place. The hook script is copied to a stable app-support location and sends only the session ID, event name and project basename to the local adapter. It does not send prompt text, tool input or transcript contents.

To launch the debug app using the real Codex home, without automatically installing anything:

```sh
BUILD_ROOT=/path/to/build SWIFTPM_CACHE=/path/to/cache \
  prototypes/mock-agent/run-debug.sh
```

Use Agent Settings to install or remove the hooks. The debug app launches its local adapter when its hooks are installed. Changing hooks requires Codex's own review/trust. Already-running sessions may not load newly installed hooks until restarted or resumed.

For isolated testing, set `DISPLAY_CORNERS_CODEX_HOME` and `DISPLAY_CORNERS_CODEX_DATA_DIR` to separate temporary directories before launching the debug app. `DISPLAY_CORNERS_OPEN_SETTINGS=1` opens the settings window on startup for UI testing. These debug overrides do not change the active Codex profile.

`PostToolUse` provides an observed working signal; after 60 seconds without confirmation it becomes unknown. `SessionStart`, `UserPromptSubmit`, and `PermissionRequest` report unknown because they do not prove that work started or that an approval was actually shown. `Stop`, `Interrupt` and `SessionEnd` remove the active observation, not necessarily the session. Events with `agent_id` are ignored because Codex can identify subagent hooks with the parent's session ID. The adapter advertises an incomplete snapshot and no session navigation. Chat titles are fetched asynchronously from the local Codex app-server by session ID, without loading turns; if unavailable, the UI shows a neutral label. Additional metadata in its response is not logged or retained. Hook delivery can be lost when the app is not running. An interactive trust approval followed by a non-interactive Codex CLI session was checked end to end: a real tool execution produced a working update, followed by removal at the end of the observation. Other Codex surfaces have not been validated.

For a disposable project-scoped test, start `python3 prototypes/codex-adapter/adapter.py`, then use `prepare.py /path/to/new/project /path/from/EVENT_SOCKET`. Review and trust the generated project hooks in Codex. The event and adapter sockets are local and access is limited to the current user. These scripts are prototypes; they are not included in the release build.
