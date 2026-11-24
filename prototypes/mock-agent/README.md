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

3. In the simulator's terminal enter `working`, `waiting`, `unknown`, `remove`, or `quit`. A state command restores a removed session. Closing the simulator ends the connection. Stop the debug app with Ctrl-C in its terminal, or through its menu-bar item.

The debug window shows the received session. On enabled bottom-right masks, working draws a blue dot and waiting draws an orange dot; unknown, an empty snapshot and disconnect clear it. Configuring a mock socket simulates installed hooks: the effective radius is at least 24 pt even with no session or connection. The selected radius remains unchanged; when the two differ, the menu-bar radius label shows both. The application uses a separate debug bundle identifier and preferences. Release builds do not contain the debug client or draw the mock indicator; detection of real installed hooks is not yet implemented.

On macOS 26 and later the debug app also opens a glass session panel when the pointer enters the bottom-right 2R × 2R activation area. It shows the mock session and updates its status; it does not open the session. The panel and input detection are debug-only. For an automated geometry check, set `DISPLAY_CORNERS_DEBUG_SIMULATE_HOVER=1` when running the debug app; this simulates the position and does not test a physical mouse. The app prints the panel and screen frames when it opens.

The production hover menu, stable ordering with multiple sessions, session navigation, adapter freshness timeouts, reconnect and real agent integrations are not implemented by this prototype. The mock is deliberately interactive and does not infer real agent activity. Manual verification on a physical display is still needed.
