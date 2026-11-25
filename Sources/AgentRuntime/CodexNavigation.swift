import Foundation
import SessionList

public enum CodexNavigation {
    public static func url(for row: VisibleSession) -> URL? {
        guard row.isAvailable, row.session.agent == "Codex",
              let id = UUID(uuidString: row.session.session_id) else { return nil }
        return URL(string: "codex://threads/\(id.uuidString.lowercased())")
    }
}
