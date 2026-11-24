#if DEBUG
import AppKit
import Network

struct MockSession: Decodable {
    let session_id: String
    let state: String
    let project: String?
    let agent: String?
}

private struct MockMessage: Decodable {
    let type: String
    let sessions: [MockSession]?
    let session: MockSession?
    let session_id: String?
}

@MainActor
final class MockDebugClient {
    private let connection: NWConnection
    private var buffer = Data()
    private var sessions: [String: MockSession] = [:]
    private let window: NSWindow
    private let label: NSTextField
    var onChange: ((String?) -> Void)?

    init(path: String) {
        connection = NWConnection(to: .unix(path: path), using: .tcp)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        label = NSTextField(wrappingLabelWithString: "Connecting to mock agent…")
        window.title = "Mock Agent — Debug"
        window.isReleasedWhenClosed = false
        label.frame = NSRect(x: 20, y: 25, width: 360, height: 110)
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        window.contentView?.addSubview(label)
        window.center()
    }

    func start() {
        window.makeKeyAndOrderFront(nil)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.label.stringValue = "Connected — waiting for snapshot"
                    self.connection.send(content: Data("{\"type\":\"snapshot_request\"}\n".utf8), completion: .contentProcessed { _ in })
                    self.receive()
                case .failed(let error): self.disconnect("Connection failed: \(error)")
                case .cancelled: self.disconnect("Disconnected")
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data { self.consume(data) }
                if complete || error != nil { self.disconnect("Disconnected — state unknown") }
                else { self.receive() }
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = try? JSONDecoder().decode(MockMessage.self, from: line) else { continue }
            switch message.type {
            case "snapshot": sessions = Dictionary(uniqueKeysWithValues: (message.sessions ?? []).map { ($0.session_id, $0) })
            case "update": if let session = message.session { sessions[session.session_id] = session }
            case "remove": if let id = message.session_id { sessions.removeValue(forKey: id) }
            default: continue
            }
            render()
        }
    }

    private func render() {
        let ordered = sessions.values.sorted { $0.session_id < $1.session_id }
        let lines = ordered.map { "\($0.project ?? "—") · \($0.agent ?? "—")\n\($0.session_id): \($0.state)" }
        label.stringValue = (["Connected to Mock Agent"] + (lines.isEmpty ? ["No sessions"] : lines)).joined(separator: "\n\n")
        let states = ordered.map(\.state)
        onChange?(states.contains("waiting_for_user") ? "waiting_for_user" : states.contains("working") ? "working" : nil)
    }

    private func disconnect(_ message: String) {
        sessions.removeAll()
        label.stringValue = message
        onChange?(nil)
    }
}
#endif
