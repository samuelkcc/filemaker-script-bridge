import AppKit
import FileMakerBridgeCore
import Foundation
import SwiftUI

enum BridgeStatusTone {
    case info
    case success
    case warning
    case error
}

enum ClipboardNoticeKind: Equatable {
    case fileMakerReady
    case readableTextReady
}

@MainActor
final class BridgeViewModel: ObservableObject {
    @Published var sourceText: String = "" {
        didSet {
            if !isAssigningImportedText {
                lastImportedXML = nil
                clipboardNotice = nil
            }
            compile()
        }
    }
    @Published var convertUnsupportedToComments = true {
        didSet {
            clipboardNotice = nil
            compile()
        }
    }
    @Published private(set) var result: CompilationResult
    @Published private(set) var statusMessage = "Paste or type an AI script to begin."
    @Published private(set) var statusTone: BridgeStatusTone = .info
    @Published var showXML = false
    @Published private(set) var requestedEditorLine: Int?
    @Published private(set) var editorNavigationRevision = 0
    @Published private(set) var clipboardNotice: ClipboardNoticeKind?

    @Published private(set) var lastImportedXML: String?
    @Published private(set) var preservedSteps: [String: PreservedFileMakerStep] = [:]

    private let compiler = FileMakerXMLCompiler()
    private let decompiler = FileMakerXMLDecompiler()
    private let clipboard: ClipboardClient
    private var isAssigningImportedText = false

    var displayedXML: String {
        lastImportedXML ?? result.xml
    }

    var isShowingImportedXML: Bool {
        lastImportedXML != nil
    }

    var reviewOnlyStepCount: Int {
        ReviewMarkerDetector.count(in: sourceText)
    }

    var displayWarningCount: Int {
        result.warningCount + result.preservedStepCount + reviewOnlyStepCount
    }

    var templateIssues: [CompilationIssue] {
        result.issues.filter { issue in
            issue.severity == .warning && issue.message.contains("converted to a FileMaker comment")
        }
    }

    var canCopyForFileMaker: Bool {
        result.canCopyToFileMaker && reviewOnlyStepCount == 0
    }

    init(clipboard: ClipboardClient = .live) {
        self.clipboard = clipboard
        result = compiler.compile(
            "",
            options: CompilationOptions(convertUnsupportedLinesToComments: false)
        )
    }

    func compile() {
        result = compiler.compile(
            sourceText,
            options: CompilationOptions(
                convertUnsupportedLinesToComments: convertUnsupportedToComments
            ),
            preservedSteps: preservedSteps
        )
        statusTone = .info
        if result.errorCount > 0 {
            statusMessage = "Fix \(result.errorCount) blocking issue\(result.errorCount == 1 ? "" : "s") before creating the FileMaker clipboard."
            statusTone = .error
        } else if reviewOnlyStepCount > 0 {
            statusMessage = "Re-read the original FileMaker script: \(reviewOnlyStepCount) legacy marker\(reviewOnlyStepCount == 1 ? " has" : "s have") no preserved XML."
            statusTone = .warning
        } else if result.preservedStepCount > 0 {
            statusMessage = "Ready. \(result.preservedStepCount) FileMaker step\(result.preservedStepCount == 1 ? " is" : "s are") preserved unchanged for this session."
            statusTone = .warning
        } else if result.warningCount > 0 {
            statusMessage = "Ready with \(result.warningCount) warning\(result.warningCount == 1 ? "" : "s")."
            statusTone = .warning
        } else if !result.steps.isEmpty {
            statusMessage = "Ready to create a native FileMaker clipboard."
            statusTone = .success
        } else {
            statusMessage = "Copy AI script text, then use the primary paste action."
        }
    }

    func clearEditor() {
        preservedSteps = [:]
        clipboardNotice = nil
        sourceText = ""
        statusMessage = "Editor cleared."
        statusTone = .info
    }

    func pasteAITextAndCreateClipboard() {
        guard let text = clipboard.readPlainText(), !text.isEmpty else {
            statusMessage = "The clipboard does not contain plain text. Copy the AI script first."
            statusTone = .error
            return
        }

        sourceText = text
        guard canCopyForFileMaker else {
            statusMessage = "AI text pasted, but the FileMaker clipboard was not created. Fix the blocking validation issues first."
            statusTone = .error
            return
        }

        createFileMakerClipboard(
            successMessage: "FileMaker clipboard ready. Open Script Workspace, choose the insertion point, and press ⌘V."
        )
    }

    func importFromFileMaker() {
        do {
            let payload = try clipboard.readFileMakerXML()
            let imported = decompiler.decompile(payload.xml)
            guard imported.isSuccessful else {
                statusMessage = imported.warnings.first ?? "No FileMaker script steps were found."
                statusTone = .error
                return
            }

            isAssigningImportedText = true
            lastImportedXML = payload.xml
            preservedSteps = imported.preservedSteps
            sourceText = imported.text
            isAssigningImportedText = false

            guard copyReadableTextToClipboard() else { return }

            if imported.unsupportedStepCount > 0 {
                statusMessage = "Read \(imported.stepCount) FileMaker steps and copied readable text. All steps can return this session; \(imported.unsupportedStepCount) step\(imported.unsupportedStepCount == 1 ? " is" : "s are") preserved unchanged with locked options."
                statusTone = .warning
            } else {
                statusMessage = "Read \(imported.stepCount) FileMaker steps. Readable text is already copied — paste it into your AI tool."
                statusTone = .success
            }
        } catch {
            isAssigningImportedText = false
            statusMessage = error.localizedDescription
            statusTone = .error
        }
    }

    func copyForFileMaker() {
        if reviewOnlyStepCount > 0 {
            statusMessage = "FileMaker clipboard creation is unavailable because \(reviewOnlyStepCount) legacy review marker\(reviewOnlyStepCount == 1 ? " has" : "s have") no preserved XML. Re-import the original script."
            statusTone = .warning
            return
        }
        guard result.canCopyToFileMaker else {
            statusMessage = "The script has blocking issues and the FileMaker clipboard was not changed."
            statusTone = .error
            return
        }

        createFileMakerClipboard(
            successMessage: "FileMaker clipboard updated from the editor. Return to Script Workspace and press ⌘V."
        )
    }

    func copyXML() {
        clipboardNotice = nil
        if clipboard.writePlainText(displayedXML) {
            statusMessage = "Raw XML copied for inspection. It will not paste as steps by itself."
            statusTone = .info
        } else {
            statusMessage = "Could not copy the XML."
            statusTone = .error
        }
    }

    func inspectClipboard() {
        let types = clipboard.typeNames()
        if types.isEmpty {
            statusMessage = "The clipboard is empty."
            statusTone = .error
        } else {
            statusMessage = "Clipboard types: " + types.joined(separator: ", ")
            statusTone = .info
        }
    }

    func focusEditor(on issue: CompilationIssue) {
        requestedEditorLine = issue.line
        editorNavigationRevision += 1
    }

    @discardableResult
    private func copyReadableTextToClipboard() -> Bool {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = "There is no readable script text to copy."
            statusTone = .error
            return false
        }

        guard clipboard.writePlainText(text) else {
            statusMessage = "Could not copy readable script text."
            statusTone = .error
            return false
        }
        clipboardNotice = .readableTextReady
        return true
    }

    private func createFileMakerClipboard(successMessage: String) {
        do {
            try clipboard.writeFileMakerScriptSteps(result.xml)
            guard clipboard.containsFileMakerScriptSteps() else {
                throw ClipboardServiceError.fileMakerWriteFailed
            }
            clipboardNotice = .fileMakerReady
            statusMessage = successMessage
            statusTone = .success
        } catch {
            clipboardNotice = nil
            statusMessage = error.localizedDescription
            statusTone = .error
        }
    }
}
