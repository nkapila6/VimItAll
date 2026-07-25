import XCTest
@testable import vimitall

final class MotionTests: XCTestCase {
    // MARK: - Basic single-line motions

    func testLeftMotion() {
        let text = "hello world"
        XCTAssertEqual(Motion.left.targetOffset(from: 5, in: text, count: 1), 4)
        XCTAssertEqual(Motion.left.targetOffset(from: 5, in: text, count: 3), 2)
        XCTAssertEqual(Motion.left.targetOffset(from: 0, in: text, count: 1), 0)
    }

    func testRightMotion() {
        let text = "hello world"
        XCTAssertEqual(Motion.right.targetOffset(from: 0, in: text, count: 1), 1)
        XCTAssertEqual(Motion.right.targetOffset(from: 0, in: text, count: 5), 5)
        XCTAssertEqual(Motion.right.targetOffset(from: text.count, in: text, count: 1), text.count)
    }

    func testWordForward() {
        let text = "hello world"
        // caret at 0 (start of "hello"): w -> start of "world" = 6
        XCTAssertEqual(Motion.wordForward.targetOffset(from: 0, in: text, count: 1), 6)
        // 2w from 0: past "world" = 11
        XCTAssertEqual(Motion.wordForward.targetOffset(from: 0, in: text, count: 2), 11)
    }

    func testWordBack() {
        let text = "hello world"
        // caret at 6 (start of "world"): b -> start of "hello" = 0
        XCTAssertEqual(Motion.wordBack.targetOffset(from: 6, in: text, count: 1), 0)
    }

    func testWordEnd() {
        let text = "hello world"
        // caret at 0: e -> end of "hello" = 4
        XCTAssertEqual(Motion.wordEnd.targetOffset(from: 0, in: text, count: 1), 4)
        // 2e from 0: end of "world" = 10
        XCTAssertEqual(Motion.wordEnd.targetOffset(from: 0, in: text, count: 2), 10)
    }

    func testLineStartAndEnd() {
        let text = "hello\nworld"
        // caret at 8 (in "world"): 0 -> start of line = 6
        XCTAssertEqual(Motion.lineStart.targetOffset(from: 8, in: text, count: 1), 6)
        // $ -> end of line = 11
        XCTAssertEqual(Motion.lineEnd.targetOffset(from: 8, in: text, count: 1), 11)
    }

    func testDocumentStartAndEnd() {
        let text = "hello\nworld"
        // gg: first non-blank of first line = 0
        XCTAssertEqual(Motion.documentStart.targetOffset(from: 5, in: text, count: 1), 0)
        // G: first non-blank of last line = 6 (start of "world")
        XCTAssertEqual(Motion.documentEnd.targetOffset(from: 0, in: text, count: 1), 6)
    }

    // MARK: - Multiline motions

    func testDownMotion() {
        let text = "abc\ndef\nghi"
        // caret at 0 (start of "abc"): j -> start of "def" = 4
        XCTAssertEqual(Motion.down.targetOffset(from: 0, in: text, count: 1), 4)
        // 2j from 0 -> start of "ghi" = 8
        XCTAssertEqual(Motion.down.targetOffset(from: 0, in: text, count: 2), 8)
        // j from last line stays at last line
        XCTAssertEqual(Motion.down.targetOffset(from: 8, in: text, count: 1), 8)
    }

    func testUpMotion() {
        let text = "abc\ndef\nghi"
        // caret at 8 (start of "ghi"): k -> start of "def" = 4
        XCTAssertEqual(Motion.up.targetOffset(from: 8, in: text, count: 1), 4)
        // 2k from 8 -> start of "abc" = 0
        XCTAssertEqual(Motion.up.targetOffset(from: 8, in: text, count: 2), 0)
        // k from first line stays at first line
        XCTAssertEqual(Motion.up.targetOffset(from: 0, in: text, count: 1), 0)
    }

    func testDownMotionPreservesColumn() {
        let text = "abcdef\ngh\nijklmn"
        // caret at 4 (col 4 in "abcdef"): j -> col 4 in "gh" is clamped to 2
        XCTAssertEqual(Motion.down.targetOffset(from: 4, in: text, count: 1), 9)
    }

    func testUpMotionPreservesColumn() {
        let text = "abcdef\ngh\nijklmn"
        // caret at 13 (col 4 in "ijklmn"): k -> col 4 in "gh" clamped to 2
        XCTAssertEqual(Motion.up.targetOffset(from: 13, in: text, count: 1), 9)
    }

    // MARK: - Counts

    func testWordForwardWithCount() {
        let text = "a b c d e"
        // 3w from 0: skip "a", "b", "c" -> start of "d" = 6
        XCTAssertEqual(Motion.wordForward.targetOffset(from: 0, in: text, count: 3), 6)
    }

    func testLeftWithCount() {
        let text = "hello"
        XCTAssertEqual(Motion.left.targetOffset(from: 4, in: text, count: 3), 1)
    }

    // MARK: - WORD motions (whitespace-delimited)

    func testWordForwardWORD() {
        let text = "hello.world foo-bar"
        // W treats punctuation as part of the word.
        // caret at 0: W -> start of "foo-bar" = 12
        XCTAssertEqual(Motion.wordForwardWORD.targetOffset(from: 0, in: text, count: 1), 12)
        // 2W from 0: past "foo-bar" = 19
        XCTAssertEqual(Motion.wordForwardWORD.targetOffset(from: 0, in: text, count: 2), 19)
    }

    func testWordForwardWORDvsWord() {
        let text = "hello.world foo-bar"
        // w treats punctuation as boundaries: "hello" is a word, "." is a word, "world" is a word.
        // 1w from 0: skip "hello" -> start of "." = 5
        XCTAssertEqual(Motion.wordForward.targetOffset(from: 0, in: text, count: 1), 5)
        // W treats it all as one WORD: hello.world -> 12
        XCTAssertEqual(Motion.wordForwardWORD.targetOffset(from: 0, in: text, count: 1), 12)
    }

    func testWordBackWORD() {
        let text = "hello.world foo-bar"
        // caret at 12 (start of "foo-bar"): B -> start of "hello.world" = 0
        XCTAssertEqual(Motion.wordBackWORD.targetOffset(from: 12, in: text, count: 1), 0)
    }

    func testWordEndWORD() {
        let text = "hello.world foo-bar"
        // caret at 0: E -> end of "hello.world" = 10
        XCTAssertEqual(Motion.wordEndWORD.targetOffset(from: 0, in: text, count: 1), 10)
        // 2E from 0: end of "foo-bar" = 18
        XCTAssertEqual(Motion.wordEndWORD.targetOffset(from: 0, in: text, count: 2), 18)
    }

    func testWordEndWORDvsWord() {
        let text = "hello.world foo-bar"
        // e: end of "hello" = 4
        // E: end of "hello.world" = 10
        XCTAssertEqual(Motion.wordEnd.targetOffset(from: 0, in: text, count: 1), 4)
        XCTAssertEqual(Motion.wordEndWORD.targetOffset(from: 0, in: text, count: 1), 10)
    }

    func testWORDMotionsWithMultipleSpaces() {
        let text = "a    b    c"
        // W from 0: skip "a", skip 4 spaces -> start of "b" = 5
        XCTAssertEqual(Motion.wordForwardWORD.targetOffset(from: 0, in: text, count: 1), 5)
        // 2W from 0: skip "a", spaces, "b", spaces -> start of "c" = 10
        XCTAssertEqual(Motion.wordForwardWORD.targetOffset(from: 0, in: text, count: 2), 10)
    }

    func testWORDMotionsAtEndOfText() {
        let text = "hello"
        // W at end of text stays at end.
        XCTAssertEqual(Motion.wordForwardWORD.targetOffset(from: 5, in: text, count: 1), 5)
        // E at end of text stays at end.
        XCTAssertEqual(Motion.wordEndWORD.targetOffset(from: 5, in: text, count: 1), 5)
    }
}
