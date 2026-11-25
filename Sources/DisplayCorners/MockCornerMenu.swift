import AppKit
import CornerGeometry
import Observation
import SessionList
import SwiftUI

@available(macOS 26, *)
@MainActor @Observable
private final class MockRowsModel {
    var rows: [VisibleSession] = []
    var radius: CGFloat = 24
    var height: CGFloat = 57
}

@available(macOS 26, *)
@MainActor
final class MockCornerMenu {
    private let rowHeight: CGFloat = 57
    private var sessions: [AgentSession] = []
    private var visible = VisibleSessionList()
    private let model = MockRowsModel()
    private var panel: NSPanel?
    private var screenFrame: NSRect = .zero
    private var timer: Timer?
    private var lastInside = Date.distantPast
    private var radius: CGFloat = 36
    private var enabled = false
    #if DEBUG
    private let fixture = ProcessInfo.processInfo.environment["DISPLAY_CORNERS_DEBUG_FIXTURE"] == "1"
    private let simulatedHover = ProcessInfo.processInfo.environment["DISPLAY_CORNERS_DEBUG_SIMULATE_HOVER"] == "1"
    #else
    private let fixture = false
    private let simulatedHover = false
    #endif

    private var capacity: Int {
        let actualRadius = AgentMenuGeometry.maskRadius(radius, on: screenFrame)
        let inset = AgentMenuGeometry.edgeInset(maskRadius: actualRadius)
        return max(1, Int((screenFrame.height - inset - 4) / rowHeight))
    }

    func update(sessions: [AgentSession], radius: CGFloat, enabled: Bool) {
        let displayedSessions = fixture
            ? [AgentSession(id: "preview", state: "working", agent: "Codex", title: "GitView (debug preview)")]
            : sessions
        self.sessions = displayedSessions
        self.radius = radius
        self.enabled = enabled
        if !enabled || radius <= 4 {
            hide()
            timer?.invalidate()
            timer = nil
            return
        }
        if panel != nil {
            visible.update(displayedSessions, capacity: capacity)
            refreshPanel()
        }
        if displayedSessions.isEmpty && panel == nil {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.checkPointer() }
            }
        }
    }

    private func checkPointer() {
        guard enabled, !sessions.isEmpty || panel != nil else { return }
        let pointer: NSPoint
        if (fixture || simulatedHover),
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
            let actualRadius = AgentMenuGeometry.maskRadius(radius, on: screen.frame)
            return NSRect(x: screen.frame.maxX - 2 * actualRadius, y: screen.frame.minY,
                          width: 2 * actualRadius, height: 2 * actualRadius).contains(pointer)
        }) {
            lastInside = Date()
            if panel == nil && !sessions.isEmpty { show(on: screen) }
        } else if panel != nil && Date().timeIntervalSince(lastInside) > 0.35 {
            hide()
            if sessions.isEmpty { timer?.invalidate(); timer = nil }
        }
    }

    private func show(on screen: NSScreen) {
        screenFrame = screen.frame
        visible.open(sessions)
        let actualRadius = AgentMenuGeometry.maskRadius(radius, on: screenFrame)
        let inset = AgentMenuGeometry.edgeInset(maskRadius: actualRadius)
        let height = AgentMenuGeometry.height(rowCount: min(visible.rows.count, capacity),
                                              rowHeight: rowHeight, maskRadius: actualRadius)
        let frame = NSRect(x: screen.frame.maxX - 306 - inset, y: screen.frame.minY + inset,
                           width: 306, height: height)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Mock Agent — Sessions"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: MockSessionList(model: model))
        panel = window
        refreshPanel()
        window.orderFrontRegardless()
        #if DEBUG
        print("Mock menu opened at \(frame) on screen \(screen.frame)")
        #endif
    }

    private func refreshPanel() {
        guard let panel else { return }
        let actualRadius = AgentMenuGeometry.maskRadius(radius, on: screenFrame)
        let inset = AgentMenuGeometry.edgeInset(maskRadius: actualRadius)
        let height = AgentMenuGeometry.height(rowCount: min(visible.rows.count, capacity),
                                              rowHeight: rowHeight, maskRadius: actualRadius)
        var frame = panel.frame
        frame.origin.x = screenFrame.maxX - frame.width - inset
        frame.origin.y = screenFrame.minY + inset
        frame.size.height = height
        panel.setFrame(frame, display: true)
        model.rows = visible.rows
        model.radius = actualRadius
        model.height = height
        #if DEBUG
        print("Mock menu rows: \(visible.rows.map { "\($0.id):\($0.isAvailable ? $0.session.state : "unavailable")" }), frame: \(frame)")
        #endif
    }

    private func hide() {
        #if DEBUG
        if panel != nil { print("Mock menu closed") }
        #endif
        panel?.orderOut(nil)
        panel = nil
        visible.close()
    }

    func reopenForDebug() {
        hide()
        if sessions.isEmpty { timer?.invalidate(); timer = nil; return }
        checkPointer()
    }
}

@available(macOS 26, *)
private struct MockSessionList: View {
    let model: MockRowsModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(model.rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(!row.isAvailable ? .gray : row.session.state == "waiting_for_user" ? .orange : row.session.state == "working" ? .blue : .gray)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                if let title = row.session.title {
                                    Text(verbatim: title).fontWeight(.semibold).lineLimit(1)
                                } else {
                                    Text("Untitled session", comment: "Session title unavailable")
                                        .fontWeight(.semibold).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                if row.session.agent == "Codex",
                                   let url = Bundle.main.url(forResource: "codex", withExtension: "png"),
                                   let icon = NSImage(contentsOf: url) {
                                    Image(nsImage: icon)
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 17, height: 17)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Codex")
                                } else {
                                    Image(systemName: "terminal")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(Text(verbatim: row.session.agent ?? "Mock Agent"))
                                }
                            }
                            Text(verbatim: row.isAvailable ? row.session.state : "unavailable")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 13))
                    .frame(height: 57)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }
            }
            .frame(minHeight: model.height, alignment: .bottom)
        }
        .frame(width: 306, height: model.height)
        .glassEffect(.regular, in: RoundedRectangle(
            cornerRadius: AgentMenuGeometry.menuRadius(maskRadius: model.radius), style: .circular))
    }
}
