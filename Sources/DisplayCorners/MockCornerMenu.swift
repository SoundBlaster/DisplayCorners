#if DEBUG
import AppKit
import SwiftUI

@available(macOS 26, *)
@MainActor
final class MockCornerMenu {
    private var sessions: [MockSession] = []
    private var panel: NSPanel?
    private var timer: Timer?
    private var lastInside = Date.distantPast
    private var radius: CGFloat = 36
    private var enabled = false

    func update(sessions: [MockSession], radius: CGFloat, enabled: Bool) {
        self.sessions = sessions
        self.radius = radius
        self.enabled = enabled
        if sessions.isEmpty || !enabled || radius <= 4 {
            hide()
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.checkPointer() }
            }
        }
        if let panel {
            panel.contentView = NSHostingView(rootView: MockSessionList(sessions: sessions, radius: radius))
            print("Mock menu states: \(sessions.map(\.state))")
        }
    }

    private func checkPointer() {
        guard enabled, !sessions.isEmpty else { return }
        let pointer: NSPoint
        if ProcessInfo.processInfo.environment["DISPLAY_CORNERS_DEBUG_SIMULATE_HOVER"] == "1",
           let screen = NSScreen.main {
            pointer = NSPoint(x: screen.frame.maxX - 1, y: screen.frame.minY + 1)
        } else {
            pointer = NSEvent.mouseLocation
        }
        if let panel, panel.frame.contains(pointer) {
            lastInside = Date()
            return
        }
        if let screen = NSScreen.screens.first(where: { screen in
            NSRect(x: screen.frame.maxX - 2 * radius, y: screen.frame.minY,
                   width: 2 * radius, height: 2 * radius).contains(pointer)
        }) {
            lastInside = Date()
            if panel == nil { show(on: screen) }
        } else if panel != nil && Date().timeIntervalSince(lastInside) > 0.35 {
            hide()
        }
    }

    private func show(on screen: NSScreen) {
        let height = CGFloat(max(1, sessions.count)) * 57
        let frame = NSRect(x: screen.frame.maxX - 306 - 4, y: screen.frame.minY + 4,
                           width: 306, height: height)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Mock Agent — Sessions"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: MockSessionList(sessions: sessions, radius: radius))
        window.orderFrontRegardless()
        panel = window
        print("Mock menu opened at \(frame) on screen \(screen.frame)")
    }

    private func hide() {
        if panel != nil { print("Mock menu closed") }
        panel?.orderOut(nil)
        panel = nil
    }
}

@available(macOS 26, *)
private struct MockSessionList: View {
    let sessions: [MockSession]
    let radius: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(sessions, id: \.session_id) { session in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(session.state == "waiting_for_user" ? .orange : session.state == "working" ? .blue : .gray)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(verbatim: session.project ?? "—").fontWeight(.semibold)
                            Spacer(minLength: 8)
                            Image(systemName: "terminal")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Text(verbatim: session.agent ?? "Mock Agent"))
                        }
                        Text(verbatim: session.state)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 57, alignment: .leading)
                .padding(.horizontal, 16)
            }
        }
        .frame(width: 306)
        .glassEffect(.regular, in: UnevenRoundedRectangle(
            topLeadingRadius: max(0, radius - 4), bottomLeadingRadius: max(0, radius - 4),
            bottomTrailingRadius: max(0, radius - 4), topTrailingRadius: max(0, radius - 4)))
    }
}
#endif
