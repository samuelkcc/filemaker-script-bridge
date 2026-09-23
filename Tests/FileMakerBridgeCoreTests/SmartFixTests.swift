import XCTest
@testable import FileMakerBridgeCore

final class SmartFixTests: XCTestCase {
    func testExportedTODOBlockCanBeRecovered() throws {
        let source = "# -----------------  FileMaker Script Bridge TODO -----------------\n# Show Custom Dialog in FileMaker. AI draft: Show Custom Dialog [ \"Title\" ; \"Message\" ]\n# after"
        var review = SmartFixReview(source: source)
        XCTAssertEqual(review.items.count, 1)
        review.items[0].action = .replace
        let fixed = try review.applying(to: source)
        XCTAssertFalse(fixed.contains("TODO"))
        XCTAssertTrue(fixed.hasSuffix("\n# after"))
        XCTAssertEqual(FileMakerXMLCompiler().compile(fixed).commentFallbackCount, 0)
    }

    func testPositionalDialogCompilesWithoutTODO() {
        let result = FileMakerXMLCompiler().compile("Show Custom Dialog [ \"Title\" ; List ( $a ; $b ) ]")
        XCTAssertEqual(result.commentFallbackCount, 0)
        guard case let .showCustomDialog(title, message, buttons) = result.steps.first else { return XCTFail("Expected native dialog") }
        XCTAssertEqual(title, "\"Title\"")
        XCTAssertEqual(message, "List ( $a ; $b )")
        XCTAssertEqual(buttons.count, 1)
    }

    func testMissingDefaultDoesNotRenumberSecondButton() throws {
        let source = "Show Custom Dialog [ Message: \"Continue?\" ; Button 2: \"Cancel\", Commit: No ]"
        XCTAssertGreaterThan(FileMakerXMLCompiler().compile(source).commentFallbackCount, 0)
        var review = SmartFixReview(source: source)
        XCTAssertEqual(review.items.count, 1)
        XCTAssertEqual(review.items[0].action, .keep)
        review.items[0].action = .replace
        let fixed = try review.applying(to: source)
        let result = FileMakerXMLCompiler().compile(fixed)
        XCTAssertEqual(result.commentFallbackCount, 0)
        guard case let .showCustomDialog(_, _, buttons) = result.steps.first else { return XCTFail("Expected native dialog") }
        XCTAssertEqual(buttons.map(\.calculation), ["\"OK\"", "\"Cancel\""])
        XCTAssertEqual(buttons.map(\.commitsRecord), [false, false])
    }

    func testBulkMultilineRepairsPreserveSurroundingText() throws {
        let source = """
        # before
          Show Custom Dialog
          [ Title: "First" ;
            Message: "Hello" ]

        Unsupported Step
        Show Custom Dialog [ Message: "Last" ]
        # after
        """
        var review = SmartFixReview(source: source)
        XCTAssertEqual(review.items.map(\.line), [2, 6, 7])
        for index in review.items.indices where review.items[index].suggestion != nil {
            review.items[index].action = .replace
        }
        let fixed = try review.applying(to: source)
        XCTAssertTrue(fixed.hasPrefix("# before\n  Show Custom Dialog ["))
        XCTAssertTrue(fixed.contains("\n\nUnsupported Step\n"))
        XCTAssertTrue(fixed.hasSuffix("\n# after"))
        XCTAssertEqual(FileMakerXMLCompiler().compile(fixed).commentFallbackCount, 2)
        XCTAssertEqual(SmartFixReview(source: fixed).items.count, 1)
    }

    func testCannotGuessMissingMessageOrDiscardInputOptions() {
        for source in [
            "Show Custom Dialog [ Title: \"Title\" ]",
            "Show Custom Dialog [ Message: \"Hello\" ; Input #1: Table::Field ]",
            "Show Custom Dialog [ Message: \"Hello\" ; Default Button: \"OK\", Commit: Maybe ]"
        ] {
            let review = SmartFixReview(source: source)
            XCTAssertEqual(review.items.count, 1)
            XCTAssertNil(review.items.first?.suggestion)
            XCTAssertFalse(SmartFixReview.isNativeReplacement(source))
        }
    }

    func testReplacementValidationStaleSourceAndOmission() throws {
        let source = "Set Variable [ $x ]\n# keep"
        var review = SmartFixReview(source: source)
        review.items[0].action = .replace
        XCTAssertThrowsError(try review.applying(to: source))
        review.items[0].replacement = "Set Variable [ $x ; Value: 42 ]"
        XCTAssertThrowsError(try review.applying(to: source + "\n"))
        XCTAssertEqual(try review.applying(to: source), "Set Variable [ $x ; Value: 42 ]\n# keep")
        review.items[0].action = .omit
        XCTAssertTrue(try review.applying(to: source).hasPrefix("# Omitted by Smart Fix:"))
    }
}
