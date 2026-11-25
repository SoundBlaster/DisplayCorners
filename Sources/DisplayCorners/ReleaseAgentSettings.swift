#if !DEBUG
import AgentRuntime
import AppKit

@available(macOS 26, *)
@MainActor
final class ReleaseAgentSettings: NSObject {
    private let window: NSWindow
    private let status: NSTextField
    private let installer: CodexInstaller
    private var runtimeError: String?
    var onInstallationChange: ((Bool) -> Void)?

    init?(executable: URL) {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? (NSHomeDirectory() + "/.codex")
        let defaultData = NSHomeDirectory() + "/Library/Application Support/Display Corners/Codex"
        let data = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DISPLAY_CORNERS_AGENT_DATA_DIR"] ?? defaultData)
        installer = CodexInstaller(home: URL(fileURLWithPath: home), data: data, executable: executable)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 210),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        status = NSTextField(wrappingLabelWithString: "")
        super.init()
        window.title = NSLocalizedString("Agent Settings", comment: "Agent settings window title")
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Codex")
        title.font = .boldSystemFont(ofSize: 15)
        title.frame = NSRect(x: 20, y: 160, width: 440, height: 22)
        status.frame = NSRect(x: 20, y: 78, width: 440, height: 75)
        let install = NSButton(title: NSLocalizedString("Install Hooks", comment: "Install Codex hooks"), target: self, action: #selector(installHooks))
        install.frame = NSRect(x: 20, y: 25, width: 190, height: 32)
        let remove = NSButton(title: NSLocalizedString("Remove Hooks", comment: "Remove Codex hooks"), target: self, action: #selector(removeHooks))
        remove.frame = NSRect(x: 220, y: 25, width: 190, height: 32)
        [title, status, install, remove].forEach { window.contentView?.addSubview($0) }
        window.center()
    }

    func show() { refresh(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }

    func refresh() {
        do {
            let state = try installer.status()
            onInstallationChange?(state != .notInstalled)
            if let runtimeError, state != .notInstalled { status.stringValue = runtimeError; return }
            switch state {
            case .installed: status.stringValue = NSLocalizedString("Hooks installed. Review and trust them in Codex. Trust status is not known here.", comment: "Hooks installed; Codex trust is separate")
            case .partial: status.stringValue = NSLocalizedString("Hooks are partially installed. Install again or remove them.", comment: "Partial hook installation")
            case .notInstalled: status.stringValue = NSLocalizedString("Hooks are not installed.", comment: "Codex hooks not installed")
            }
        } catch { status.stringValue = error.localizedDescription }
    }

    func showRuntimeError(_ error: Error) { runtimeError = error.localizedDescription; status.stringValue = error.localizedDescription }
    func clearRuntimeError() { runtimeError = nil }
    @objc private func installHooks() { do { try installer.install(); refresh() } catch { status.stringValue = error.localizedDescription } }
    @objc private func removeHooks() { do { try installer.remove(); runtimeError = nil; refresh() } catch { status.stringValue = error.localizedDescription } }
}
#endif
