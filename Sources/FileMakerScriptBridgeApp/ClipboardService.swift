import AppKit
import Foundation

enum ClipboardServiceError: LocalizedError {
    case encodingFailed
    case fileMakerWriteFailed
    case noFileMakerData
    case fileMakerDataDecodeFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "The generated XML could not be encoded as UTF-8."
        case .fileMakerWriteFailed:
            return "macOS did not accept the FileMaker XMSS clipboard payload."
        case .noFileMakerData:
            return "Copy script steps or a script in FileMaker Pro before importing."
        case .fileMakerDataDecodeFailed:
            return "The FileMaker clipboard payload could not be decoded as XML."
        }
    }
}

enum FileMakerClipboardKind: Equatable {
    case scriptSteps
    case scripts
}

struct FileMakerClipboardPayload {
    let kind: FileMakerClipboardKind
    let xml: String
    let pasteboardType: String
}

@MainActor
enum ClipboardService {
    // FileMaker Pro 26 publishes both the legacy CorePasteboard flavour and
    // macOS's dynamically registered UTI for the XMSS four-character code.
    // The com.apple.ostype alias is also written for older macOS/FileMaker pairs.
    static let fileMaker26ScriptStepsType = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x584D5353")
    static let dynamicScriptStepsType = NSPasteboard.PasteboardType("dyn.ah62d4rv4gk8zuxnxnq")
    static let legacyScriptStepsType = NSPasteboard.PasteboardType("com.apple.ostype:XMSS")
    static let fileMakerScriptsType = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x584D5343")
    static let legacyScriptsType = NSPasteboard.PasteboardType("com.apple.ostype:XMSC")

    static let fileMakerScriptStepTypes = [
        fileMaker26ScriptStepsType,
        dynamicScriptStepsType,
        legacyScriptStepsType
    ]

    static let fileMakerScriptTypes = [
        fileMakerScriptsType,
        legacyScriptsType
    ]

    static func writeFileMakerScriptSteps(xml: String) throws {
        guard let data = xml.data(using: .utf8) else {
            throw ClipboardServiceError.encodingFailed
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let writeResults = fileMakerScriptStepTypes.map { pasteboard.setData(data, forType: $0) }
        guard writeResults.prefix(2).allSatisfy({ $0 }) else {
            throw ClipboardServiceError.fileMakerWriteFailed
        }
        // Plain text is an intentionally secondary representation for diagnostics.
        // FileMaker selects the XMSS representation when pasting into Script Workspace.
        _ = pasteboard.setString(xml, forType: .string)
    }

    static func readPlainText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func readFileMakerXML() throws -> FileMakerClipboardPayload {
        let pasteboard = NSPasteboard.general
        let candidates: [(NSPasteboard.PasteboardType, FileMakerClipboardKind)] =
            fileMakerScriptStepTypes.map { ($0, .scriptSteps) }
            + fileMakerScriptTypes.map { ($0, .scripts) }

        for (type, kind) in candidates {
            guard let data = pasteboard.data(forType: type) else { continue }
            guard let xml = decodeXML(data) else {
                throw ClipboardServiceError.fileMakerDataDecodeFailed
            }
            return FileMakerClipboardPayload(kind: kind, xml: xml, pasteboardType: type.rawValue)
        }

        throw ClipboardServiceError.noFileMakerData
    }

    static func containsFileMakerScriptSteps() -> Bool {
        NSPasteboard.general.availableType(from: fileMakerScriptStepTypes) != nil
    }

    static func typeNames() -> [String] {
        NSPasteboard.general.types?.map(\.rawValue) ?? []
    }

    private static func decodeXML(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian]
        for encoding in encodings {
            if let value = String(data: data, encoding: encoding),
               value.contains("<fmxmlsnippet") || value.contains("<FMObjectTransfer") {
                return value
            }
        }
        return nil
    }
}

@MainActor
struct ClipboardClient {
    var readPlainText: () -> String?
    var readFileMakerXML: () throws -> FileMakerClipboardPayload
    var writeFileMakerScriptSteps: (String) throws -> Void
    var containsFileMakerScriptSteps: () -> Bool
    var writePlainText: (String) -> Bool
    var typeNames: () -> [String]

    static let live = ClipboardClient(
        readPlainText: { ClipboardService.readPlainText() },
        readFileMakerXML: { try ClipboardService.readFileMakerXML() },
        writeFileMakerScriptSteps: { try ClipboardService.writeFileMakerScriptSteps(xml: $0) },
        containsFileMakerScriptSteps: { ClipboardService.containsFileMakerScriptSteps() },
        writePlainText: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        },
        typeNames: { ClipboardService.typeNames() }
    )
}
