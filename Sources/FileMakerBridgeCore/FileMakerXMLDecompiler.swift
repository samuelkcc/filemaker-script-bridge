import Foundation

public struct FileMakerXMLDecompiler: Sendable {
    public init() {}

    public func decompile(_ xml: String) -> DecompilationResult {
        guard let data = xml.data(using: .utf8) else {
            return failure(xml, "The FileMaker clipboard XML is not valid UTF-8 text.")
        }

        let builder = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder

        guard parser.parse(), builder.parseError == nil else {
            return failure(
                xml,
                builder.parseError?.localizedDescription ?? parser.parserError?.localizedDescription ?? "Invalid XML."
            )
        }

        let scriptNodes = builder.roots
            .flatMap { $0.descendants(named: "Script") }
            .filter { $0.child(named: "Step") != nil }
        let scriptNames = scriptNodes.compactMap { node -> String? in
            let value = node.attributes["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        let stepNodes = builder.roots.flatMap { $0.descendants(named: "Step") }

        guard !stepNodes.isEmpty else {
            return failure(xml, "No FileMaker script steps were found in the clipboard XML.")
        }

        var output: [String] = []
        if scriptNames.count == 1, let scriptName = scriptNames.first {
            output.append("# FileMaker Script: \(scriptName)")
        } else if scriptNames.count > 1 {
            output.append("# FileMaker Scripts: \(scriptNames.joined(separator: ", "))")
        }

        var indentation = 0
        var unsupportedCount = 0
        var warnings: [String] = []
        var preservedSteps: [String: PreservedFileMakerStep] = [:]

        for (index, node) in stepNodes.enumerated() {
            let id = Int(node.attributes["id"] ?? "")

            if shouldOutdentBefore(id: id) {
                indentation = max(0, indentation - 1)
            }

            var rendered = render(node)
            if rendered.unsupported {
                unsupportedCount += 1
                let token = "SCKC-P\(index + 1)-ID\(id.map(String.init) ?? "unknown")"
                let preserved = PreservedFileMakerStep(
                    token: token,
                    name: rendered.name,
                    id: id,
                    xml: node.serializedXML(indentation: "  ")
                )
                preservedSteps[token] = preserved
                rendered = RenderedStep(
                    name: rendered.name,
                    text: "# ↔ FileMaker step preserved unchanged: \(rendered.name) (ID \(id.map(String.init) ?? "unknown")) [\(token)] — options locked; keep this line for return to FileMaker",
                    unsupported: true
                )
                warnings.append("\(rendered.name) (ID \(id.map(String.init) ?? "unknown")) is preserved losslessly for same-session round trips, but its options are not editable as readable text.")
            }

            let prefix = String(repeating: "    ", count: indentation)
            let indentedText = rendered.text
                .components(separatedBy: "\n")
                .map { prefix + $0 }
                .joined(separator: "\n")
            output.append(indentedText)

            if shouldIndentAfter(id: id) {
                indentation += 1
            }
        }

        return DecompilationResult(
            sourceXML: xml,
            text: output.joined(separator: "\n"),
            stepCount: stepNodes.count,
            unsupportedStepCount: unsupportedCount,
            scriptNames: scriptNames,
            warnings: warnings,
            preservedSteps: preservedSteps
        )
    }

    private func render(_ node: ParsedXMLNode) -> RenderedStep {
        let id = Int(node.attributes["id"] ?? "")
        let name = node.attributes["name"] ?? "Unknown Step"

        switch id {
        case 1:
            let scriptName = node.child(named: "Script")?.attributes["name"] ?? "<unknown script>"
            var result = "Perform Script [ \(quoteObjectName(scriptName))"
            if let parameter = node.directText(named: "Calculation"), !parameter.isEmpty {
                result += " ; Parameter: \(parameter)"
            }
            result += " ]"
            return supported(name, result)

        case 6:
            if node.child(named: "LayoutDestination")?.attributes["value"] == "OriginalLayout" {
                return supported(name, "Go to Layout [ original layout ]")
            }
            let layoutName = node.child(named: "Layout")?.attributes["name"] ?? "<unknown layout>"
            return supported(name, "Go to Layout [ \(quoteObjectName(layoutName)) ]")

        case 7, 23, 32, 38, 44, 79, 88, 90, 93, 102, 105, 112, 113, 114, 118, 129, 140, 149, 151, 156, 165, 172, 183, 237:
            return supported(name, canonicalName(for: id) ?? name)

        case 8, 21, 24, 25, 27, 98, 101, 104, 127, 133, 152, 182, 225:
            guard matchesCapturedDefault(node, name: canonicalName(for: id) ?? name) else {
                return renderGeneric(node, id: id, name: name)
            }
            return supported(name, canonicalName(for: id) ?? name)

        case 36:
            if matchesCapturedDefault(node, name: canonicalName(for: id) ?? name) {
                return supported(name, canonicalName(for: id) ?? name)
            }
            return renderExportRecords(node, id: id, name: name)

        case 35:
            if matchesCapturedDefault(node, name: canonicalName(for: id) ?? name) {
                return supported(name, canonicalName(for: id) ?? name)
            }
            return renderImportRecords(node, id: id, name: name)

        case 143:
            if matchesCapturedDefault(node, name: canonicalName(for: id) ?? name) {
                return supported(name, canonicalName(for: id) ?? name)
            }
            return renderSaveRecordsAsExcel(node, id: id, name: name)

        case 63:
            return renderSendMail(node, id: id, name: name)

        case 31:
            let raw = node.child(named: "WindowState")?.attributes["value"] ?? ""
            let readable: String
            switch raw.lowercased() {
            case "resizetofit": readable = "Resize to Fit"
            case "maximize": readable = "Maximize"
            case "minimize": readable = "Minimize"
            case "restore": readable = "Restore"
            case "hide": readable = "Hide"
            default: return renderGeneric(node, id: id, name: name)
            }
            return supported(name, "Adjust Window [ \(readable) ]")

        case 120:
            let raw = node.child(named: "WindowArrangement")?.attributes["value"] ?? ""
            let readable: String
            switch raw.lowercased() {
            case "tilehorizontally": readable = "Tile Horizontally"
            case "tilevertically": readable = "Tile Vertically"
            case "cascade": readable = "Cascade"
            case "bringalltofront": readable = "Bring All to Front"
            default: return renderGeneric(node, id: id, name: name)
            }
            return supported(name, "Arrange All Windows [ \(readable) ]")

        case 30:
            let raw = node.child(named: "View")?.attributes["value"] ?? ""
            guard ["form", "list", "table", "cycle"].contains(raw.lowercased()) else {
                return renderGeneric(node, id: id, name: name)
            }
            return supported(name, "View As [ \(raw.capitalized) ]")

        case 81:
            let raw = node.child(named: "ScrollOperation")?.attributes["value"] ?? ""
            let readable: String
            switch raw.lowercased() {
            case "home": readable = "Home"
            case "end": readable = "End"
            case "pageup": readable = "Page Up"
            case "pagedown": readable = "Page Down"
            case "toselection": readable = "To Selection"
            default: return renderGeneric(node, id: id, name: name)
            }
            return supported(name, "Scroll Window [ \(readable) ]")

        case 92:
            let raw = node.child(named: "ShowHide")?.attributes["value"] ?? ""
            guard ["show", "hide", "toggle"].contains(raw.lowercased()) else {
                return renderGeneric(node, id: id, name: name)
            }
            return supported(name, "Show/Hide Text Ruler [ \(raw.capitalized) ]")

        case 166:
            let raw = node.child(named: "ShowHide")?.attributes["value"] ?? ""
            guard ["show", "hide", "toggle"].contains(raw.lowercased()) else {
                return renderGeneric(node, id: id, name: name)
            }
            let lock = boolAttribute(node.child(named: "Lock"), name: "state") ? "On" : "Off"
            return supported(name, "Show/Hide Menubar [ \(raw.capitalized) ; Lock: \(lock) ]")

        case 29:
            let raw = node.child(named: "ShowHide")?.attributes["value"] ?? ""
            guard ["show", "hide", "toggle"].contains(raw.lowercased()) else {
                return renderGeneric(node, id: id, name: name)
            }
            let lock = boolAttribute(node.child(named: "Lock"), name: "state") ? "On" : "Off"
            let include = boolAttribute(node.child(named: "IncludeEditRecordToolbar"), name: "state") ? "On" : "Off"
            return supported(name, "Show/Hide Toolbars [ \(raw.capitalized) ; Lock: \(lock) ; Include Edit Record Toolbar: \(include) ]")

        case 97:
            let raw = node.child(named: "Zoom")?.attributes["value"] ?? ""
            let readable: String
            switch raw.lowercased() {
            case "25", "50", "75", "100", "150", "200", "300", "400": readable = "\(raw)%"
            case "zoomin": readable = "Zoom In"
            case "zoomout": readable = "Zoom Out"
            case "bycalculation":
                guard let calculation = node.directText(named: "Calculation") else {
                    return renderGeneric(node, id: id, name: name)
                }
                readable = "Custom: \(calculation)"
            default: return renderGeneric(node, id: id, name: name)
            }
            let lock = boolAttribute(node.child(named: "Lock"), name: "state") ? "On" : "Off"
            return supported(name, "Set Zoom Level [ \(readable) ; Lock: \(lock) ]")

        case 119:
            var options: [String] = []
            let target = node.child(named: "Window")?.attributes["value"] ?? "Current"
            if target.caseInsensitiveCompare("ByName") == .orderedSame {
                guard let calculation = node.text(at: ["Name", "Calculation"]) else {
                    return renderGeneric(node, id: id, name: name)
                }
                options.append("Name: \(calculation)")
                let currentFile = boolAttribute(node.child(named: "LimitToWindowsOfCurrentFile"), name: "state")
                options.append(currentFile ? "Current file" : "All files")
            } else {
                options.append("Current Window")
            }
            for (label, element) in [
                ("Height", "Height"), ("Width", "Width"),
                ("Top", "DistanceFromTop"), ("Left", "DistanceFromLeft")
            ] {
                if let calculation = node.text(at: [element, "Calculation"]) {
                    options.append("\(label): \(calculation)")
                }
            }
            return supported(name, "Move/Resize Window [ \(options.joined(separator: " ; ")) ]")

        case 124:
            var options: [String] = []
            let target = node.child(named: "Window")?.attributes["value"] ?? "Current"
            if target.caseInsensitiveCompare("ByName") == .orderedSame {
                guard let calculation = node.text(at: ["Name", "Calculation"]) else {
                    return renderGeneric(node, id: id, name: name)
                }
                options.append("Name: \(calculation)")
                let currentFile = boolAttribute(node.child(named: "LimitToWindowsOfCurrentFile"), name: "state")
                options.append(currentFile ? "Current file" : "All files")
            } else {
                options.append("Current Window")
            }
            if let newName = node.text(at: ["NewName", "Calculation"]) {
                options.append("New title: \(newName)")
            }
            return supported(name, "Set Window Title [ \(options.joined(separator: " ; ")) ]")

        case 155:
            let raw = node.child(named: "FindMatchingRecordsByField")?.attributes["value"] ?? ""
            let readable: String
            switch raw.lowercased() {
            case "findmatchingreplace": readable = "Replace"
            case "findmatchingconstrain": readable = "Constrain"
            case "findmatchingextend": readable = "Extend"
            default: return renderGeneric(node, id: id, name: name)
            }
            var result = "Find Matching Records [ \(readable)"
            if let field = node.child(named: "Field"),
               let table = field.attributes["table"], let fieldName = field.attributes["name"] {
                result += " ; Target: \(table)::\(fieldName)"
            }
            result += " ]"
            return supported(name, result)

        case 150:
            if let calculation = node.directText(named: "Calculation") {
                return supported(name, "Perform Quick Find [ \(calculation) ]")
            }
            guard matchesCapturedDefault(node, name: "Perform Quick Find") else {
                return renderGeneric(node, id: id, name: name)
            }
            return supported(name, "Perform Quick Find")

        case 154:
            let raw = node.child(named: "SortRecordsByField")?.attributes["value"] ?? ""
            let readable: String
            switch raw.lowercased() {
            case "sortascending": readable = "Ascending"
            case "sortdescending": readable = "Descending"
            case "sortvaluelist": readable = "Associated value list"
            default: return renderGeneric(node, id: id, name: name)
            }
            var result = "Sort Records by Field [ \(readable)"
            if let field = node.child(named: "Field"),
               let table = field.attributes["table"], let fieldName = field.attributes["name"] {
                result += " ; Target: \(table)::\(fieldName)"
            }
            result += " ]"
            return supported(name, result)

        case 126:
            guard node.child(named: "Restore")?.attributes["state"]?.caseInsensitiveCompare("False") == .orderedSame else {
                return renderGeneric(node, id: id, name: name)
            }
            let unindexed = boolAttribute(node.child(named: "Option"), name: "state") ? "On" : "Off"
            return supported(name, "Constrain Found Set [ Find without indexes: \(unindexed) ]")

        case 26:
            let withDialog = boolAttribute(node.child(named: "NoInteract"), name: "state") ? "Off" : "On"
            var result = "Omit Multiple Records [ With dialog: \(withDialog)"
            if let calculation = node.directText(named: "Calculation") {
                result += " ; Records: \(calculation)"
            }
            result += " ]"
            return supported(name, result)

        case 39:
            guard node.child(named: "Restore")?.attributes["state"]?.caseInsensitiveCompare("False") == .orderedSame else {
                return renderSortRecords(node, id: id, name: name)
            }
            guard node.child(named: "SortList") == nil else { return renderGeneric(node, id: id, name: name) }
            let withDialog = boolAttribute(node.child(named: "NoInteract"), name: "state") ? "Off" : "On"
            return supported(name, "Sort Records [ With dialog: \(withDialog) ]")

        case 16:
            let location = node.child(named: "RowPageLocation")?.attributes["value"] ?? "First"
            if location.caseInsensitiveCompare("ByCalculation") == .orderedSame {
                let calculation = node.directText(named: "Calculation") ?? ""
                return supported(name, "Go to Record/Request/Page [ By calculation: \(calculation) ]")
            }
            let readableLocation: String
            switch location.lowercased() {
            case "last": readableLocation = "Last"
            case "previous": readableLocation = "Previous"
            case "next": readableLocation = "Next"
            default: readableLocation = "First"
            }
            let exits = node.child(named: "Exit")?.attributes["state"]?.caseInsensitiveCompare("True") == .orderedSame
            let exitOption = exits && (readableLocation == "Next" || readableLocation == "Previous")
                ? " ; Exit after last"
                : ""
            return supported(name, "Go to Record/Request/Page [ \(readableLocation)\(exitOption) ]")

        case 9, 10, 51:
            let noInteract = boolAttribute(node.child(named: "NoInteract"), name: "state")
            let stepName: String
            switch id {
            case 9: stepName = "Delete Record/Request"
            case 10: stepName = "Delete All Records"
            default: stepName = "Revert Record/Request"
            }
            return supported(name, "\(stepName) [ With dialog: \(noInteract ? "Off" : "On") ]")

        case 22:
            let pause = boolAttribute(node.child(named: "Pause"), name: "state")
            return supported(name, "Enter Find Mode [ Pause: \(pause ? "On" : "Off") ]")

        case 28:
            let restore = boolAttribute(node.child(named: "Restore"), name: "state")
            if restore || node.child(named: "Query") != nil {
                return renderGeneric(node, id: id, name: name)
            }
            return supported(name, "Perform Find [ ]")

        case 68:
            return supported(name, "If [ \(node.directText(named: "Calculation") ?? "") ]")
        case 69:
            return supported(name, "Else")
        case 70:
            return supported(name, "End If")
        case 71:
            let rawFlush = node.child(named: "FlushType")?.attributes["value"] ?? LoopFlushMode.always.rawValue
            guard let flush = LoopFlushMode.allCases.first(where: {
                $0.rawValue.caseInsensitiveCompare(rawFlush) == .orderedSame
            }) else {
                return renderGeneric(node, id: id, name: name)
            }
            return supported(name, "Loop [ Flush: \(flush.rawValue) ]")
        case 72:
            return supported(name, "Exit Loop If [ \(node.directText(named: "Calculation") ?? "") ]")
        case 73:
            return supported(name, "End Loop")

        case 75:
            return supported(name, "Commit Records/Requests")

        case 76:
            let field = node.child(named: "Field")
            let tableName = field?.attributes["table"] ?? "<unknown table>"
            let fieldName = field?.attributes["name"] ?? "<unknown field>"
            let calculation = node.directText(named: "Calculation") ?? ""
            return supported(name, "Set Field [ \(tableName)::\(fieldName) ; \(calculation) ]")

        case 80:
            return supported(name, "Refresh Window")

        case 85, 86, 94, 115:
            let enabled = node.child(named: "Set")?.attributes["state"]?.caseInsensitiveCompare("True") == .orderedSame
            let stepName = canonicalName(for: id) ?? name
            return supported(name, "\(stepName) [ \(enabled ? "On" : "Off") ]")

        case 174:
            let enabled = node.child(named: "ShowHide")?.attributes["value"]?.caseInsensitiveCompare("Show") == .orderedSame
            return supported(name, "Enable Touch Keyboard [ \(enabled ? "On" : "Off") ]")

        case 87:
            let title = node.text(at: ["Title", "Calculation"])
            let message = node.text(at: ["Message", "Calculation"]) ?? "\"\""
            var components: [String] = []
            if let title, !title.isEmpty {
                components.append("Title: \(title)")
            }
            components.append("Message: \(message)")
            let buttonNodes = node.child(named: "Buttons")?.children.filter { $0.name == "Button" } ?? []
            for (index, button) in buttonNodes.prefix(3).enumerated() {
                guard let calculation = button.directText(named: "Calculation"), !calculation.isEmpty else {
                    continue
                }
                let label = index == 0 ? "Default Button" : "Button \(index + 1)"
                let commits = boolAttribute(button, name: "CommitState")
                components.append("\(label): \(calculation), Commit: \(commits ? "Yes" : "No")")
            }
            return supported(name, "Show Custom Dialog [ \(components.joined(separator: " ; ")) ]")

        case 89:
            let text = node.child(named: "Text")?.trimmedText ?? ""
            return supported(name, "# \(text)")

        case 103:
            if let calculation = node.directText(named: "Calculation"), !calculation.isEmpty {
                return supported(name, "Exit Script [ Text Result: \(calculation) ]")
            }
            return supported(name, "Exit Script")

        case 125:
            return supported(name, "Else If [ \(node.directText(named: "Calculation") ?? "") ]")

        case 141:
            let variableName = node.child(named: "Name")?.trimmedText ?? "$variable"
            let value = node.text(at: ["Value", "Calculation"]) ?? ""
            var result = "Set Variable [ \(variableName) ; Value: \(value)"
            if let repetition = node.text(at: ["Repetition", "Calculation"]),
               !repetition.isEmpty,
               repetition != "1" {
                result += " ; Repetition: \(repetition)"
            }
            result += " ]"
            return supported(name, result)

        case 147:
            let target = node.text(at: ["TargetName", "Calculation"]) ?? "\"\""
            let result = node.text(at: ["Result", "Calculation"]) ?? "\"\""
            return supported(name, "Set Field By Name [ \(target) ; \(result) ]")

        case 131:
            guard let field = node.child(named: "Field"),
                  let table = field.attributes["table"],
                  let fieldName = field.attributes["name"],
                  let path = node.directText(named: "UniversalPathList"),
                  !path.isEmpty,
                  let dialogOptions = node.child(named: "DialogOptions"),
                  dialogOptions.attributes["enable"]?.caseInsensitiveCompare("False") == .orderedSame,
                  dialogOptions.attributes["asFile"]?.caseInsensitiveCompare("True") == .orderedSame,
                  dialogOptions.child(named: "Storage")?.attributes["type"] == "UserChoice",
                  dialogOptions.child(named: "Compress")?.attributes["type"] == "UserChoice",
                  dialogOptions.child(named: "FilterList")?.children.isEmpty == true,
                  dialogOptions.child(named: "FilterList")?.trimmedText.isEmpty == true else {
                return renderGeneric(node, id: id, name: name)
            }
            return supported(
                name,
                "Insert File [ Target: \(table)::\(fieldName) ; \(quoteObjectName(path)) ]"
            )

        case 132:
            guard let field = node.child(named: "Field"),
                  let table = field.attributes["table"],
                  let fieldName = field.attributes["name"],
                  let path = node.directText(named: "UniversalPathList"),
                  !path.isEmpty,
                  !boolAttribute(node.child(named: "AutoOpen"), name: "state"),
                  !boolAttribute(node.child(named: "CreateEmail"), name: "state") else {
                return renderGeneric(node, id: id, name: name)
            }
            let createDirectories = boolAttribute(node.child(named: "CreateDirectories"), name: "state")
            return supported(
                name,
                "Export Field Contents [ \(table)::\(fieldName) ; \(quoteObjectName(path)) ; Create folders: \(createDirectories ? "Yes" : "No") ]"
            )

        case 164:
            guard let scriptName = node.child(named: "Script")?.attributes["name"], !scriptName.isEmpty else {
                return renderGeneric(node, id: id, name: name)
            }
            var result = "Perform Script on Server [ \(quoteObjectName(scriptName))"
            if let parameter = node.directText(named: "Calculation"), !parameter.isEmpty {
                result += " ; Parameter: \(parameter)"
            }
            let wait = boolAttribute(node.child(named: "WaitForCompletion"), name: "state")
            result += " ; Wait for completion: \(wait ? "On" : "Off") ]"
            return supported(name, result)

        case 167:
            guard let objectName = node.text(at: ["ObjectName", "Calculation"]), !objectName.isEmpty else {
                return renderGeneric(node, id: id, name: name)
            }
            let repetition = node.text(at: ["Repetition", "Calculation"]) ?? "1"
            return supported(name, "Refresh Object [ Object Name: \(objectName) ; Repetition: \(repetition) ]")

        case 121, 123:
            let stepName = id == 121 ? "Close Window" : "Select Window"
            let target = node.child(named: "Window")?.attributes["value"] ?? "Current"
            if target.caseInsensitiveCompare("ByName") == .orderedSame {
                let calculation = node.text(at: ["Name", "Calculation"]) ?? "\"\""
                let currentFile = boolAttribute(node.child(named: "LimitToWindowsOfCurrentFile"), name: "state")
                return supported(name, "\(stepName) [ Name: \(calculation) ; \(currentFile ? "Current file" : "All files") ]")
            }
            return supported(name, "\(stepName) [ Current Window ]")

        case 122:
            guard let styles = node.child(named: "NewWndStyles"),
                  let nameCalculation = node.text(at: ["Name", "Calculation"]),
                  let layoutName = node.child(named: "Layout")?.attributes["name"] else {
                return renderGeneric(node, id: id, name: name)
            }
            let style = styles.attributes["Style"] ?? "Document"
            let toolbars = styles.attributes["Styles"] != "1"
            let options = [
                "Style: \(style)",
                "Name: \(nameCalculation)",
                "Using layout: \(quoteObjectName(layoutName))",
                "Close: \(yesNoAttribute(styles, "Close"))",
                "Minimize: \(yesNoAttribute(styles, "Minimize"))",
                "Maximize: \(yesNoAttribute(styles, "Maximize"))",
                "Resize: \(yesNoAttribute(styles, "Resize"))",
                "Menu Bar: \(yesNoAttribute(styles, "MenuBar"))",
                "Dim parent window: \(yesNoAttribute(styles, "DimParentWindow"))",
                "Toolbars: \(toolbars ? "Yes" : "No")"
            ]
            return supported(name, "New Window [ \(options.joined(separator: " ; ")) ]")

        default:
            return renderGeneric(node, id: id, name: name)
        }
    }

    private func renderGeneric(_ node: ParsedXMLNode, id: Int?, name: String) -> RenderedStep {
        if let stepText = node.child(named: "StepText")?.trimmedText, !stepText.isEmpty {
            return RenderedStep(
                name: name,
                text: "# ▶︎ Unsupported step preserved for AI review\n\(stepText)",
                unsupported: true
            )
        }

        var hints: [String] = []
        if let calculation = node.directText(named: "Calculation"), !calculation.isEmpty {
            hints.append("Calculation: \(calculation)")
        }
        if let field = node.child(named: "Field") {
            let table = field.attributes["table"] ?? "?"
            let fieldName = field.attributes["name"] ?? "?"
            hints.append("Field: \(table)::\(fieldName)")
        }
        if let layout = node.child(named: "Layout")?.attributes["name"] {
            hints.append("Layout: \(layout)")
        }
        if let script = node.child(named: "Script")?.attributes["name"] {
            hints.append("Script: \(script)")
        }

        let idText = id.map(String.init) ?? "unknown"
        var text = "# ▶︎ Unsupported FileMaker step: \(name) (ID \(idText))"
        if !hints.isEmpty {
            text += "\n# Options detected: " + hints.joined(separator: " ; ")
        }
        return RenderedStep(name: name, text: text, unsupported: true)
    }

    private func renderExportRecords(_ node: ParsedXMLNode, id: Int?, name: String) -> RenderedStep {
        let expectedChildren = ["NoInteract", "CreateDirectories", "DisableStepCollapsed", "Restore", "AutoOpen", "CreateEmail", "Profile", "UniversalPathList", "UseFieldNames", "ExportOptions", "ExportEntries"]
        guard node.children.map(\.name) == expectedChildren,
              node.attributes["enable"]?.caseInsensitiveCompare("True") == .orderedSame,
              let profile = node.child(named: "Profile"),
              profile.attributes == ["FieldDelimiter": "\t", "IsPredefined": "-1", "FieldNameRow": "-1", "DataType": "XLXE"],
              let path = node.directText(named: "UniversalPathList"), !path.isEmpty,
              node.child(named: "Restore")?.attributes["state"]?.caseInsensitiveCompare("True") == .orderedSame,
              !boolAttribute(node.child(named: "AutoOpen"), name: "state"),
              !boolAttribute(node.child(named: "CreateEmail"), name: "state"),
              node.child(named: "DisableStepCollapsed")?.attributes["state"]?.caseInsensitiveCompare("False") == .orderedSame,
              let exportOptions = node.child(named: "ExportOptions"),
              exportOptions.attributes == ["FormatUsingCurrentLayout": "False", "CharacterSet": "Unicode"],
              let entries = node.child(named: "ExportEntries"), !entries.children.isEmpty else {
            return renderGeneric(node, id: id, name: name)
        }
        var fields: [String] = []
        for entry in entries.children {
            guard entry.name == "ExportEntry", entry.children.count == 1,
                  let field = entry.child(named: "Field"),
                  let table = field.attributes["table"], let fieldName = field.attributes["name"],
                  field.attributes.keys.sorted() == ["id", "name", "table"] else {
                return renderGeneric(node, id: id, name: name)
            }
            fields.append("\(table)::\(fieldName)")
        }
        let withDialog = boolAttribute(node.child(named: "NoInteract"), name: "state") ? "Off" : "On"
        let createFolders = boolAttribute(node.child(named: "CreateDirectories"), name: "state") ? "On" : "Off"
        let useFieldNames = boolAttribute(node.child(named: "UseFieldNames"), name: "state") ? "On" : "Off"
        return supported(name, "Export Records [ With dialog: \(withDialog) ; Create folders: \(createFolders) ; File: \(quoteObjectName(path)) ; Format: XLSX ; Character set: Unicode ; Use field names: \(useFieldNames) ; Field order: \(fields.joined(separator: ", ")) ]")
    }

    private func renderImportRecords(_ node: ParsedXMLNode, id: Int?, name: String) -> RenderedStep {
        let expectedChildren = ["NoInteract", "DisableStepCollapsed", "Restore", "VerifySSLCertificates", "DataSourceType", "Profile", "UniversalPathList"]
        guard node.children.map(\.name) == expectedChildren,
              node.attributes["enable"]?.caseInsensitiveCompare("True") == .orderedSame,
              node.child(named: "DisableStepCollapsed")?.attributes == ["state": "False"],
              node.child(named: "Restore")?.attributes == ["state": "False"],
              node.child(named: "VerifySSLCertificates")?.attributes == ["state": "False"],
              node.child(named: "DataSourceType")?.attributes == ["value": "File"],
              let profile = node.child(named: "Profile"),
              let path = node.directText(named: "UniversalPathList"), !path.isEmpty,
              profile.attributes == ["FileName": path, "WorksheetName": "", "SelectedSheet": "0", "FieldDelimiter": "\t", "IsPredefined": "-1", "FieldNameRow": "-1", "DataType": "XLSX"] else {
            return renderGeneric(node, id: id, name: name)
        }
        let withDialog = boolAttribute(node.child(named: "NoInteract"), name: "state") ? "Off" : "On"
        return supported(name, "Import Records [ With dialog: \(withDialog) ; File: \(quoteObjectName(path)) ; Format: XLSX ]")
    }

    private func renderSaveRecordsAsExcel(_ node: ParsedXMLNode, id: Int?, name: String) -> RenderedStep {
        let expectedChildren = ["NoInteract", "CreateDirectories", "DisableStepCollapsed", "Restore", "AutoOpen", "CreateEmail", "Profile", "UniversalPathList", "SaveType", "UseFieldNames"]
        guard node.children.map(\.name) == expectedChildren,
              node.attributes["enable"]?.caseInsensitiveCompare("True") == .orderedSame,
              node.child(named: "DisableStepCollapsed")?.attributes == ["state": "False"],
              node.child(named: "Restore")?.attributes == ["state": "False"],
              !boolAttribute(node.child(named: "AutoOpen"), name: "state"),
              !boolAttribute(node.child(named: "CreateEmail"), name: "state"),
              let profile = node.child(named: "Profile"),
              profile.attributes == ["FieldDelimiter": "\t", "IsPredefined": "-1", "FieldNameRow": "-1", "DataType": "XLXE"],
              let path = node.directText(named: "UniversalPathList"), !path.isEmpty,
              let saveType = node.child(named: "SaveType")?.attributes["value"],
              saveType == "BrowsedRecords" || saveType == "CurrentRecord" else {
            return renderGeneric(node, id: id, name: name)
        }
        let withDialog = boolAttribute(node.child(named: "NoInteract"), name: "state") ? "Off" : "On"
        let createFolders = boolAttribute(node.child(named: "CreateDirectories"), name: "state") ? "On" : "Off"
        let recordScope = saveType == "BrowsedRecords" ? "Records being browsed" : "Current record"
        let useFieldNames = boolAttribute(node.child(named: "UseFieldNames"), name: "state") ? "On" : "Off"
        return supported(name, "Save Records as Excel [ With dialog: \(withDialog) ; File: \(quoteObjectName(path)) ; \(recordScope) ; Create folders: \(createFolders) ; Use field names: \(useFieldNames) ]")
    }

    private func renderSendMail(_ node: ParsedXMLNode, id: Int?, name: String) -> RenderedStep {
        let expectedChildren = ["NoInteract", "DisableStepCollapsed", "Attachment", "MultipleEmails", "SendViaSMTP", "SendViaOAuthAuthentication", "SMTPEncryptionType", "SMTPAuthenticationType", "OAuthProvider"]
        guard node.children.map(\.name) == expectedChildren,
              node.attributes["enable"]?.caseInsensitiveCompare("True") == .orderedSame,
              let attachment = node.child(named: "Attachment"), attachment.children.map(\.name) == ["UniversalPathList"],
              let path = attachment.directText(named: "UniversalPathList"), !path.isEmpty,
              node.child(named: "DisableStepCollapsed")?.attributes["state"]?.caseInsensitiveCompare("False") == .orderedSame,
              !boolAttribute(node.child(named: "MultipleEmails"), name: "state"),
              !boolAttribute(node.child(named: "SendViaSMTP"), name: "state"),
              !boolAttribute(node.child(named: "SendViaOAuthAuthentication"), name: "state"),
              node.child(named: "SMTPEncryptionType")?.attributes == ["type": "SMTPEncryptionNone"],
              node.child(named: "SMTPAuthenticationType")?.attributes == ["type": "SMTPAuthenticationNone"],
              node.child(named: "OAuthProvider")?.attributes == ["type": "OAuthProviderGoogle"] else {
            return renderGeneric(node, id: id, name: name)
        }
        let withDialog = boolAttribute(node.child(named: "NoInteract"), name: "state") ? "Off" : "On"
        return supported(name, "Send Mail [ Send via: E-Mail Client ; With dialog: \(withDialog) ; Attachment: \(quoteObjectName(path)) ]")
    }

    private func supported(_ name: String, _ text: String) -> RenderedStep {
        RenderedStep(name: name, text: text, unsupported: false)
    }

    private func renderSortRecords(_ node: ParsedXMLNode, id: Int?, name: String) -> RenderedStep {
        guard node.children.map(\.name) == ["NoInteract", "DisableStepCollapsed", "Restore", "SortList"],
              node.child(named: "Restore")?.attributes["state"]?.caseInsensitiveCompare("True") == .orderedSame,
              let sortList = node.child(named: "SortList"),
              sortList.attributes.count == 3,
              sortList.attributes["value"]?.caseInsensitiveCompare("True") == .orderedSame,
              let blanksLast = sortList.attributes["BlanksLast"],
              let maintain = sortList.attributes["Maintain"],
              let blanksLastValue = onOffText(blanksLast),
              let maintainValue = onOffText(maintain),
              !sortList.children.isEmpty else {
            return renderGeneric(node, id: id, name: name)
        }

        var criteria: [String] = []
        for sort in sortList.children {
            guard sort.name == "Sort", sort.attributes.count == 1,
                  let order = SortOrder(rawValue: sort.attributes["type"] ?? ""),
                  sort.children.count == 1, let primaryField = sort.child(named: "PrimaryField"),
                  primaryField.children.count == 1, let field = primaryField.child(named: "Field"),
                  field.children.isEmpty, field.attributes.count == 3,
                  let table = field.attributes["table"], let fieldName = field.attributes["name"],
                  field.attributes["id"] != nil else {
                return renderGeneric(node, id: id, name: name)
            }
            criteria.append("\(table)::\(fieldName) \(order.rawValue)")
        }
        let withDialog = boolAttribute(node.child(named: "NoInteract"), name: "state") ? "Off" : "On"
        return supported(name, "Sort Records [ With dialog: \(withDialog) ; Blanks last: \(blanksLastValue) ; Keep records sorted: \(maintainValue) ; \(criteria.joined(separator: " ; ")) ]")
    }

    private func onOffText(_ raw: String) -> String? {
        if raw.caseInsensitiveCompare("True") == .orderedSame { return "On" }
        if raw.caseInsensitiveCompare("False") == .orderedSame { return "Off" }
        return nil
    }

    private func matchesCapturedDefault(_ node: ParsedXMLNode, name: String) -> Bool {
        let compiled = FileMakerXMLCompiler().compile(
            name,
            options: CompilationOptions(convertUnsupportedLinesToComments: false)
        )
        guard compiled.errorCount == 0,
              let data = compiled.xml.data(using: .utf8) else {
            return false
        }
        let builder = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse(),
              let expected = builder.roots.flatMap({ $0.descendants(named: "Step") }).first else {
            return false
        }
        return node.children.map { $0.serializedXML() } == expected.children.map { $0.serializedXML() }
    }

    private func boolAttribute(_ node: ParsedXMLNode?, name: String) -> Bool {
        node?.attributes[name]?.caseInsensitiveCompare("True") == .orderedSame
    }

    private func yesNoAttribute(_ node: ParsedXMLNode, _ name: String) -> String {
        node.attributes[name]?.caseInsensitiveCompare("Yes") == .orderedSame ? "Yes" : "No"
    }

    private func canonicalName(for id: Int?) -> String? {
        switch id {
        case 7: return "New Record/Request"
        case 8: return "Duplicate Record/Request"
        case 21: return "Unsort Records"
        case 23: return "Show All Records"
        case 24: return "Modify Last Find"
        case 25: return "Omit Record"
        case 26: return "Omit Multiple Records"
        case 27: return "Show Omitted Only"
        case 29: return "Show/Hide Toolbars"
        case 30: return "View As"
        case 31: return "Adjust Window"
        case 32: return "Open Help"
        case 35: return "Import Records"
        case 36: return "Export Records"
        case 38: return "Open Manage Database"
        case 39: return "Sort Records"
        case 44: return "Exit Application"
        case 79: return "Freeze Window"
        case 80: return "Refresh Window"
        case 81: return "Scroll Window"
        case 85: return "Allow User Abort"
        case 86: return "Set Error Capture"
        case 88: return "Open Script Workspace"
        case 90: return "Halt Script"
        case 92: return "Show/Hide Text Ruler"
        case 93: return "Beep"
        case 94: return "Set Use System Formats"
        case 97: return "Set Zoom Level"
        case 98: return "Copy All Records/Requests"
        case 101: return "Copy Record/Request"
        case 102: return "Flush Cache to Disk"
        case 104: return "Delete Portal Row"
        case 105: return "Open Settings"
        case 112: return "Open Manage Value Lists"
        case 113: return "Open Sharing"
        case 114: return "Open File Options"
        case 115: return "Allow Formatting Bar"
        case 118: return "Open Hosts"
        case 119: return "Move/Resize Window"
        case 120: return "Arrange All Windows"
        case 124: return "Set Window Title"
        case 126: return "Constrain Found Set"
        case 127: return "Extend Found Set"
        case 129: return "Open Find/Replace"
        case 133: return "Open Record/Request"
        case 140: return "Open Manage Data Sources"
        case 143: return "Save Records as Excel"
        case 149: return "Open Edit Saved Finds"
        case 150: return "Perform Quick Find"
        case 151: return "Open Manage Layouts"
        case 152: return "Save Records as Snapshot Link"
        case 154: return "Sort Records by Field"
        case 155: return "Find Matching Records"
        case 156: return "Open Manage Containers"
        case 165: return "Open Manage Themes"
        case 166: return "Show/Hide Menubar"
        case 172: return "Open Upload to Host"
        case 174: return "Enable Touch Keyboard"
        case 182: return "Truncate Table"
        case 183: return "Open Favorites"
        case 225: return "Save Records as JSONL"
        case 237: return "Flush Web Viewer Cookies"
        default: return nil
        }
    }

    private func shouldOutdentBefore(id: Int?) -> Bool {
        [69, 70, 73, 125].contains(id)
    }

    private func shouldIndentAfter(id: Int?) -> Bool {
        [68, 69, 71, 125].contains(id)
    }

    private func quoteObjectName(_ name: String) -> String {
        "\"\(name.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func failure(_ xml: String, _ message: String) -> DecompilationResult {
        DecompilationResult(
            sourceXML: xml,
            text: "",
            stepCount: 0,
            unsupportedStepCount: 0,
            scriptNames: [],
            warnings: [message],
            preservedSteps: [:]
        )
    }
}

private struct RenderedStep {
    let name: String
    let text: String
    let unsupported: Bool
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    var roots: [ParsedXMLNode] = []
    var parseError: Error?
    private var stack: [ParsedXMLNode] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = ParsedXMLNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            roots.append(node)
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        stack.last?.text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        _ = stack.popLast()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

private final class ParsedXMLNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [ParsedXMLNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func child(named target: String) -> ParsedXMLNode? {
        children.first { $0.name == target }
    }

    func directText(named target: String) -> String? {
        child(named: target)?.trimmedText
    }

    func text(at path: [String]) -> String? {
        var node: ParsedXMLNode? = self
        for component in path {
            node = node?.child(named: component)
        }
        return node?.trimmedText
    }

    func descendants(named target: String) -> [ParsedXMLNode] {
        var result: [ParsedXMLNode] = []
        if name == target {
            result.append(self)
        }
        for child in children {
            result.append(contentsOf: child.descendants(named: target))
        }
        return result
    }

    func serializedXML(indentation: String = "") -> String {
        let attributesText = attributes
            .sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\(escapeAttribute($0.value))\"" }
            .joined()

        if children.isEmpty {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                return "\(indentation)<\(name)\(attributesText)></\(name)>"
            }
            return "\(indentation)<\(name)\(attributesText)>\(escapeText(value))</\(name)>"
        }

        let childIndentation = indentation + "  "
        let body = children
            .map { $0.serializedXML(indentation: childIndentation) }
            .joined(separator: "\n")
        return "\(indentation)<\(name)\(attributesText)>\n\(body)\n\(indentation)</\(name)>"
    }

    private func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
