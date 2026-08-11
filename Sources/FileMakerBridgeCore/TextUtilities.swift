import Foundation

enum TextUtilities {
    static func normalizeLogicalLines(_ source: String) -> [LogicalLine] {
        let physicalLines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var result: [LogicalLine] = []
        var current = ""
        var currentLineNumber = 1
        var squareDepth = 0

        for (index, physical) in physicalLines.enumerated() {
            let lineNumber = index + 1
            var line = physical.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("```") {
                continue
            }

            line = stripListPrefix(line)
            if line.isEmpty {
                continue
            }

            if current.isEmpty {
                current = line
                currentLineNumber = lineNumber
            } else {
                current += " " + line
            }

            squareDepth += squareBracketDelta(in: line)
            if squareDepth <= 0 {
                result.append(LogicalLine(lineNumber: currentLineNumber, text: current))
                current = ""
                squareDepth = 0
            }
        }

        if !current.isEmpty {
            result.append(LogicalLine(lineNumber: currentLineNumber, text: current))
        }

        return result
    }

    static func caseInsensitivePrefix(_ prefix: String, in value: String) -> Bool {
        value.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
    }

    static func bracketBody(forPrefix prefix: String, in line: String) -> String? {
        guard hasStepNamePrefix(prefix, in: line) else { return nil }
        guard let open = line.firstIndex(of: "["), let close = line.lastIndex(of: "]"), open < close else {
            return nil
        }
        return String(line[line.index(after: open)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasStepNamePrefix(_ prefix: String, in line: String) -> Bool {
        guard caseInsensitivePrefix(prefix, in: line) else { return false }
        guard line.count > prefix.count else { return true }
        let boundary = line.index(line.startIndex, offsetBy: prefix.count)
        let suffix = line[boundary...].drop(while: \.isWhitespace)
        return suffix.isEmpty || suffix.first == "["
    }

    static func topLevelComponents(in value: String, separator: Character = ";") -> [String] {
        var parts: [String] = []
        var buffer = ""
        var roundDepth = 0
        var squareDepth = 0
        var curlyDepth = 0
        var quote: Character?
        var previous: Character?

        for character in value {
            if let activeQuote = quote {
                buffer.append(character)
                if character == activeQuote && previous != "\\" {
                    quote = nil
                }
                previous = character
                continue
            }

            if character == "\"" || character == "“" || character == "‘" {
                quote = matchingQuote(for: character)
                buffer.append(character)
                previous = character
                continue
            }

            switch character {
            case "(": roundDepth += 1
            case ")": roundDepth = max(0, roundDepth - 1)
            case "[": squareDepth += 1
            case "]": squareDepth = max(0, squareDepth - 1)
            case "{": curlyDepth += 1
            case "}": curlyDepth = max(0, curlyDepth - 1)
            default: break
            }

            if character == separator && roundDepth == 0 && squareDepth == 0 && curlyDepth == 0 {
                parts.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                buffer = ""
            } else {
                buffer.append(character)
            }
            previous = character
        }

        parts.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts
    }

    static func value(afterLabel label: String, in component: String) -> String? {
        guard let range = component.range(of: label, options: [.caseInsensitive, .anchored]) else {
            return nil
        }
        return String(component[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }

        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("‘", "’")]
        for (opening, closing) in pairs where trimmed.first == opening && trimmed.last == closing {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    static func objectName(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        let closing: Character
        switch first {
        case "\"": closing = "\""
        case "“": closing = "”"
        case "‘": closing = "’"
        default:
            if let context = trimmed.range(of: " (", options: [.backwards]) {
                return String(trimmed[..<context.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmed
        }

        var index = trimmed.index(after: trimmed.startIndex)
        var previous: Character?
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character == closing && previous != "\\" {
                return String(trimmed[trimmed.index(after: trimmed.startIndex)..<index])
            }
            previous = character
            index = trimmed.index(after: index)
        }
        return unquote(trimmed)
    }

    static func splitFieldReference(_ value: String) -> (table: String, field: String)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "::") else { return nil }
        let table = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let field = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !table.isEmpty, !field.isEmpty else { return nil }
        return (unquote(table), unquote(field))
    }

    private static func stripListPrefix(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)

        for bullet in ["- ", "* ", "• ", "– ", "— "] where value.hasPrefix(bullet) {
            return String(value.dropFirst(bullet.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var index = value.startIndex
        while index < value.endIndex, value[index].isNumber {
            index = value.index(after: index)
        }
        if index > value.startIndex, index < value.endIndex, value[index] == "." {
            let afterDot = value.index(after: index)
            if afterDot < value.endIndex, value[afterDot].isWhitespace {
                value = String(value[value.index(after: afterDot)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return value
    }

    private static func squareBracketDelta(in value: String) -> Int {
        var depth = 0
        var quote: Character?
        var previous: Character?

        for character in value {
            if let activeQuote = quote {
                if character == activeQuote && previous != "\\" {
                    quote = nil
                }
                previous = character
                continue
            }
            if character == "\"" || character == "“" || character == "‘" {
                quote = matchingQuote(for: character)
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
            }
            previous = character
        }
        return depth
    }

    private static func matchingQuote(for opening: Character) -> Character {
        switch opening {
        case "“": return "”"
        case "‘": return "’"
        default: return opening
        }
    }
}
