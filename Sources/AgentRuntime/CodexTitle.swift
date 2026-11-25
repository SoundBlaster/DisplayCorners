import Darwin
import Foundation

enum CodexTitle {
    static func read(_ id: String, executable override: URL? = nil) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin"]
        guard let executable = override ?? paths.map({ URL(fileURLWithPath: $0).appendingPathComponent("codex") })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = paths.joined(separator: ":")
        process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                usleep(100_000)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
        }
        func send(_ object: [String: Any]) -> Bool {
            guard var data = try? JSONSerialization.data(withJSONObject: object) else { return false }
            data.append(10)
            do { try input.fileHandleForWriting.write(contentsOf: data); return true } catch { return false }
        }
        guard send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "displaycorners", "version": "1.0"]]]) else { return nil }
        let deadline = Date().addingTimeInterval(5)
        var buffer = Data()
        let fd = output.fileHandleForReading.fileDescriptor
        while Date() < deadline {
            var pollDescriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = max(0, Int32(deadline.timeIntervalSinceNow * 1000))
            guard poll(&pollDescriptor, 1, remaining) > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count < 2_000_000 else { return nil }
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let replyID = message["id"] as? Int else { continue }
                if replyID == 1 {
                    guard message["result"] != nil,
                          send(["method": "initialized", "params": [:]]),
                          send(["id": 2, "method": "thread/read", "params": ["threadId": id, "includeTurns": false]]) else { return nil }
                } else if replyID == 2 {
                    let result = message["result"] as? [String: Any]
                    let thread = result?["thread"] as? [String: Any]
                    let name = (thread?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name?.isEmpty == false ? name : nil
                }
            }
        }
        return nil
    }
}
