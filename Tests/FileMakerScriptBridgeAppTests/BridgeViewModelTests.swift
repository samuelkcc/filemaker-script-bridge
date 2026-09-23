import FileMakerBridgeCore
import XCTest
@testable import FileMakerScriptBridgeApp

@MainActor
final class BridgeViewModelTests: XCTestCase {
    func testSmartFixAppliesInBulkAndRequiresClipboardUpdate() throws {
        let clipboard = InMemoryClipboard(plainText: "Show Custom Dialog [ Message: \"Hello\" ; Button 2: \"Cancel\" ]")
        let model = BridgeViewModel(clipboard: clipboard.client)
        model.pasteAITextAndCreateClipboard()
        let originalClipboard = clipboard.fileMakerXML
        var review = SmartFixReview(source: model.sourceText)
        review.items[0].action = .replace
        try model.applySmartFix(review)
        XCTAssertEqual(model.result.commentFallbackCount, 0)
        XCTAssertNil(model.clipboardNotice)
        XCTAssertEqual(clipboard.fileMakerXML, originalClipboard)
        model.copyForFileMaker()
        XCTAssertFalse(clipboard.fileMakerXML?.contains("TODO") ?? true)
    }

    func testSmartFixRejectsIncompleteControlFlowReplacement() {
        let model = BridgeViewModel(clipboard: InMemoryClipboard().client)
        model.sourceText = "If [ $x ]"
        var review = SmartFixReview(source: model.sourceText)
        review.items[0].action = .replace
        review.items[0].replacement = "If [ $y ]"
        XCTAssertThrowsError(try model.applySmartFix(review))
        XCTAssertEqual(model.sourceText, "If [ $x ]")
    }

    func testNewBridgeStartsEmptyWithoutValidationError() {
        let model = BridgeViewModel(clipboard: InMemoryClipboard().client)

        XCTAssertEqual(model.sourceText, "")
        XCTAssertEqual(model.result.errorCount, 0)
        XCTAssertFalse(model.canCopyForFileMaker)
        XCTAssertTrue(model.statusMessage.contains("Paste or type"))
    }

    func testPastingValidAITextAutomaticallyCreatesFileMakerClipboard() {
        let clipboard = InMemoryClipboard(plainText: ExampleScript.fileMaker26)
        let model = BridgeViewModel(clipboard: clipboard.client)

        model.pasteAITextAndCreateClipboard()

        XCTAssertEqual(model.clipboardNotice, .fileMakerReady)
        XCTAssertTrue(model.canCopyForFileMaker)
        XCTAssertNotNil(clipboard.fileMakerXML)
        XCTAssertTrue(model.statusMessage.contains("FileMaker clipboard ready"))
    }

    func testUnsupportedAITextCreatesPasteableTemplateCommentByDefault() {
        let clipboard = InMemoryClipboard(
            plainText: "Constrain Found Set [ unsupported AI-authored options ]"
        )
        let model = BridgeViewModel(clipboard: clipboard.client)

        model.pasteAITextAndCreateClipboard()

        XCTAssertEqual(model.clipboardNotice, .fileMakerReady)
        XCTAssertEqual(model.result.errorCount, 0)
        XCTAssertTrue(model.canCopyForFileMaker)
        XCTAssertTrue(clipboard.fileMakerXML?.contains("FileMaker Script Bridge TODO") == true)
        XCTAssertTrue(clipboard.fileMakerXML?.contains("Constrain Found Set in FileMaker. AI draft:") == true)
        XCTAssertTrue(model.statusMessage.contains("FileMaker clipboard ready"))
    }

    func testReadingFileMakerAutomaticallyCopiesReadableText() {
        let xml = FileMakerXMLCompiler().compile(ExampleScript.fileMaker26).xml
        let clipboard = InMemoryClipboard(
            fileMakerPayload: FileMakerClipboardPayload(
                kind: .scriptSteps,
                xml: xml,
                pasteboardType: "test.XMSS"
            )
        )
        let model = BridgeViewModel(clipboard: clipboard.client)

        model.importFromFileMaker()

        XCTAssertEqual(model.clipboardNotice, .readableTextReady)
        XCTAssertTrue(clipboard.plainText?.contains("Set Variable") == true)
        XCTAssertNil(clipboard.fileMakerXML)
        XCTAssertTrue(model.statusMessage.contains("Readable text is already copied"))
    }

    func testIssueNavigationTargetsTheRequestedEditorLine() {
        let model = BridgeViewModel(clipboard: InMemoryClipboard().client)
        let issue = CompilationIssue(
            severity: .error,
            line: 7,
            message: "Test issue",
            source: "Unsupported Step"
        )

        model.focusEditor(on: issue)

        XCTAssertEqual(model.requestedEditorLine, 7)
        XCTAssertEqual(model.editorNavigationRevision, 1)
    }
}

@MainActor
private final class InMemoryClipboard {
    var plainText: String?
    var fileMakerPayload: FileMakerClipboardPayload?
    var fileMakerXML: String?

    init(
        plainText: String? = nil,
        fileMakerPayload: FileMakerClipboardPayload? = nil
    ) {
        self.plainText = plainText
        self.fileMakerPayload = fileMakerPayload
    }

    lazy var client = ClipboardClient(
        readPlainText: { [unowned self] in plainText },
        readFileMakerXML: { [unowned self] in
            guard let fileMakerPayload else {
                throw ClipboardServiceError.noFileMakerData
            }
            return fileMakerPayload
        },
        writeFileMakerScriptSteps: { [unowned self] xml in
            fileMakerXML = xml
            plainText = xml
        },
        containsFileMakerScriptSteps: { [unowned self] in fileMakerXML != nil },
        writePlainText: { [unowned self] text in
            plainText = text
            fileMakerXML = nil
            return true
        },
        typeNames: { [unowned self] in
            var types: [String] = []
            if plainText != nil { types.append("public.utf8-plain-text") }
            if fileMakerXML != nil { types.append("test.XMSS") }
            return types
        }
    )
}
