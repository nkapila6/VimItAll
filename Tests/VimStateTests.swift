import XCTest
@testable import vimitall

final class VimStateTests: XCTestCase {
    @MainActor
    func testInitialStateIsInsert() {
        let state = VimState()
        XCTAssertEqual(state.mode, .insert)
        XCTAssertNil(state.currentCount)
        XCTAssertNil(state.pendingOperator)
    }

    @MainActor
    func testNormalToInsertAndBack() {
        let state = VimState()
        state.enterNormalMode()
        XCTAssertEqual(state.mode, .normal)
        state.enterInsertMode()
        XCTAssertEqual(state.mode, .insert)
        state.enterNormalMode()
        XCTAssertEqual(state.mode, .normal)
    }

    @MainActor
    func testResetClearsCountAndOperator() {
        let state = VimState()
        state.currentCount = 5
        state.pendingOperator = .deleteChar
        state.reset()
        XCTAssertNil(state.currentCount)
        XCTAssertNil(state.pendingOperator)
    }

    @MainActor
    func testEnterNormalResets() {
        let state = VimState()
        state.currentCount = 3
        state.pendingOperator = .yankLine
        state.enterNormalMode()
        XCTAssertNil(state.currentCount)
        XCTAssertNil(state.pendingOperator)
    }

    @MainActor
    func testEnterInsertResets() {
        let state = VimState()
        state.currentCount = 7
        state.pendingOperator = .deleteLine
        state.enterInsertMode()
        XCTAssertNil(state.currentCount)
        XCTAssertNil(state.pendingOperator)
    }

    @MainActor
    func testEnterVisualSetsMode() {
        let state = VimState()
        state.enterVisualMode(anchor: 0, lineWise: false)
        XCTAssertEqual(state.mode, .visual)
    }

    @MainActor
    func testEnterVisualSetsAnchor() {
        let state = VimState()
        state.enterVisualMode(anchor: 5, lineWise: false)
        XCTAssertEqual(state.visualAnchor, 5)
    }

    @MainActor
    func testEnterVisualLineWise() {
        let state = VimState()
        state.enterVisualMode(anchor: 0, lineWise: true)
        XCTAssertTrue(state.visualLineWise)
    }

    @MainActor
    func testVisualToInsertResets() {
        let state = VimState()
        state.enterVisualMode(anchor: 5, lineWise: true)
        state.enterInsertMode()
        XCTAssertEqual(state.mode, .insert)
        XCTAssertEqual(state.visualAnchor, 0)
    }

    // MARK: - Pending find and last find

    @MainActor
    func testResetClearsPendingFind() {
        let state = VimState()
        state.pendingFind = (forward: true, till: false)
        state.reset()
        XCTAssertNil(state.pendingFind)
    }

    @MainActor
    func testLastFindPersistsAcrossReset() {
        let state = VimState()
        state.lastFind = LastFind(char: "x", forward: true, till: false)
        state.reset()
        // lastFind should NOT be cleared by reset (needed for ; and , repeat).
        XCTAssertNotNil(state.lastFind)
        XCTAssertEqual(state.lastFind?.char, "x")
    }

    @MainActor
    func testLastChangePersistsAcrossReset() {
        let state = VimState()
        state.lastChange = LastChange(op: .deleteLine, motion: .wordForward, count: 1)
        state.reset()
        // lastChange should NOT be cleared by reset (needed for . repeat).
        XCTAssertNotNil(state.lastChange)
        XCTAssertEqual(state.lastChange?.op, .deleteLine)
    }

    // MARK: - KeyMapping resolution for new bindings

    func testKeyMappingResolvesWORDMotions() {
        XCTAssertEqual(KeyMapping.resolve("W")?.action, .motion(.wordForwardWORD))
        XCTAssertEqual(KeyMapping.resolve("B")?.action, .motion(.wordBackWORD))
        XCTAssertEqual(KeyMapping.resolve("E")?.action, .motion(.wordEndWORD))
    }

    func testKeyMappingResolvesFind() {
        if case .pendingFind(let forward, let till) = KeyMapping.resolve("f")?.action {
            XCTAssertTrue(forward)
            XCTAssertFalse(till)
        } else {
            XCTFail("f should resolve to pendingFind")
        }
        if case .pendingFind(let forward, let till) = KeyMapping.resolve("F")?.action {
            XCTAssertFalse(forward)
            XCTAssertFalse(till)
        } else {
            XCTFail("F should resolve to pendingFind")
        }
        if case .pendingFind(let forward, let till) = KeyMapping.resolve("t")?.action {
            XCTAssertTrue(forward)
            XCTAssertTrue(till)
        } else {
            XCTFail("t should resolve to pendingFind")
        }
        if case .pendingFind(let forward, let till) = KeyMapping.resolve("T")?.action {
            XCTAssertFalse(forward)
            XCTAssertTrue(till)
        } else {
            XCTFail("T should resolve to pendingFind")
        }
    }

    func testKeyMappingResolvesRepeatFind() {
        XCTAssertEqual(KeyMapping.resolve(";")?.action, .repeatFind(reverse: false))
        XCTAssertEqual(KeyMapping.resolve(",")?.action, .repeatFind(reverse: true))
    }

    func testKeyMappingResolvesRepeatLastChange() {
        XCTAssertEqual(KeyMapping.resolve(".")?.action, .repeatLastChange)
    }
}
