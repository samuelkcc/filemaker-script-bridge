import Foundation

public struct SmartFixQuestion: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let prompt: String
    public let choices: [String]
    public var answer: String = ""
}

struct SmartFixParameters {
    let step: String
    var values: [String: String]
    var questions: [SmartFixQuestion] = []
    var notes: [String] = []

    var text: String { Self.text(step: step, values: values) }

    static func text(step: String, values: [String: String]) -> String {
        if step == "Export Records" { return ExportRecordsSyntax.text(values) }
        return "Read from Data File [ " + ["File ID:", "Amount (bytes):", "Target:", "Read as:"]
            .compactMap { key in values[key].map { key + " " + $0 } }.joined(separator: " ; ") + " ]"
    }

    mutating func ask(_ key: String, _ prompt: String, choices: [String] = []) {
        questions.append(SmartFixQuestion(key: key, prompt: prompt, choices: choices))
    }

    static func prepare(_ line: String, physical: String) -> Self? {
        if let body = TextUtilities.bracketBody(forPrefix: "Export Records", in: line) {
            let syntax = ExportRecordsSyntax(body)
            guard syntax.error == nil else { return nil }
            var form = Self(step: "Export Records", values: syntax.values)
            for (key, value) in [("With dialog:", "Off"), ("Create folders:", "Off"), ("Character set:", "Unicode")] {
                if form.values[key]?.isEmpty != false {
                    form.values[key] = value
                    form.notes.append("Suggest \(key) \(value).")
                }
            }
            let path = TextUtilities.unquote(form.values["File:"] ?? "")
            if path.isEmpty { form.ask("File:", "Where should the XLSX be saved? Enter a FileMaker path or $path variable.") }
            if form.values["Format:"]?.isEmpty != false,
               form.values["Worksheet:"]?.isEmpty == false || path.lowercased().hasSuffix(".xlsx") {
                form.values["Format:"] = "XLSX"
                form.notes.append("Infer XLSX from the worksheet option or .xlsx filename.")
            }
            if TextUtilities.unquote(form.values["Format:"] ?? "").uppercased() != "XLSX" {
                form.ask("Format:", "Which export format is intended? The editable export currently supports XLSX only.", choices: ["XLSX"])
            }
            for key in ["With dialog:", "Create folders:", "Use field names:"] {
                if !["on", "off", "yes", "no", "true", "false", "0", "1"].contains(TextUtilities.unquote(form.values[key] ?? "").lowercased()) {
                    let prompt = key == "Use field names:" ? "Should the first row contain field names as column headings?" : "Choose \(key)"
                    form.ask(key, prompt, choices: ["On", "Off"])
                }
            }
            if !["unicode", "unicode (utf-16)", "utf-16"].contains(TextUtilities.unquote(form.values["Character set:"] ?? "").lowercased()) {
                form.ask("Character set:", "Confirm the XLSX character set.", choices: ["Unicode"])
            }
            if let worksheet = form.values["Worksheet:"], worksheet.isEmpty {
                form.ask("Worksheet:", "What worksheet name calculation should be used? For example, \"Sheet1\" or $sheetName.")
            }
            // Physical line boundaries can disambiguate a list that lost its commas.
            // Never guess field boundaries from spaces in a flattened TODO comment.
            if ExportRecordsSyntax.fields(form.values["Field order:"] ?? "") == nil,
               let range = physical.range(of: #"(?is)Field order:\s*([^;\]]+)"#, options: .regularExpression) {
                let block = String(physical[range])
                let raw = String(block.dropFirst("Field order:".count))
                let fields = raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if fields.count > 1, fields.allSatisfy({ ExportRecordsSyntax.fields($0)?.count == 1 }) {
                    form.values["Field order:"] = fields.joined(separator: ", ")
                    form.notes.append("Separate the explicitly listed field lines with commas, preserving their order.")
                }
            }
            if ExportRecordsSyntax.fields(form.values["Field order:"] ?? "") == nil {
                form.ask("Field order:", "Which fields should be exported, in what order? Use Table::Field, Table::Other field.")
            }
            return form
        }
        if let body = TextUtilities.bracketBody(forPrefix: "Read from Data File", in: line) {
            var values: [String: String] = [:]
            let labels = ["File ID:", "Amount (bytes):", "Amount (Unicode code units):", "Amount:", "Target:", "Read as:"]
            for part in TextUtilities.topLevelComponents(in: body) where !part.isEmpty {
                guard let label = labels.first(where: { TextUtilities.value(afterLabel: $0, in: part) != nil }) else { return nil }
                let key = label.hasPrefix("Amount") ? "Amount (bytes):" : label
                guard values[key] == nil else { return nil }
                values[key] = TextUtilities.value(afterLabel: label, in: part)!
            }
            // A bounded read must never be "fixed" by dropping its requested amount.
            guard (values["Amount (bytes):"] ?? "").isEmpty else { return nil }
            var form = Self(step: "Read from Data File", values: values)
            form.values["Amount (bytes):"] = ""
            form.notes.append("Blank Amount reads the whole file (up to 64 MB per read).")
            if values["File ID:"]?.isEmpty != false { form.ask("File ID:", "Which open file ID should be read? Enter a calculation, for example $fileID.") }
            if values["Target:"]?.isEmpty != false { form.ask("Target:", "Where should the data be stored? Enter a $variable or Table::Field.") }
            if DataFileReadEncoding(rawValue: TextUtilities.unquote(values["Read as:"] ?? "").uppercased()) == nil {
                form.ask("Read as:", "Is this binary data (such as XLSX) or text? Choose the encoding.", choices: ["Bytes", "UTF-8", "UTF-16"])
            }
            return form
        }
        return nil
    }
}
