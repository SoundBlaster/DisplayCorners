#if DEBUG
import AppKit

@MainActor
final class CodexSettings: NSObject {
    private let window: NSWindow
    private let status: NSTextField
    private let installer: URL
    let dataDirectory: URL
    private let codexHome: URL
    private var runtimeError: String?
    var onInstallationChange: ((Bool) -> Void)?

    init?(resources: URL) {
        let environment = ProcessInfo.processInfo.environment
        let home = environment["DISPLAY_CORNERS_CODEX_HOME"] ?? environment["CODEX_HOME"] ?? (NSHomeDirectory() + "/.codex")
        codexHome = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
        let support = environment["DISPLAY_CORNERS_CODEX_DATA_DIR"] ?? (NSHomeDirectory() + "/Library/Application Support/Display Corners Debug/Codex")
        dataDirectory = URL(fileURLWithPath: support, isDirectory: true).standardizedFileURL
        installer = resources.appendingPathComponent("CodexAdapter/install.py")
        guard FileManager.default.fileExists(atPath: installer.path) else { return nil }
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
        window.contentView?.addSubview(title)
        window.contentView?.addSubview(status)
        window.contentView?.addSubview(install)
        window.contentView?.addSubview(remove)
        window.center()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        switch run("status") {
        case .success(let result):
            display(result)
            onInstallationChange?(result == "installed" || result == "partial")
        case .failure(let error): status.stringValue = error.localizedDescription
        }
    }

    func showRuntimeError(_ message: String) {
        runtimeError = message
        status.stringValue = message
    }

    func clearRuntimeError() { runtimeError = nil }

    @objc private func installHooks() { change("install") }
    @objc private func removeHooks() { change("remove") }

    private func change(_ action: String) {
        switch run(action) {
        case .success(let result):
            display(result)
            onInstallationChange?(result == "installed" || result == "partial")
        case .failure(let error): status.stringValue = error.localizedDescription
        }
    }

    private func display(_ result: String) {
        if result == "installed", let runtimeError {
            status.stringValue = runtimeError
            return
        }
        switch result {
        case "installed": status.stringValue = NSLocalizedString("Hooks installed. Review and trust them in Codex. Trust status is not known here.", comment: "Hooks installed; Codex trust is separate")
        case "partial": status.stringValue = NSLocalizedString("Hooks are partially installed. Install again or remove them.", comment: "Partial hook installation")
        default: status.stringValue = NSLocalizedString("Hooks are not installed.", comment: "Codex hooks not installed")
        }
    }

    private func run(_ action: String) -> Result<String, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [installer.path, action, "--home", codexHome.path, "--data", dataDirectory.path]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
            let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let diagnostic = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                return .failure(NSError(domain: "CodexSettings", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: diagnostic]))
            }
            return .success(message)
        } catch { return .failure(error) }
    }
}
#endif
