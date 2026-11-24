import AppKit
import CornerGeometry
#if DEBUG
import SessionList
#endif

@MainActor
final class CornerView: NSView {
    let corner: Corner
    #if DEBUG
    var mockState: String?
    #endif

    init(corner: Corner, frame: NSRect) {
        self.corner = corner
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds.width
        let k: CGFloat = 0.5522847498307936
        context.saveGState()
        context.translateBy(x: corner.isRight ? r : 0, y: corner.isTop ? r : 0)
        context.scaleBy(x: corner.isRight ? -1 : 1, y: corner.isTop ? -1 : 1)
        context.setFillColor(NSColor.black.cgColor)
        context.move(to: .zero)
        context.addLine(to: CGPoint(x: r, y: 0))
        context.addCurve(to: CGPoint(x: 0, y: r),
                         control1: CGPoint(x: r * (1 - k), y: 0),
                         control2: CGPoint(x: 0, y: r * (1 - k)))
        context.closePath()
        context.fillPath()
        context.restoreGState()
        #if DEBUG
        if corner == .bottomRight, let mockState, r >= CornerRadius.minimumForAgent {
            (mockState == "waiting_for_user" ? NSColor.systemOrange : NSColor.systemBlue).setFill()
            NSBezierPath(ovalIn: NSRect(x: r - 7, y: 2, width: 5, height: 5)).fill()
        }
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var windows: [NSWindow] = []
    private var enabled = true
    private var showTop = true
    private var showBottom = true
    private var radius: Double = 36
    #if DEBUG
    private var mockClient: MockDebugClient?
    private var mockState: String?
    private var mockSessions: [AgentSession] = []
    private var mockMenu: AnyObject?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateSettings()
        defaults.register(defaults: ["enabled": true, "showTop": true, "showBottom": true, "radius": 36.0])
        enabled = defaults.bool(forKey: "enabled")
        showTop = defaults.bool(forKey: "showTop")
        showBottom = defaults.bool(forKey: "showBottom")
        radius = min(120, max(4, defaults.double(forKey: "radius")))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.roundedtop", accessibilityDescription: "Display Corners")
        statusItem.button?.image?.isTemplate = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        rebuildMenu()
        refreshWindows()
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["DISPLAY_CORNERS_MOCK_SOCKET"], !path.isEmpty {
            print("Mock radius: selected \(radius) pt, effective \(effectiveRadius) pt")
            let client = MockDebugClient(path: path)
            if #available(macOS 26, *) { mockMenu = MockCornerMenu() }
            client.onChange = { [weak self] sessions in
                guard let self else { return }
                self.mockSessions = sessions
                let states = sessions.map(\.state)
                self.mockState = states.contains("waiting_for_user") ? "waiting_for_user" : states.contains("working") ? "working" : nil
                self.refreshWindows()
            }
            client.onReopen = { [weak self] in
                if #available(macOS 26, *), let menu = self?.mockMenu as? MockCornerMenu {
                    menu.reopenForDebug()
                }
            }
            mockClient = client
            client.start()
        }
        #endif
    }

    private func migrateSettings() {
        let current = defaults.persistentDomain(forName: "ru.egormerkushev.displaycorners") ?? [:]
        guard current["migratedPreviousSettings"] == nil else { return }
        let previous = defaults.persistentDomain(forName: "local.displaycorners.app") ?? [:]
        for key in ["enabled", "showTop", "showBottom", "radius"] where current[key] == nil {
            if let value = previous[key] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "migratedPreviousSettings")
    }

    @objc private func screensChanged() { refreshWindows() }

    private var effectiveRadius: CGFloat {
        #if DEBUG
        let hasHooks = !(ProcessInfo.processInfo.environment["DISPLAY_CORNERS_MOCK_SOCKET"] ?? "").isEmpty
        #else
        let hasHooks = false
        #endif
        return CornerRadius.effective(selected: CGFloat(radius), agentHooksInstalled: hasHooks)
    }

    private func refreshWindows() {
        #if DEBUG
        if #available(macOS 26, *), let menu = mockMenu as? MockCornerMenu {
            menu.update(sessions: mockSessions, radius: effectiveRadius, enabled: enabled && showBottom)
        }
        #endif
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard enabled else { return }
        for screen in NSScreen.screens {
            for corner in Corner.allCases where corner.isTop ? showTop : showBottom {
                let frame = corner.frame(on: screen.frame, radius: effectiveRadius)
                let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                window.hidesOnDeactivate = false
                let view = CornerView(corner: corner, frame: NSRect(origin: .zero, size: frame.size))
                #if DEBUG
                view.mockState = mockState
                #endif
                window.contentView = view
                window.orderFrontRegardless()
                windows.append(window)
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Display Corners", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        addToggle(to: menu, title: NSLocalizedString("Rounded corners enabled", comment: "Toggle all corner masks"), action: #selector(toggleEnabled), on: enabled)
        addToggle(to: menu, title: NSLocalizedString("Top corners", comment: "Toggle the top corner masks"), action: #selector(toggleTop), on: showTop)
        addToggle(to: menu, title: NSLocalizedString("Bottom corners", comment: "Toggle the bottom corner masks"), action: #selector(toggleBottom), on: showBottom)
        menu.addItem(.separator())
        let label = NSMenuItem(title: radiusTitle, action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(label)
        let sliderItem = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        let slider = NSSlider(value: radius, minValue: 4, maxValue: 120, target: self, action: #selector(changeRadius(_:)))
        slider.frame = NSRect(x: 16, y: 3, width: 188, height: 24)
        slider.isContinuous = true
        container.addSubview(slider)
        sliderItem.view = container
        menu.addItem(sliderItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: NSLocalizedString("Quit Display Corners", comment: "Quit the application"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private var radiusTitle: String {
        let title = String.localizedStringWithFormat(
            NSLocalizedString("Radius: %lld pt", comment: "Corner radius in points"), Int64(radius)
        )
        #if DEBUG
        if effectiveRadius != CGFloat(radius) {
            return "\(title) → \(Int(effectiveRadius)) pt"
        }
        #endif
        return title
    }

    private func addToggle(to menu: NSMenu, title: String, action: Selector, on: Bool) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        menu.addItem(item)
    }

    @objc private func toggleEnabled() { enabled.toggle(); defaults.set(enabled, forKey: "enabled"); rebuildMenu(); refreshWindows() }
    @objc private func toggleTop() { showTop.toggle(); defaults.set(showTop, forKey: "showTop"); rebuildMenu(); refreshWindows() }
    @objc private func toggleBottom() { showBottom.toggle(); defaults.set(showBottom, forKey: "showBottom"); rebuildMenu(); refreshWindows() }
    @objc private func changeRadius(_ sender: NSSlider) {
        radius = sender.doubleValue.rounded()
        defaults.set(radius, forKey: "radius")
        // Keep the slider alive while it is being dragged.
        statusItem.menu?.item(at: 6)?.title = radiusTitle
        refreshWindows()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
