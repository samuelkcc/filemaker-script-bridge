import AppKit
import FileMakerBridgeCore
import SwiftUI

struct ScriptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let issues: [CompilationIssue]
    let requestedLine: Int?
    let navigationRevision: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = text
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyHighlighting()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            ))
        }
        context.coordinator.applyHighlighting()

        if context.coordinator.handledNavigationRevision != navigationRevision,
           let requestedLine {
            context.coordinator.handledNavigationRevision = navigationRevision
            context.coordinator.focus(line: requestedLine)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptTextEditor
        weak var textView: NSTextView?
        var handledNavigationRevision = 0

        init(parent: ScriptTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            applyHighlighting()
        }

        func focus(line: Int) {
            guard let textView, let range = lineRange(line, in: textView.string) else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }

        func applyHighlighting() {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            let source = textView.string as NSString
            let fullRange = NSRange(location: 0, length: source.length)
            let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.font, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
            layoutManager.addTemporaryAttributes([
                .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.24, alpha: 1),
                .font: baseFont
            ], forCharacterRange: fullRange)

            applyPattern(
                #"(?m)^\s*([A-Za-z][A-Za-z0-9 /#-]*?)(?=\s*\[|\s*$)"#,
                color: NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.78, alpha: 1),
                font: .monospacedSystemFont(ofSize: 13, weight: .semibold),
                captureGroup: 1,
                layoutManager: layoutManager,
                source: source
            )
            applyPattern(
                #"\$\$?[A-Za-z_][A-Za-z0-9_]*"#,
                color: NSColor(calibratedRed: 0.68, green: 0.18, blue: 0.62, alpha: 1),
                layoutManager: layoutManager,
                source: source
            )
            applyPattern(
                #"\b(?:True|False|Yes|No|On|Off|Always|Minimum|Never)\b"#,
                color: NSColor(calibratedRed: 0.05, green: 0.52, blue: 0.60, alpha: 1),
                layoutManager: layoutManager,
                source: source
            )
            applyPattern(
                #"(?:\"(?:\\.|[^\"\\])*\"|“[^”]*”|‘[^’]*’)"#,
                color: NSColor(calibratedRed: 0.84, green: 0.38, blue: 0.08, alpha: 1),
                layoutManager: layoutManager,
                source: source
            )
            applyPattern(
                #"[\[\]();]"#,
                color: NSColor(calibratedRed: 0.39, green: 0.24, blue: 0.74, alpha: 1),
                layoutManager: layoutManager,
                source: source
            )
            applyPattern(
                #"(?m)^\s*(?:#|//).*$"#,
                color: NSColor(calibratedRed: 0.12, green: 0.50, blue: 0.25, alpha: 1),
                layoutManager: layoutManager,
                source: source
            )

            for issue in parent.issues {
                guard let range = lineRange(issue.line, in: textView.string) else { continue }
                let color = issue.severity == .error
                    ? NSColor(calibratedRed: 1.00, green: 0.20, blue: 0.18, alpha: 0.14)
                    : NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.08, alpha: 0.28)
                layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
                if issue.severity == .warning {
                    layoutManager.addTemporaryAttribute(
                        .underlineStyle,
                        value: NSUnderlineStyle.single.rawValue,
                        forCharacterRange: range
                    )
                }
            }
        }

        private func applyPattern(
            _ pattern: String,
            color: NSColor,
            font: NSFont? = nil,
            captureGroup: Int = 0,
            layoutManager: NSLayoutManager,
            source: NSString
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(location: 0, length: source.length)
            for match in regex.matches(in: source as String, range: range) {
                let matchRange = match.range(at: captureGroup)
                guard matchRange.location != NSNotFound else { continue }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: matchRange)
                if let font {
                    layoutManager.addTemporaryAttribute(.font, value: font, forCharacterRange: matchRange)
                }
            }
        }

        private func lineRange(_ requestedLine: Int, in text: String) -> NSRange? {
            guard requestedLine > 0 else { return nil }
            let source = text as NSString
            var location = 0
            var currentLine = 1

            while currentLine < requestedLine, location < source.length {
                let range = source.lineRange(for: NSRange(location: location, length: 0))
                location = NSMaxRange(range)
                currentLine += 1
            }
            guard currentLine == requestedLine, location <= source.length else { return nil }
            let range = source.lineRange(for: NSRange(location: location, length: 0))
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: range
            )
            return NSRange(location: lineStart, length: max(0, contentsEnd - lineStart))
        }
    }
}
