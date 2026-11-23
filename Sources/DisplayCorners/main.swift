import AppKit
import CornerGeometry

@MainActor
final class CornerView: NSView {
    let corner: Corner

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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    @objc private func screensChanged() { refreshWindows() }

    private func refreshWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard enabled else { return }
        for screen in NSScreen.screens {
            for corner in Corner.allCases where corner.isTop ? showTop : showBottom {
                let frame = corner.frame(on: screen.frame, radius: CGFloat(radius))
                let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                window.hidesOnDeactivate = false
                window.contentView = CornerView(corner: corner, frame: NSRect(origin: .zero, size: frame.size))
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
        addToggle(to: menu, title: "Скругления включены", action: #selector(toggleEnabled), on: enabled)
        addToggle(to: menu, title: "Верхние углы", action: #selector(toggleTop), on: showTop)
        addToggle(to: menu, title: "Нижние углы", action: #selector(toggleBottom), on: showBottom)
        menu.addItem(.separator())
        let label = NSMenuItem(title: "Радиус: \(Int(radius)) pt", action: nil, keyEquivalent: "")
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
        let quit = NSMenuItem(title: "Завершить Display Corners", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
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
        statusItem.menu?.item(at: 6)?.title = "Радиус: \(Int(radius)) pt"
        refreshWindows()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
