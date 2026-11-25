#if compiler(>=6.2)
import Darwin
import Foundation
import Testing
@testable import AgentRuntime

@Test("A closed app-server input does not terminate the host process")
func closedAppServerInputDoesNotTerminateHost() async {
    await #expect(processExitsWith: .success) {
        signal(SIGPIPE, SIG_DFL)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        IFS= read -r request || exit 1
        exec 0<&-
        printf '%s\\n' '{"id":1,"result":{}}'
        exec sleep 30
        """
        try! Data(script.utf8).write(to: executable)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let result = CodexTitle.read("session", executable: executable)
        if result != nil { exit(1) }
    }
}
#endif
