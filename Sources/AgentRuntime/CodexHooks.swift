import Darwin
import Foundation

public enum CodexHook {
    public static let events = ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd"]

    public static func socketURL() -> URL {
        URL(fileURLWithPath: "/tmp/displaycorners-\(getuid())", isDirectory: true).appendingPathComponent("events.sock")
    }

    public static func payload(_ input: Data) -> Data? {
        guard let value = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              value["agent_id"] == nil || value["agent_id"] is NSNull,
              let event = value["hook_event_name"] as? String, events.contains(event),
              let id = value["session_id"] as? String, !id.isEmpty else { return nil }
        var output: [String: Any] = ["event": event, "session_id": id]
        if let cwd = value["cwd"] as? String, !cwd.isEmpty { output["project"] = URL(fileURLWithPath: cwd).lastPathComponent }
        return try? JSONSerialization.data(withJSONObject: output)
    }

    public static func run() {
        defer { FileHandle.standardOutput.write(Data("{}\n".utf8)) }
        send(FileHandle.standardInput.readDataToEndOfFile(), to: socketURL())
    }

    public static func send(_ input: Data, to url: URL) {
        guard let message = payload(input) else { return }
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        guard var address = socketAddress(url) else { return }
        message.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(descriptor, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
    }
}

func socketAddress(_ url: URL) -> sockaddr_un? {
    let bytes = Array(url.path.utf8CString)
    var address = sockaddr_un()
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        for (index, byte) in bytes.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
    }
    return address
}

public struct CodexInstaller {
    public enum State: String { case installed, partial, notInstalled }
    private let home: URL
    private let data: URL
    private let executable: URL

    public init(home: URL, data: URL, executable: URL) {
        self.home = home; self.data = data; self.executable = executable
    }

    private var configURL: URL { home.appendingPathComponent("hooks.json").resolvingSymlinksInPath() }
    private var helper: URL { data.appendingPathComponent("hook") }
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private var command: String { "\(quote(helper.path)) --displaycorners-codex-hook" }

    private func load() throws -> [String: Any] {
        let original = home.appendingPathComponent("hooks.json")
        var info = stat()
        if lstat(original.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK,
           !FileManager.default.fileExists(atPath: original.path) {
            throw CocoaError(.fileReadNoSuchFile)
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else { return ["hooks": [String: Any]() ] }
        guard let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any],
              json["hooks"] == nil || json["hooks"] is [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        return json
    }

    private func contains(_ value: Any?) throws -> Bool {
        guard let value else { return false }
        guard let groups = value as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        return try groups.contains { group in
            guard let hooks = group["hooks"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
            return hooks.contains { $0["command"] as? String == command }
        }
    }

    public func status() throws -> State {
        let hooks = try load()["hooks"] as? [String: Any] ?? [:]
        let found = try CodexHook.events.filter { try contains(hooks[$0]) }.count
        return found == CodexHook.events.count ? .installed : found > 0 ? .partial : .notInstalled
    }

    public func install() throws {
        var json = try load()
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        for event in CodexHook.events {
            if try !contains(hooks[event]) {
                var groups = hooks[event] as? [[String: Any]] ?? []
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 2]]])
                hooks[event] = groups
            }
        }
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = data.appendingPathComponent(".hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: executable, to: temporary)
        if rename(temporary.path, helper.path) != 0 { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        json["hooks"] = hooks
        try save(json)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        var json = try load()
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        for event in CodexHook.events where hooks[event] != nil {
            guard try contains(hooks[event]) else { continue }
            guard let groups = hooks[event] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
            var updated: [[String: Any]] = []
            for var group in groups {
                let old = group["hooks"] as? [[String: Any]] ?? []
                let remaining = old.filter { $0["command"] as? String != command }
                if remaining.count == old.count { updated.append(group) }
                else if !remaining.isEmpty { group["hooks"] = remaining; updated.append(group) }
            }
            if updated.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = updated }
        }
        json["hooks"] = hooks
        try save(json)
    }

    private func save(_ json: [String: Any]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let permissions = (try? manager.attributesOfItem(atPath: configURL.path)[.posixPermissions]) as? NSNumber ?? NSNumber(value: 0o600)
        let contents = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try contents.write(to: configURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: configURL.path)
    }
}
