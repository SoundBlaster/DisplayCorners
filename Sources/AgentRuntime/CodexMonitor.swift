import Darwin
import Foundation
import SessionList

private struct HookEvent: Decodable {
    let event: String
    let session_id: String
    let project: String?
}

@MainActor
public final class CodexMonitor {
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var timer: Timer?
    private var sessions = SessionTracker()
    private var records: [String: (session: AgentSession, deadline: Date)] = [:]
    private var titleRequests = Set<String>()
    private var titleCache: [String: String] = [:]
    private var titleRetryAfter: [String: Date] = [:]
    private let socketURL: URL
    public var onChange: (([AgentSession]) -> Void)?

    public init(socketURL: URL = CodexHook.socketURL()) { self.socketURL = socketURL }

    public func start() throws {
        guard descriptor < 0 else { return }
        let url = socketURL
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        guard var address = socketAddress(url) else { throw CocoaError(.fileWriteInvalidFileName) }
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        func bindSocket() -> Int32 {
            withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            } }
        }
        if bindSocket() != 0 {
            let bindError = errno
            if bindError == EADDRINUSE {
                let probe = socket(AF_UNIX, SOCK_DGRAM, 0)
                let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                } }
                let probeError = errno
                if probe >= 0 { close(probe) }
                if connected != 0 && probeError == ECONNREFUSED && lstat(url.path, &info) == 0 &&
                    (info.st_mode & S_IFMT) == S_IFSOCK && info.st_uid == getuid() {
                    _ = unlink(url.path)
                    if bindSocket() == 0 { activate(fd, url); return }
                }
            }
            close(fd)
            throw POSIXError(.init(rawValue: bindError) ?? .EIO)
        }
        activate(fd, url)
    }

    private func activate(_ fd: Int32, _ url: URL) {
        descriptor = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.receive() }
        source.setCancelHandler { close(fd); unlink(url.path) }
        self.source = source
        source.resume()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.expire() }
        }
    }

    private func receive() {
        var bytes = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = recv(descriptor, &bytes, bytes.count, 0)
            guard count > 0 else { break }
            guard let event = try? JSONDecoder().decode(HookEvent.self, from: Data(bytes.prefix(count))),
                  CodexHook.events.contains(event.event), !event.session_id.isEmpty else { continue }
            if ["Stop", "Interrupt", "SessionEnd"].contains(event.event) {
                records.removeValue(forKey: event.session_id)
                sessions.remove(id: event.session_id)
                onChange?(sessions.ordered)
                continue
            }
            let old = records[event.session_id]?.session
            let state = event.event == "PostToolUse" ? "working" : "unknown"
            let session = AgentSession(id: event.session_id, state: state, project: event.project ?? old?.project,
                                       agent: "Codex", title: old?.title ?? titleCache[event.session_id])
            records[event.session_id] = (session, Date().addingTimeInterval(60))
            sessions.update(session)
            onChange?(sessions.ordered)
            if Date() >= (titleRetryAfter[event.session_id] ?? .distantPast) && titleRequests.insert(event.session_id).inserted {
                let id = event.session_id
                titleRetryAfter[id] = Date().addingTimeInterval(60)
                Task.detached { [weak self] in
                    let title = CodexTitle.read(id)
                    await self?.applyTitle(title, id: id)
                }
            }
        }
    }

    private func applyTitle(_ title: String?, id: String) {
        titleRequests.remove(id)
        guard let title else { return }
        titleCache[id] = title
        guard let entry = records[id] else { return }
        let old = entry.session
        let updated = AgentSession(id: id, state: old.state, project: old.project, agent: old.agent, title: title)
        records[id] = (updated, entry.deadline)
        sessions.update(updated)
        onChange?(sessions.ordered)
    }

    private func expire() {
        let now = Date()
        for (id, entry) in records where entry.session.state == "working" && entry.deadline <= now {
            let old = entry.session
            let updated = AgentSession(id: id, state: "unknown", project: old.project, agent: old.agent, title: old.title)
            records[id] = (updated, entry.deadline)
            sessions.update(updated)
            onChange?(sessions.ordered)
        }
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        source?.cancel(); source = nil
        descriptor = -1
        records.removeAll()
        sessions.replace(with: [])
        onChange?([])
    }
}
