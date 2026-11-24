import XCTest
@testable import SessionList

final class SessionListTests: XCTestCase {
    private func session(_ id: String, _ state: String) -> AgentSession {
        AgentSession(id: id, state: state, project: "DisplayCorners", agent: "Mock Agent")
    }

    func testOpenListKeepsRowsStableAndReordersOnlyWhenReopened() {
        var tracker = SessionTracker()
        tracker.update(session("A", "working"))
        tracker.update(session("B", "working"))
        var visible = VisibleSessionList()
        visible.open(tracker.ordered)
        XCTAssertEqual(visible.rows.map(\.id), ["A", "B"])

        tracker.update(session("A", "working")) // A repeated confirmation is not a state change.
        XCTAssertEqual(tracker.ordered.map(\.id), ["A", "B"])
        tracker.update(session("A", "waiting_for_user"))
        visible.update(tracker.ordered, capacity: 10)
        XCTAssertEqual(visible.rows.map(\.id), ["A", "B"])
        XCTAssertEqual(visible.rows[0].session.state, "waiting_for_user")

        let oldY = visible.rows.indices.map { (visible.rows.count - $0 - 1) * 57 }
        tracker.update(session("C", "working"))
        visible.update(tracker.ordered, capacity: 10)
        XCTAssertEqual(visible.rows.map(\.id), ["C", "A", "B"])
        let newY = visible.rows.indices.dropFirst().map { (visible.rows.count - $0 - 1) * 57 }
        XCTAssertEqual(oldY, newY)

        tracker.remove(id: "B")
        visible.update(tracker.ordered, capacity: 10)
        XCTAssertEqual(visible.rows.map(\.id), ["C", "A", "B"])
        XCTAssertFalse(visible.rows[2].isAvailable)
        visible.close()
        visible.open(tracker.ordered)
        XCTAssertEqual(visible.rows.map(\.id), ["A", "C"])
        XCTAssertTrue(visible.rows.allSatisfy(\.isAvailable))
    }

    func testNewRowsWaitWhenThereIsNoSpace() {
        var tracker = SessionTracker()
        tracker.update(session("A", "working"))
        tracker.update(session("B", "working"))
        var visible = VisibleSessionList()
        visible.open(tracker.ordered)
        tracker.update(session("C", "waiting_for_user"))
        visible.update(tracker.ordered, capacity: 2)
        XCTAssertEqual(visible.rows.map(\.id), ["A", "B"])
        XCTAssertTrue(tracker.ordered.contains { $0.id == "C" && $0.state == "waiting_for_user" })
        visible.close()
        visible.open(tracker.ordered)
        XCTAssertEqual(visible.rows.map(\.id), ["A", "B", "C"])
    }

    func testTitleUpdateDoesNotMoveRow() {
        var tracker = SessionTracker()
        tracker.update(AgentSession(id: "A", state: "working"))
        tracker.update(AgentSession(id: "B", state: "working"))
        tracker.update(AgentSession(id: "A", state: "working", title: "Actual chat"))
        XCTAssertEqual(tracker.ordered.map(\.id), ["A", "B"])
        XCTAssertEqual(tracker.ordered.first?.title, "Actual chat")
    }
}
