import Foundation
import SessionList
import XCTest
@testable import AgentRuntime

final class CodexHooksTests: XCTestCase {
    func testNavigationUsesSelectedSessionAndRejectsUnavailableRows() throws {
        let first = AgentSession(id: "11111111-1111-4111-8111-111111111111", state: "working", agent: "Codex")
        let second = AgentSession(id: "22222222-2222-4222-8222-222222222222", state: "unknown", agent: "Codex")
        var list = VisibleSessionList()
        list.open([first, second])
        XCTAssertEqual(CodexNavigation.url(for: list.rows[0])?.absoluteString, "codex://threads/\(first.id)")
        XCTAssertEqual(CodexNavigation.url(for: list.rows[1])?.absoluteString, "codex://threads/\(second.id)")
        list.update([second], capacity: 2)
        XCTAssertNil(CodexNavigation.url(for: list.rows[0]))
        XCTAssertEqual(CodexNavigation.url(for: list.rows[1])?.absoluteString, "codex://threads/\(second.id)")
    }

    func testNavigationRejectsOtherAgentsAndUnsafeIdentifiers() {
        var list = VisibleSessionList()
        list.open([
            AgentSession(id: "11111111-1111-4111-8111-111111111111", state: "working", agent: "Claude"),
            AgentSession(id: "11111111-1111-4111-8111-111111111111?view=review", state: "working", agent: "Codex"),
            AgentSession(id: "preview", state: "working", agent: "Codex"),
        ])
        XCTAssertTrue(list.rows.allSatisfy { CodexNavigation.url(for: $0) == nil })
    }

    @MainActor
    func testHookEventReachesMonitor() async throws {
        let directory = URL(fileURLWithPath: "/tmp/dc-test-\(getpid())-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("events.sock")
        let monitor = CodexMonitor(socketURL: socket)
        let received = expectation(description: "working session")
        monitor.onChange = { sessions in
            if sessions.contains(where: { $0.session_id == "s1" && $0.state == "working" }) { received.fulfill() }
        }
        try monitor.start()
        defer { monitor.stop() }
        CodexHook.send(try JSONSerialization.data(withJSONObject: ["session_id": "s1", "hook_event_name": "PostToolUse"]), to: socket)
        await fulfillment(of: [received], timeout: 3)
    }

    @MainActor
    func testHookSessionIDBecomesNavigationTarget() async throws {
        let directory = URL(fileURLWithPath: "/tmp/dc-nav-\(getpid())-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("events.sock")
        let monitor = CodexMonitor(socketURL: socket)
        let received = expectation(description: "hook session is navigable")
        let id = "33333333-3333-4333-8333-333333333333"
        monitor.onChange = { sessions in
            guard let session = sessions.first(where: { $0.id == id }) else { return }
            var list = VisibleSessionList()
            list.open([session])
            XCTAssertEqual(CodexNavigation.url(for: list.rows[0])?.absoluteString, "codex://threads/\(id)")
            received.fulfill()
        }
        try monitor.start()
        defer { monitor.stop() }
        CodexHook.send(try JSONSerialization.data(withJSONObject: ["session_id": id, "hook_event_name": "PostToolUse"]), to: socket)
        await fulfillment(of: [received], timeout: 3)
    }

    func testHookFiltersSensitiveFieldsAndSubagents() throws {
        let input: [String: Any] = ["session_id": "s1", "hook_event_name": "PostToolUse", "cwd": "/tmp/Project", "prompt": "private"]
        let data = try JSONSerialization.data(withJSONObject: input)
        let result = try XCTUnwrap(CodexHook.payload(data))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: String])
        XCTAssertEqual(object, ["session_id": "s1", "event": "PostToolUse", "project": "Project"])
        var subagent = input; subagent["agent_id"] = "child"
        XCTAssertNil(CodexHook.payload(try JSONSerialization.data(withJSONObject: subagent)))
    }

    func testInstallAndRemovePreserveOtherHooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let home = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let path = home.appendingPathComponent("hooks.json")
        let existing: [String: Any] = ["hooks": ["PostToolUse": [["hooks": [["type": "command", "command": "echo unchanged"]]]]]]
        try JSONSerialization.data(withJSONObject: existing).write(to: path)
        let installer = CodexInstaller(home: home, data: root.appendingPathComponent("data"), executable: URL(fileURLWithPath: "/usr/bin/true"))
        XCTAssertEqual(try installer.status(), .notInstalled)
        try installer.install(); try installer.install()
        XCTAssertEqual(try installer.status(), .installed)
        try installer.remove()
        XCTAssertEqual(try installer.status(), .notInstalled)
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? NSDictionary)
        XCTAssertEqual(actual, existing as NSDictionary)
    }

    func testInvalidConfigurationIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("hooks.json")
        try Data("{invalid".utf8).write(to: path)
        let installer = CodexInstaller(home: root, data: root.appendingPathComponent("data"), executable: URL(fileURLWithPath: "/usr/bin/true"))
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try Data(contentsOf: path), Data("{invalid".utf8))
    }

    func testExistingConfigurationSymlinkIsPreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("shared.json")
        try Data("{\"hooks\":{}}".utf8).write(to: target)
        let link = root.appendingPathComponent("hooks.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let installer = CodexInstaller(home: root, data: root.appendingPathComponent("data"), executable: URL(fileURLWithPath: "/usr/bin/true"))
        try installer.install()
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        try installer.remove()
        XCTAssertEqual(try installer.status(), .notInstalled)
    }

    func testTitleLookupReadsOnlyThreadName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        read first
        echo '{"id":1,"result":{}}'
        read second
        read third
        echo '{"id":2,"result":{"thread":{"name":"Actual chat","preview":"private prompt"}}}'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        XCTAssertEqual(CodexTitle.read("s1", executable: executable), "Actual chat")
    }

    func testBrokenConfigurationSymlinkIsNotReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("hooks.json")
        let target = root.appendingPathComponent("missing.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let installer = CodexInstaller(home: root, data: root.appendingPathComponent("data"), executable: URL(fileURLWithPath: "/usr/bin/true"))
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
    }
}
