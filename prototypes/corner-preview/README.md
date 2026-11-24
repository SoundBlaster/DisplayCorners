# Agent Corner: visual prototype

A standalone SwiftUI mock for reviewing a possible agent corner. It does not change DisplayCorners or read real agent sessions. Requires macOS 26 and a matching Swift toolchain.

Build to a directory outside the checkout, then open the app:

```sh
OUTPUT_DIR=/path/to/build/directory ./prototypes/corner-preview/build.sh
open '/path/to/build/directory/Agent Corner Preview.app'
```

The mock is a window representing a display; its lower-right black wedge contains the indicator. The intended hover target is the 48 × 48 pt area in that corner; automated hover verification was inconclusive. The checkbox also shows the menu for visual review. The example sessions and statuses are static, and the rows have no action.

## Preliminary requirements to review

- Place a small status indicator in the existing black display corner, where present.
- Activate the list when the pointer reaches a square of side 2R, where R is the display corner radius.
- Use a restrained system glass material and concentric geometry: this mock uses R = 24 pt, inset = 4 pt, and menu corner radius = 20 pt. These values are for evaluation, not universal hardware measurements.
- Distinguish working and waiting states using text as well as color.
- When the list is opened, place newer sessions below older ones. While it stays open, do not reorder existing rows; insert newly arriving sessions at the top. The final UI must keep the row under the pointer stable when insertions would otherwise shift it; the mechanism remains to be prototyped.
- Agent data should come through adapters; this mock has no adapter integration. SessionMonitor is a visual example only, not a dependency.

The real screen overlay, multiple displays, dynamic list updates, interaction with actual sessions, accessibility, and hover reliability in the final app remain to be designed and verified. Quick actions and a Notification Center-style stack are deferred.
