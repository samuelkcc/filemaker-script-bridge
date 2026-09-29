import Foundation

/// Shared by compilation and Smart Fix. Never discard unrecognized options.
struct ExportRecordsSyntax {
    var values: [String: String] = [:]
    var error: String?

    init(_ body: String) {
        let labels = ["With dialog:", "Create folders:", "File:", "File Name:", "Format:",
                      "Character set:", "Use field names:", "Field order:", "Worksheet:"]
        for part in TextUtilities.topLevelComponents(in: body) where !part.isEmpty {
            let key: String
            let value: String
            if part.caseInsensitiveCompare("No dialog") == .orderedSame {
                key = "With dialog:"; value = "Off"
            } else if part.caseInsensitiveCompare("Use field names as column names") == .orderedSame {
                key = "Use field names:"; value = "On"
            } else if let label = labels.first(where: { TextUtilities.value(afterLabel: $0, in: part) != nil }) {
                key = label == "File Name:" ? "File:" : label
                value = TextUtilities.value(afterLabel: label, in: part)!
            } else {
                error = "Export Records has an unsupported option: \(part). Complete it in FileMaker or edit the replacement."
                return
            }
            guard values[key] == nil else {
                error = "Export Records has a duplicate option: \(key)"
                return
            }
            values[key] = value
        }
    }

    static func fields(_ value: String) -> [ExportRecordField]? {
        let parts = TextUtilities.topLevelComponents(in: value, separator: ",")
        let fields = parts.compactMap { part -> ExportRecordField? in
            guard part.components(separatedBy: "::").count == 2,
                  let field = TextUtilities.splitFieldReference(part) else { return nil }
            return ExportRecordField(table: field.table, field: field.field)
        }
        return !fields.isEmpty && fields.count == parts.count ? fields : nil
    }

    static func text(_ values: [String: String]) -> String {
        let order = ["With dialog:", "Create folders:", "File:", "Format:", "Character set:",
                     "Use field names:", "Worksheet:", "Field order:"]
        return "Export Records [ " + order.compactMap { key in values[key].map { key + " " + $0 } }.joined(separator: " ; ") + " ]"
    }
}
