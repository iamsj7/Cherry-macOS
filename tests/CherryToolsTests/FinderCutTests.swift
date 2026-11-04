import XCTest
@testable import CherryTools

final class FinderCutTests: XCTestCase {
    func testKeysFollowTheTypedCharacter() {
        XCTAssertEqual(FinderKey.resolve(characters: "x", keyCode: 7), .cut)
        // Dvorak puts Q on the physical X key.
        XCTAssertNil(FinderKey.resolve(characters: "q", keyCode: 7))
        XCTAssertEqual(FinderKey.resolve(characters: "x", keyCode: 11), .cut)
        XCTAssertEqual(FinderKey.resolve(characters: "V", keyCode: 9), .paste)
    }

    func testNonLatinLayoutsUsePhysicalKeys() {
        XCTAssertEqual(FinderKey.resolve(characters: "ء", keyCode: 7), .cut)
        XCTAssertEqual(FinderKey.resolve(characters: "ؤ", keyCode: 8), .copy)
        XCTAssertNil(FinderKey.resolve(characters: "ب", keyCode: 11))
    }

    func testPasteMovesAfterFilesAreCopied() {
        var state = CutState()
        state.begin(changeCount: 10)
        XCTAssertTrue(state.confirm(changeCount: 11, hasFiles: true))
        XCTAssertTrue(state.paste(changeCount: 11, hasFiles: true))
        XCTAssertFalse(state.paste(changeCount: 11, hasFiles: true), "A cut only moves once")
    }

    func testEmptySelectionDoesNotTurnAnEarlierCopyIntoAMove() {
        var state = CutState()
        state.begin(changeCount: 10) // Finder copied nothing, so the count never changes.
        XCTAssertFalse(state.confirm(changeCount: 10, hasFiles: true))
        XCTAssertFalse(state.paste(changeCount: 10, hasFiles: true))
    }

    func testCopiedTextDoesNotArm() {
        var state = CutState()
        state.begin(changeCount: 10)
        XCTAssertFalse(state.confirm(changeCount: 11, hasFiles: false))
        XCTAssertFalse(state.paste(changeCount: 11, hasFiles: false))
    }

    func testAnotherCopyCancelsTheCut() {
        var state = CutState()
        state.begin(changeCount: 10)
        XCTAssertTrue(state.confirm(changeCount: 11, hasFiles: true))
        XCTAssertFalse(state.paste(changeCount: 12, hasFiles: true))
    }

    func testFastPasteStillMoves() {
        var state = CutState()
        state.begin(changeCount: 10)
        XCTAssertTrue(state.paste(changeCount: 11, hasFiles: true))
    }

    func testServiceCutArmsPaste() {
        var state = CutState()
        state.arm(changeCount: 20)
        XCTAssertTrue(state.isArmed(changeCount: 20))
        XCTAssertFalse(state.isArmed(changeCount: 21), "Copying anything else cancels the cut")
        XCTAssertTrue(state.paste(changeCount: 20, hasFiles: true))
    }

    func testMoveNeverReplacesOrNestsFiles() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let fresh = source.appendingPathComponent("fresh.txt"), taken = source.appendingPathComponent("taken.txt")
        try Data("new".utf8).write(to: fresh)
        try Data("new".utf8).write(to: taken)
        try Data("old".utf8).write(to: target.appendingPathComponent("taken.txt"))

        let result = FileMover.move([fresh, taken, target], to: target)

        XCTAssertEqual(result.moved.map(\.lastPathComponent), ["fresh.txt"])
        XCTAssertEqual(result.skipped, ["taken.txt", "target"])
        XCTAssertTrue(manager.fileExists(atPath: taken.path))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("taken.txt")), Data("old".utf8))
    }
}
