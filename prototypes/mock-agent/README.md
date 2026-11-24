# Mock Agent — debug

A disposable agent simulator and an opt-in debug-only client in Display Corners. The simulator serves a local Unix socket in a private temporary directory. It sends one complete snapshot and subsequent `update` / `remove` messages using the draft JSONL protocol. It does not monitor real agents, implement navigation or claim full protocol conformance.

1. Start the simulator in a terminal and copy the printed socket path:

   ```sh
   python3 prototypes/mock-agent/mock_agent.py
   ```

2. In a second terminal, build and launch the debug application. Use a build directory outside the checkout:

   ```sh
   BUILD_ROOT=/path/to/build SWIFTPM_CACHE=/path/to/cache \
     prototypes/mock-agent/run-debug.sh /path/from/SOCKET
   ```

3. The simulator starts with `mock-1` and `mock-2`. In its terminal enter `working mock-1`, `waiting mock-1`, `unknown mock-1`, `add mock-3`, `remove mock-2`, `reopen`, or `quit`. State and remove commands without an ID use `mock-1`. `reopen` is a debug-only control: it closes the panel and checks the pointer again; it is not an adapter protocol message. Closing the simulator ends the connection. Stop the debug app with Ctrl-C in its terminal, or through its menu-bar item.

The debug window shows the received session. On enabled bottom-right masks, working draws a blue dot and waiting draws an orange dot; unknown, an empty snapshot and disconnect clear it. Configuring a mock socket simulates installed hooks: the effective radius is at least 24 pt even with no session or connection. The selected radius remains unchanged; when the two differ, the menu-bar radius label shows both. The application uses a separate debug bundle identifier and preferences. Release builds do not contain the debug client or draw the mock indicator; detection of real installed hooks is not yet implemented.

On macOS 26 and later the debug app also opens a glass session panel when the pointer enters the bottom-right 2R × 2R activation area. Status changes update existing rows in place, and new rows are inserted at the top while the panel grows upward. A removed row remains marked unavailable until the panel closes. If there is no room to grow without moving existing rows, new entries wait until reopening; the indicator still updates immediately. Rows do not open sessions. The panel and input detection are debug-only. For an automated geometry check, set `DISPLAY_CORNERS_DEBUG_SIMULATE_HOVER=1` when running the debug app; this simulates the position and does not test a physical mouse. The app prints the row order and panel frame.

The production hover menu, session navigation, adapter freshness timeouts, reconnect and production agent integrations are not implemented by this prototype. The mock is deliberately interactive and does not infer real agent activity. Manual verification of pointer behavior and actual row positions on a physical display is still needed.

For the separate Codex hook prototype, including the debug settings window, see [Codex hook adapter](../codex-adapter/README.md).
