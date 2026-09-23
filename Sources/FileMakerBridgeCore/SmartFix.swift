import Foundation

enum DialogSyntax {
    static func components(_ body: String) -> [String] {
        var parts = TextUtilities.topLevelComponents(in: body)
        let labels = ["Title:", "Message:", "Default Button:", "Button 2:", "Button 3:", "Commit:"]
        func isNamed(_ value: String) -> Bool {
            labels.contains { TextUtilities.value(afterLabel: $0, in: value) != nil }
                || value.range(of: #"^[A-Za-z][A-Za-z 0-9]*:"#, options: .regularExpression) != nil
        }
        if parts.count >= 2, !isNamed(parts[0]), !isNamed(parts[1]) {
            parts[0] = "Title: " + parts[0]
            parts[1] = "Message: " + parts[1]
        } else if parts.count == 1, !isNamed(parts[0]) {
            parts[0] = "Message: " + parts[0]
        }
        return parts
    }
}

public enum SmartFixAction: String, CaseIterable, Sendable {
    case keep = "Keep for later"
    case replace = "Use replacement"
    case omit = "Omit step"
}

public struct SmartFixItem: Identifiable, Sendable {
    public var id: Int { line }
    public let line: Int
    public let endLine: Int
    public let original: String
    public let reason: String
    public let suggestion: String?
    public var replacement: String
    public var action: SmartFixAction = .keep
}

/// A review is tied to a source snapshot. Applying it never writes the clipboard.
public struct SmartFixReview: Sendable {
    public let source: String
    public var items: [SmartFixItem]

    public init(source: String, preservedSteps: [String: PreservedFileMakerStep] = [:]) {
        self.source = source
        let result = FileMakerXMLCompiler().compile(source, preservedSteps: preservedSteps)
        let physical = Self.lines(source)
        items = result.logicalLines.compactMap { line in
            let issues = result.issues.filter { $0.line == line.lineNumber }
            var suggestion: String?
            var reason = issues.map(\.message).joined(separator: "\n")
            if let body = TextUtilities.bracketBody(forPrefix: "Show Custom Dialog", in: line.text) {
                var parts = DialogSyntax.components(body)
                let defaultIndex = parts.firstIndex { TextUtilities.value(afterLabel: "Default Button:", in: $0) != nil }
                let missingDefault = defaultIndex == nil || defaultIndex.map {
                    TextUtilities.topLevelComponents(in: parts[$0], separator: ",").first
                        .flatMap { TextUtilities.value(afterLabel: "Default Button:", in: $0) }?.isEmpty == true
                } == true
                if missingDefault {
                    let button = "Default Button: \"OK\", Commit: No"
                    if let defaultIndex { parts[defaultIndex] = button }
                    else {
                        let index = parts.firstIndex { $0.lowercased().hasPrefix("button ") } ?? parts.count
                        parts.insert(button, at: index)
                    }
                    let candidate = "Show Custom Dialog [ " + parts.joined(separator: " ; ") + " ]"
                    if Self.isNativeReplacement(candidate) {
                        suggestion = candidate
                        reason += (reason.isEmpty ? "" : "\n") + "Add an explicit OK default button with Commit: No. This button will not commit the record; review the label and commit choice."
                    }
                }
            }
            guard !reason.isEmpty else { return nil }
            // Find the shortest physical span that normalizes to this logical step.
            let start = line.lineNumber - 1
            guard start >= 0, start < physical.count else { return nil }
            var end = start
            while end < physical.count - 1 {
                let normalized = TextUtilities.normalizeLogicalLines(physical[start...end].joined(separator: "\n"))
                if normalized.count == 1, normalized[0].text == line.text { break }
                end += 1
            }
            return SmartFixItem(line: line.lineNumber, endLine: end + 1, original: line.text,
                                reason: reason, suggestion: suggestion, replacement: suggestion ?? line.text)
        }
        // Recover the two-comment TODO blocks emitted by earlier exports, too.
        for (index, heading) in result.logicalLines.enumerated() {
            guard heading.text.hasPrefix("#"), heading.text.contains("FileMaker Script Bridge TODO"),
                  index + 1 < result.logicalLines.count else { continue }
            let draftLine = result.logicalLines[index + 1]
            guard draftLine.text.hasPrefix("#"),
                  let marker = draftLine.text.range(of: " in FileMaker. AI draft: ") else { continue }
            let draft = String(draftLine.text[marker.upperBound...])
            guard !draft.hasPrefix("#") else { continue }
            let recovered = SmartFixReview(source: draft).items.first
            let suggestion = recovered?.suggestion ?? (Self.isNativeReplacement(draft) ? draft : nil)
            items.append(SmartFixItem(
                line: heading.lineNumber, endLine: draftLine.lineNumber, original: draft,
                reason: "Recover an exported TODO comment as a native step. " + (recovered?.reason ?? "Review the original AI draft before applying."),
                suggestion: suggestion, replacement: suggestion ?? draft
            ))
        }
        items.sort { $0.line < $1.line }
    }

    public static func isNativeReplacement(_ text: String) -> Bool {
        let result = FileMakerXMLCompiler().compile(text, options: .init(convertUnsupportedLinesToComments: false))
        return result.canCopyToFileMaker && result.issues.isEmpty
            && result.steps.allSatisfy { if case .comment = $0 { return false }; return true }
    }

    public func applying(to currentSource: String) throws -> String {
        guard currentSource == source else { throw SmartFixError.staleReview }
        var lines = Self.lines(source)
        for item in items.sorted(by: { $0.line > $1.line }) where item.action != .keep {
            let replacement: String
            switch item.action {
            case .keep: continue
            case .replace:
                guard Self.isNativeReplacement(item.replacement) else { throw SmartFixError.invalidReplacement(item.line) }
                replacement = item.replacement
            case .omit:
                replacement = "# Omitted by Smart Fix: " + item.original
            }
            let indent = String(lines[item.line - 1].prefix(while: { $0 == " " || $0 == "\t" }))
            lines.replaceSubrange((item.line - 1)..<item.endLine, with: Self.lines(replacement).map { indent + $0 })
        }
        return lines.joined(separator: "\n")
    }

    private static func lines(_ source: String) -> [String] {
        source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }
}

public enum SmartFixError: LocalizedError {
    case staleReview
    case invalidReplacement(Int)

    public var errorDescription: String? {
        switch self {
        case .staleReview: return "The script changed. Close Smart Fix and review the latest script."
        case .invalidReplacement(let line): return "The replacement for line \(line) does not compile as native steps. Edit it or choose Keep for later."
        }
    }
}
