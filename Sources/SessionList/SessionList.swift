import Foundation

public struct AgentSession: Decodable, Equatable, Identifiable {
    public let session_id: String
    public let state: String
    public let project: String?
    public let agent: String?
    public let title: String?
    public var id: String { session_id }

    public init(id: String, state: String, project: String? = nil, agent: String? = nil, title: String? = nil) {
        self.session_id = id
        self.state = state
        self.project = project
        self.agent = agent
        self.title = title
    }
}

/// Tracks the order in which distinct state changes were received from one mock source.
public struct SessionTracker {
    private struct Entry {
        var session: AgentSession
        var order: Int
    }
    private var entries: [String: Entry] = [:]
    private var nextOrder = 0

    public init() {}

    public var ordered: [AgentSession] {
        entries.values.sorted { $0.order < $1.order }.map(\.session)
    }

    public mutating func update(_ session: AgentSession) {
        let old = entries[session.id]
        let order: Int
        if let old, old.session.state == session.state {
            order = old.order
        } else {
            order = nextOrder
            nextOrder += 1
        }
        entries[session.id] = Entry(session: session, order: order)
    }

    public mutating func replace(with sessions: [AgentSession]) {
        let ids = Set(sessions.map(\.id))
        entries = entries.filter { ids.contains($0.key) }
        for session in sessions { update(session) }
    }

    public mutating func remove(id: String) { entries.removeValue(forKey: id) }
}

public struct VisibleSession: Identifiable, Equatable {
    public var session: AgentSession
    public var isAvailable: Bool
    public var id: String { session.id }
}

/// Keeps the displayed rows stable until the menu is closed.
public struct VisibleSessionList {
    public private(set) var rows: [VisibleSession] = []

    public init() {}

    public mutating func open(_ sessions: [AgentSession]) {
        rows = sessions.map { VisibleSession(session: $0, isAvailable: true) }
    }

    public mutating func update(_ sessions: [AgentSession], capacity: Int) {
        let current = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        rows = rows.map { row in
            guard let session = current[row.id] else {
                return VisibleSession(session: row.session, isAvailable: false)
            }
            return VisibleSession(session: session, isAvailable: true)
        }
        let displayed = Set(rows.map(\.id))
        let availableSlots = max(0, capacity - rows.count)
        let additions = sessions.filter { !displayed.contains($0.id) }.reversed().prefix(availableSlots)
        rows.insert(contentsOf: additions.map { VisibleSession(session: $0, isAvailable: true) }, at: 0)
    }

    public mutating func close() { rows.removeAll() }
}
