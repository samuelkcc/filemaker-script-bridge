import Foundation

public struct FileMakerTextParser: Sendable {
    public init() {}

    public func parse(
        _ source: String,
        options: CompilationOptions = CompilationOptions(),
        preservedSteps: [String: PreservedFileMakerStep] = [:]
    ) -> (logicalLines: [LogicalLine], steps: [CompiledStep], issues: [CompilationIssue]) {
        let logicalLines = TextUtilities.normalizeLogicalLines(source)
        var steps: [CompiledStep] = []
        var issues: [CompilationIssue] = []
        var structures: [(kind: StructureKind, line: LogicalLine)] = []

        for logicalLine in logicalLines {
            let line = logicalLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            switch parseLine(line, preservedSteps: preservedSteps) {
            case .step(let step):
                validateStructure(
                    step,
                    line: logicalLine,
                    structures: &structures,
                    issues: &issues
                )
                steps.append(step)

            case .malformed(let message):
                appendFallback(
                    logicalLine,
                    reason: message,
                    options: options,
                    steps: &steps,
                    issues: &issues
                )

            case .blocking(let message):
                issues.append(CompilationIssue(
                    severity: .error,
                    line: logicalLine.lineNumber,
                    message: message,
                    source: logicalLine.text
                ))

            case .unsupported(let officialStepName):
                let reference = officialStepName.flatMap { name in
                    FileMakerScriptStepCatalog.entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                }
                let unsupportedReason: String
                if reference?.name == "Export Records" {
                    unsupportedReason = "Export Records cannot be sent yet: the output path, file format, character set, automatic-open setting, and field order must be captured as a native FileMaker XML shape before this exact export can be generated safely"
                } else if reference?.name == "Import Records" {
                    unsupportedReason = "Import Records requires the native-captured File/XLSX profile with an empty worksheet and no import order; worksheet selection, field mapping, and other source profiles remain preserve-only"
                } else if reference?.support == .editableSubset {
                    unsupportedReason = "The bridge supports an editable subset of ‘\(reference!.name)’, but this option syntax is not mapped safely yet"
                } else if let officialStepName {
                    unsupportedReason = "Official FileMaker step ‘\(officialStepName)’ is preserve-only in this bridge version. Copy the original step from FileMaker to retain its options; AI-authored text cannot be rebuilt safely"
                } else {
                    unsupportedReason = "Unrecognized script step"
                }
                appendFallback(
                    logicalLine,
                    reason: unsupportedReason,
                    options: options,
                    steps: &steps,
                    issues: &issues
                )
            }
        }

        for structure in structures.reversed() {
            let expected = structure.kind == .ifBlock ? "End If" : "End Loop"
            issues.append(CompilationIssue(
                severity: .error,
                line: structure.line.lineNumber,
                message: "Missing \(expected) for this block",
                source: structure.line.text
            ))
        }

        return (logicalLines, steps, issues)
    }

    private func parseLine(
        _ line: String,
        preservedSteps: [String: PreservedFileMakerStep]
    ) -> LineParseResult {
        if line.hasPrefix("# ↔ FileMaker step preserved unchanged:")
            || line.hasPrefix("# ▶︎ Preserved FileMaker step:") {
            guard let token = preservationToken(in: line),
                  let preserved = preservedSteps[token] else {
                return .blocking("This preserved FileMaker step is no longer available. Re-copy and read the original script from FileMaker before exporting.")
            }
            return .step(.preservedXML(
                token: token,
                name: preserved.name,
                xml: preserved.xml
            ))
        }

        if line.hasPrefix("#") {
            return .step(.comment(
                text: String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines),
                isFallback: false
            ))
        }
        if let result = parseDataAndURLStep(line) { return result }

        if line.hasPrefix("//") {
            return .step(.comment(
                text: String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines),
                isFallback: false
            ))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Comment", in: line) {
            return .step(.comment(text: TextUtilities.unquote(body), isFallback: false))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Set Variable", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let rawName = components.first else {
                return .malformed("Set Variable requires a variable name and Value")
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.hasPrefix("$") else {
                return .malformed("Set Variable name must begin with $ or $$")
            }
            guard let valuePart = components.dropFirst().first(where: {
                TextUtilities.value(afterLabel: "Value:", in: $0) != nil
            }), let value = TextUtilities.value(afterLabel: "Value:", in: valuePart), !value.isEmpty else {
                return .malformed("Set Variable requires Value: calculation")
            }
            let repetition = components.dropFirst().compactMap {
                TextUtilities.value(afterLabel: "Repetition:", in: $0)
            }.first
            return .step(.setVariable(name: name, value: value, repetition: repetition))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Set Field By Name", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard components.count >= 2 else {
                return .malformed("Set Field By Name requires target and result calculations")
            }
            let target = TextUtilities.value(afterLabel: "Target:", in: components[0]) ?? components[0]
            let result = TextUtilities.value(afterLabel: "Result:", in: components[1]) ?? components[1]
            guard !target.isEmpty, !result.isEmpty else {
                return .malformed("Set Field By Name target and result cannot be empty")
            }
            return .step(.setFieldByName(target: target, value: result))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Set Field", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard components.count >= 2 else {
                return .malformed("Set Field requires Table::Field and a calculation")
            }
            guard let reference = TextUtilities.splitFieldReference(components[0]) else {
                return .malformed("Set Field target must use Table::Field notation")
            }
            let value = TextUtilities.value(afterLabel: "Value:", in: components[1]) ?? components[1]
            guard !value.isEmpty else {
                return .malformed("Set Field calculation cannot be empty")
            }
            return .step(.setField(table: reference.table, field: reference.field, value: value))
        }

        if let calculation = TextUtilities.bracketBody(forPrefix: "Else If", in: line) {
            guard !calculation.isEmpty else { return .malformed("Else If requires a calculation") }
            return .step(.elseIf(calculation: calculation))
        }
        if let calculation = TextUtilities.bracketBody(forPrefix: "If", in: line) {
            guard !calculation.isEmpty else { return .malformed("If requires a calculation") }
            return .step(.ifStep(calculation: calculation))
        }
        if isExact(line, "Else") || TextUtilities.bracketBody(forPrefix: "Else", in: line)?.isEmpty == true {
            return .step(.elseStep)
        }
        if isExact(line, "End If") { return .step(.endIf) }
        if isExact(line, "Loop") { return .step(.loop(flush: .always)) }
        if let body = TextUtilities.bracketBody(forPrefix: "Loop", in: line),
           let rawFlush = TextUtilities.value(afterLabel: "Flush:", in: body),
           let flush = LoopFlushMode.allCases.first(where: {
               $0.rawValue.caseInsensitiveCompare(rawFlush) == .orderedSame
           }) {
            return .step(.loop(flush: flush))
        }
        if let calculation = TextUtilities.bracketBody(forPrefix: "Exit Loop If", in: line) {
            guard !calculation.isEmpty else { return .malformed("Exit Loop If requires a calculation") }
            return .step(.exitLoopIf(calculation: calculation))
        }
        if isExact(line, "End Loop") { return .step(.endLoop) }

        if let body = TextUtilities.bracketBody(forPrefix: "Perform Script", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let first = components.first else {
                return .malformed("Perform Script requires a script name")
            }
            let rawName = TextUtilities.value(afterLabel: "Script:", in: first) ?? first
            let name = TextUtilities.unquote(rawName)
            guard !name.isEmpty else { return .malformed("Perform Script name cannot be empty") }
            let parameter = components.dropFirst().compactMap {
                TextUtilities.value(afterLabel: "Parameter:", in: $0)
                    ?? TextUtilities.value(afterLabel: "Script Parameter:", in: $0)
            }.first
            return .step(.performScript(name: name, parameter: parameter))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Perform Script on Server", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let first = components.first else {
                return .malformed("Perform Script on Server requires a script name")
            }
            let rawName = TextUtilities.value(afterLabel: "Script:", in: first) ?? first
            let name = TextUtilities.unquote(rawName)
            guard !name.isEmpty else { return .malformed("Perform Script on Server name cannot be empty") }
            let parameter = components.dropFirst().compactMap {
                TextUtilities.value(afterLabel: "Parameter:", in: $0)
                    ?? TextUtilities.value(afterLabel: "Script Parameter:", in: $0)
            }.first
            let waitValue = components.dropFirst().compactMap {
                TextUtilities.value(afterLabel: "Wait for completion:", in: $0)
            }.first ?? "On"
            guard let wait = parseOnOff(waitValue) else {
                return .malformed("Perform Script on Server Wait for completion requires On or Off")
            }
            return .step(.performScriptOnServer(name: name, parameter: parameter, waitForCompletion: wait))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Export Field Contents", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let first = components.first,
                  let reference = TextUtilities.splitFieldReference(first) else {
                return .malformed("Export Field Contents requires Table::Field")
            }
            guard components.count >= 2 else {
                return .malformed("Export Field Contents requires an output path")
            }
            let path = TextUtilities.unquote(components[1])
            guard !path.isEmpty else { return .malformed("Export Field Contents path cannot be empty") }
            let createValue = components.dropFirst(2).compactMap {
                TextUtilities.value(afterLabel: "Create folders:", in: $0)
            }.first ?? "Yes"
            guard let createDirectories = parseYesNo(createValue) else {
                return .malformed("Export Field Contents Create folders requires Yes or No")
            }
            return .step(.exportFieldContents(
                table: reference.table,
                field: reference.field,
                path: path,
                createDirectories: createDirectories
            ))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Export Records", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            let values = Dictionary(uniqueKeysWithValues: components.compactMap { component -> (String, String)? in
                for label in ["With dialog:", "Create folders:", "File:", "Format:", "Character set:", "Use field names:", "Field order:"] {
                    if let value = TextUtilities.value(afterLabel: label, in: component) {
                        return (label, value)
                    }
                }
                return nil
            })
            guard let dialogRaw = values["With dialog:"], let withDialog = parseOnOff(dialogRaw),
                  let foldersRaw = values["Create folders:"], let createDirectories = parseOnOff(foldersRaw),
                  let rawPath = values["File:"],
                  let format = values["Format:"], format.caseInsensitiveCompare("XLSX") == .orderedSame,
                  let characterSet = values["Character set:"], characterSet.caseInsensitiveCompare("Unicode") == .orderedSame,
                  let fieldNamesRaw = values["Use field names:"], let useFieldNames = parseOnOff(fieldNamesRaw),
                  let fieldOrder = values["Field order:"] else {
                return .malformed("Export Records requires its native-captured output path, Format: XLSX, Character set: Unicode, automatic-open-off profile, and field order; unsupported options remain preserve-only")
            }
            let path = TextUtilities.unquote(rawPath)
            guard !path.isEmpty else { return .malformed("Export Records File cannot be empty") }
            let fields = fieldOrder.split(separator: ",").compactMap { TextUtilities.splitFieldReference($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard fields.count == fieldOrder.split(separator: ",").count, !fields.isEmpty else {
                return .malformed("Export Records Field order requires one or more Table::Field values separated by commas")
            }
            return .step(.exportRecords(options: ExportRecordsOptions(
                withDialog: withDialog,
                createDirectories: createDirectories,
                path: path,
                characterSet: "Unicode",
                useFieldNames: useFieldNames,
                fields: fields.map { ExportRecordField(table: $0.table, field: $0.field) }
            )))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Save Records as Excel", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            let values = Dictionary(uniqueKeysWithValues: components.compactMap { component -> (String, String)? in
                for label in ["With dialog:", "File:", "Create folders:", "Use field names:"] {
                    if let value = TextUtilities.value(afterLabel: label, in: component) { return (label, value) }
                }
                return nil
            })
            guard let dialogRaw = values["With dialog:"], let withDialog = parseOnOff(dialogRaw),
                  let rawPath = values["File:"], !TextUtilities.unquote(rawPath).isEmpty,
                  let foldersRaw = values["Create folders:"], let createDirectories = parseOnOff(foldersRaw),
                  let fieldsRaw = values["Use field names:"], let useFieldNames = parseOnOff(fieldsRaw) else {
                return .malformed("Save Records as Excel requires With dialog, File, a record scope, Create folders, and Use field names")
            }
            let scopes = components.filter { $0.caseInsensitiveCompare("Records being browsed") == .orderedSame || $0.caseInsensitiveCompare("Current record") == .orderedSame }
            guard components.count == 5, scopes.count == 1, values.count == 4 else {
                return .malformed("Save Records as Excel requires exactly one scope: Records being browsed or Current record")
            }
            return .step(.saveRecordsAsExcel(options: SaveRecordsAsExcelOptions(
                withDialog: withDialog,
                createDirectories: createDirectories,
                path: TextUtilities.unquote(rawPath),
                saveType: scopes[0].caseInsensitiveCompare("Current record") == .orderedSame ? "CurrentRecord" : "BrowsedRecords",
                useFieldNames: useFieldNames
            )))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Import Records", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            let values = Dictionary(uniqueKeysWithValues: components.compactMap { component -> (String, String)? in
                for label in ["With dialog:", "File:", "Format:"] {
                    if let value = TextUtilities.value(afterLabel: label, in: component) {
                        return (label, value)
                    }
                }
                return nil
            })
            guard let dialogRaw = values["With dialog:"], let withDialog = parseOnOff(dialogRaw),
                  let rawPath = values["File:"],
                  let format = values["Format:"], format.caseInsensitiveCompare("XLSX") == .orderedSame else {
                return .malformed("Import Records requires its native-captured With dialog, File, and Format: XLSX profile; worksheet selection, import order, and other source profiles remain preserve-only")
            }
            let path = TextUtilities.unquote(rawPath)
            guard !path.isEmpty else { return .malformed("Import Records File cannot be empty") }
            return .step(.importRecords(options: ImportRecordsOptions(withDialog: withDialog, path: path)))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Send Mail", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let via = components.compactMap({ TextUtilities.value(afterLabel: "Send via:", in: $0) }).first,
                  via.caseInsensitiveCompare("E-Mail Client") == .orderedSame,
                  let dialogRaw = components.compactMap({ TextUtilities.value(afterLabel: "With dialog:", in: $0) }).first,
                  let withDialog = parseOnOff(dialogRaw),
                  let rawAttachment = components.compactMap({ TextUtilities.value(afterLabel: "Attachment:", in: $0) }).first else {
                return .malformed("Send Mail requires Send via: E-Mail Client, With dialog, and Attachment")
            }
            let attachmentPath = TextUtilities.unquote(rawAttachment)
            guard !attachmentPath.isEmpty else { return .malformed("Send Mail Attachment cannot be empty") }
            return .step(.sendMail(options: SendMailOptions(withDialog: withDialog, attachmentPath: attachmentPath)))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Insert File", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let targetPart = components.first,
                  let rawTarget = TextUtilities.value(afterLabel: "Target:", in: targetPart),
                  let reference = TextUtilities.splitFieldReference(rawTarget) else {
                return .malformed("Insert File requires Target: Table::Field")
            }
            guard components.count >= 2 else { return .malformed("Insert File requires a source path") }
            let path = TextUtilities.unquote(components[1])
            guard !path.isEmpty else { return .malformed("Insert File path cannot be empty") }
            return .step(.insertFile(table: reference.table, field: reference.field, path: path))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Refresh Object", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let objectName = components.compactMap({
                TextUtilities.value(afterLabel: "Object Name:", in: $0)
            }).first, !objectName.isEmpty else {
                return .malformed("Refresh Object requires Object Name: calculation")
            }
            let repetition = components.compactMap {
                TextUtilities.value(afterLabel: "Repetition:", in: $0)
            }.first ?? "1"
            guard !repetition.isEmpty else { return .malformed("Refresh Object repetition cannot be empty") }
            return .step(.refreshObject(objectName: objectName, repetition: repetition))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Go to Layout", in: line) {
            let rawName = TextUtilities.value(afterLabel: "Layout:", in: body) ?? body
            let name = TextUtilities.objectName(from: rawName)
            guard !name.isEmpty else { return .malformed("Go to Layout requires a layout name") }
            return .step(.goToLayout(name: name))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Go to Record/Request/Page", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let rawDestination = components.first, !rawDestination.isEmpty else {
                return .malformed("Go to Record/Request/Page requires First, Last, Previous, Next, or By calculation")
            }

            let destination: RecordPageDestination
            switch rawDestination.lowercased() {
            case "first": destination = .first
            case "last": destination = .last
            case "previous": destination = .previous
            case "next": destination = .next
            default:
                let calculation = TextUtilities.value(afterLabel: "By calculation:", in: rawDestination) ?? rawDestination
                guard !calculation.isEmpty else {
                    return .malformed("Go to Record/Request/Page By calculation requires a calculation")
                }
                destination = .byCalculation(calculation)
            }

            var exitAfterLast = false
            for option in components.dropFirst() {
                if option.caseInsensitiveCompare("Exit after last") == .orderedSame {
                    exitAfterLast = true
                } else if option.caseInsensitiveCompare("No dialog") == .orderedSame,
                          case .byCalculation = destination {
                    continue
                } else if !option.isEmpty {
                    return .malformed("Unsupported Go to Record/Request/Page option: \(option)")
                }
            }
            if exitAfterLast, destination != .next, destination != .previous {
                return .malformed("Exit after last is only valid with Next or Previous")
            }
            return .step(.goToRecord(
                destination: destination,
                exitAfterLast: exitAfterLast
            ))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Show Custom Dialog", in: line) {
            let components = DialogSyntax.components(body)
            let allowedLabels = ["Title:", "Message:", "Default Button:", "Button 2:", "Button 3:", "Commit:"]
            guard components.allSatisfy({ component in
                allowedLabels.contains { TextUtilities.value(afterLabel: $0, in: component) != nil }
            }) else {
                return .malformed("Show Custom Dialog has unsupported options; input fields must be configured in FileMaker")
            }
            for label in allowedLabels where label != "Commit:" {
                guard components.filter({ TextUtilities.value(afterLabel: label, in: $0) != nil }).count <= 1 else {
                    return .malformed("Show Custom Dialog has duplicate \(label) options")
                }
            }
            let title = components.compactMap { TextUtilities.value(afterLabel: "Title:", in: $0) }.first
            let message = components.compactMap { TextUtilities.value(afterLabel: "Message:", in: $0) }.first
            guard let message, !message.isEmpty else {
                return .malformed("Show Custom Dialog requires Message: calculation")
            }
            var buttons: [DialogButton] = []
            for (index, component) in components.enumerated() {
                let buttonParts = TextUtilities.topLevelComponents(in: component, separator: ",")
                guard let labelPart = buttonParts.first else { continue }
                let labels = ["Default Button:", "Button 2:", "Button 3:"]
                guard let label = labels.first(where: {
                    TextUtilities.value(afterLabel: $0, in: labelPart) != nil
                }) else { continue }
                guard label == labels[min(buttons.count, 2)], buttons.count < 3,
                      let calculation = TextUtilities.value(afterLabel: label, in: labelPart), !calculation.isEmpty else {
                    return .malformed("Show Custom Dialog requires nonempty buttons in order: Default Button, Button 2, Button 3")
                }
                guard buttonParts.dropFirst().allSatisfy({ TextUtilities.value(afterLabel: "Commit:", in: $0) != nil }) else {
                    return .malformed("Show Custom Dialog has unsupported button options")
                }
                let inlineCommitValue = buttonParts.dropFirst().compactMap {
                    TextUtilities.value(afterLabel: "Commit:", in: $0)
                }.first
                let followingCommitValue = components.dropFirst(index + 1).prefix { candidate in
                    !["Default Button:", "Button 2:", "Button 3:"].contains { label in
                        TextUtilities.value(afterLabel: label, in: candidate) != nil
                    }
                }.compactMap {
                    TextUtilities.value(afterLabel: "Commit:", in: $0)
                }.first
                let commitValue = inlineCommitValue ?? followingCommitValue
                // Labels may be arbitrary calculations or any language. Never infer
                // data-writing intent from words such as OK, Cancel, or Continue.
                // Message-only dialogs need no commit setting to operate.
                let commitsRecord: Bool
                if let commitValue {
                    guard let explicitCommit = parseYesNo(commitValue) else {
                        return .malformed("Show Custom Dialog Commit must be Yes or No when specified")
                    }
                    commitsRecord = explicitCommit
                } else {
                    commitsRecord = false
                }
                buttons.append(DialogButton(
                    calculation: normalizeSmartQuotedCalculation(calculation),
                    commitsRecord: commitsRecord
                ))
            }
            if buttons.isEmpty {
                buttons = [DialogButton(calculation: "\"OK\"", commitsRecord: true)]
            }
            return .step(.showCustomDialog(title: title, message: message, buttons: buttons))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "New Window", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            func option(_ label: String) -> String? {
                components.compactMap { TextUtilities.value(afterLabel: label, in: $0) }.first
            }
            guard let style = option("Style:"), ["document", "floating", "dialog", "card"].contains(style.lowercased()) else {
                return .malformed("New Window requires Style: Document, Floating, Dialog, or Card")
            }
            guard let name = option("Name:"), !name.isEmpty else {
                return .malformed("New Window requires Name: calculation")
            }
            guard let rawLayout = option("Using layout:"), !rawLayout.isEmpty else {
                return .malformed("New Window requires Using layout: name")
            }
            let boolOptions: [(String, Bool)] = [
                ("Close:", true), ("Minimize:", true), ("Maximize:", true),
                ("Resize:", true), ("Menu Bar:", true), ("Dim parent window:", false),
                ("Toolbars:", true)
            ]
            var parsed: [String: Bool] = [:]
            for (label, defaultValue) in boolOptions {
                if let raw = option(label) {
                    guard let value = parseYesNo(raw) else {
                        return .malformed("New Window \(label) requires Yes or No")
                    }
                    parsed[label] = value
                } else {
                    parsed[label] = defaultValue
                }
            }
            return .step(.newWindow(options: NewWindowOptions(
                style: style.prefix(1).uppercased() + style.dropFirst().lowercased(),
                nameCalculation: name,
                layoutName: TextUtilities.objectName(from: rawLayout),
                close: parsed["Close:"]!,
                minimize: parsed["Minimize:"]!,
                maximize: parsed["Maximize:"]!,
                resize: parsed["Resize:"]!,
                menuBar: parsed["Menu Bar:"]!,
                dimParentWindow: parsed["Dim parent window:"]!,
                toolbars: parsed["Toolbars:"]!
            )))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Select Window", in: line) {
            return parseWindowTarget(body).map { .step(.selectWindow(target: $0)) }
                ?? .malformed("Select Window requires Current Window or Name: calculation")
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Close Window", in: line) {
            return parseWindowTarget(body).map { .step(.closeWindow(target: $0)) }
                ?? .malformed("Close Window requires Current Window or Name: calculation")
        }

        for (name, id) in [("Delete Record/Request", 9), ("Delete All Records", 10), ("Revert Record/Request", 51)] {
            if let body = TextUtilities.bracketBody(forPrefix: name, in: line) {
                let noInteract: Bool?
                if body.isEmpty {
                    noInteract = false
                } else if body.caseInsensitiveCompare("No dialog") == .orderedSame {
                    noInteract = true
                } else if let dialog = TextUtilities.value(afterLabel: "With dialog:", in: body),
                          let enabled = parseOnOff(dialog) {
                    noInteract = !enabled
                } else {
                    noInteract = nil
                }
                guard let noInteract else { return .malformed("\(name) requires No dialog or With dialog: On/Off") }
                return .step(.recordDialogStep(id: id, name: name, noInteract: noInteract))
            }
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Enter Find Mode", in: line) {
            if body.isEmpty { return .step(.enterFindMode(pause: false)) }
            guard let rawPause = TextUtilities.value(afterLabel: "Pause:", in: body),
                  let pause = parseOnOff(rawPause) else {
                return .malformed("Enter Find Mode Pause requires On or Off")
            }
            return .step(.enterFindMode(pause: pause))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Perform Find", in: line), body.isEmpty {
            return .step(.performFind(restore: false))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Exit Script", in: line) {
            let result = TextUtilities.value(afterLabel: "Text Result:", in: body)
                ?? TextUtilities.value(afterLabel: "Result:", in: body)
                ?? (body.isEmpty ? nil : body)
            return .step(.exitScript(result: result))
        }
        if isExact(line, "Exit Script") { return .step(.exitScript(result: nil)) }

        if let body = TextUtilities.bracketBody(forPrefix: "Allow User Abort", in: line),
           let enabled = parseOnOff(body) {
            return .step(.toggle(id: 85, name: "Allow User Abort", enabled: enabled))
        }
        if let body = TextUtilities.bracketBody(forPrefix: "Set Error Capture", in: line),
           let enabled = parseOnOff(body) {
            return .step(.toggle(id: 86, name: "Set Error Capture", enabled: enabled))
        }
        for (name, id) in [
            ("Allow Formatting Bar", 115),
            ("Enable Touch Keyboard", 174),
            ("Set Use System Formats", 94)
        ] {
            if let body = TextUtilities.bracketBody(forPrefix: name, in: line),
               let enabled = parseOnOff(body) {
                return .step(.toggle(id: id, name: name, enabled: enabled))
            }
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Adjust Window", in: line) {
            let modes: [String: String] = [
                "resize to fit": "ResizeToFit",
                "maximize": "Maximize",
                "minimize": "Minimize",
                "restore": "Restore",
                "hide": "Hide"
            ]
            let key = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let value = modes[key] else {
                return .malformed("Adjust Window expects Resize to Fit, Maximize, Minimize, Restore, or Hide")
            }
            return .step(.enumOption(id: 31, name: "Adjust Window", element: "WindowState", value: value))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Arrange All Windows", in: line) {
            let modes: [String: String] = [
                "tile horizontally": "TileHorizontally",
                "tile vertically": "TileVertically",
                "cascade": "Cascade",
                "cascade window": "Cascade",
                "bring all to front": "BringAllToFront"
            ]
            let key = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let value = modes[key] else {
                return .malformed("Arrange All Windows expects Tile Horizontally, Tile Vertically, Cascade, or Bring All to Front")
            }
            return .step(.enumOption(id: 120, name: "Arrange All Windows", element: "WindowArrangement", value: value))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "View As", in: line) {
            let modes: [String: String] = [
                "form": "Form", "view as form": "Form",
                "list": "List", "view as list": "List",
                "table": "Table", "view as table": "Table",
                "cycle": "Cycle"
            ]
            let key = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let value = modes[key] else {
                return .malformed("View As expects Form, List, Table, or Cycle")
            }
            return .step(.enumOption(id: 30, name: "View As", element: "View", value: value))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Scroll Window", in: line) {
            let modes: [String: String] = [
                "home": "Home", "end": "End", "page up": "PageUp",
                "page down": "PageDown", "to selection": "ToSelection"
            ]
            let key = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let value = modes[key] else {
                return .malformed("Scroll Window expects Home, End, Page Up, Page Down, or To Selection")
            }
            return .step(.enumOption(id: 81, name: "Scroll Window", element: "ScrollOperation", value: value))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Show/Hide Text Ruler", in: line) {
            let modes: [String: String] = ["show": "Show", "hide": "Hide", "toggle": "Toggle"]
            let key = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let value = modes[key] else {
                return .malformed("Show/Hide Text Ruler expects Show, Hide, or Toggle")
            }
            return .step(.enumOption(id: 92, name: "Show/Hide Text Ruler", element: "ShowHide", value: value))
        }

        for (name, id, hasToolbarOption) in [
            ("Show/Hide Menubar", 166, false),
            ("Show/Hide Toolbars", 29, true)
        ] {
            if let body = TextUtilities.bracketBody(forPrefix: name, in: line) {
                let components = TextUtilities.topLevelComponents(in: body)
                guard let action = components.first?.trimmingCharacters(in: .whitespacesAndNewlines).capitalized,
                      ["Show", "Hide", "Toggle"].contains(action) else {
                    return .malformed("\(name) expects Show, Hide, or Toggle")
                }
                let lockRaw = components.dropFirst().compactMap { TextUtilities.value(afterLabel: "Lock:", in: $0) }.first ?? "Off"
                guard let lock = parseOnOff(lockRaw) else {
                    return .malformed("\(name) Lock requires On or Off")
                }
                var include: Bool? = nil
                if hasToolbarOption {
                    let includeRaw = components.dropFirst().compactMap {
                        TextUtilities.value(afterLabel: "Include Edit Record Toolbar:", in: $0)
                    }.first ?? "On"
                    guard let parsedInclude = parseOnOff(includeRaw) else {
                        return .malformed("Show/Hide Toolbars Include Edit Record Toolbar requires On or Off")
                    }
                    include = parsedInclude
                }
                return .step(.showHide(id: id, name: name, value: action, lock: lock, includeEditRecordToolbar: include))
            }
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Set Zoom Level", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let first = components.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else {
                return .malformed("Set Zoom Level requires a percentage, Zoom In, Zoom Out, or Custom calculation")
            }
            let lockRaw = components.dropFirst().compactMap { TextUtilities.value(afterLabel: "Lock:", in: $0) }.first ?? "Off"
            guard let lock = parseOnOff(lockRaw) else {
                return .malformed("Set Zoom Level Lock requires On or Off")
            }
            let lower = first.lowercased()
            if lower.hasPrefix("custom:") {
                let calculation = String(first.dropFirst("custom:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !calculation.isEmpty else { return .malformed("Set Zoom Level Custom requires a calculation") }
                return .step(.setZoomLevel(value: "ByCalculation", calculation: calculation, lock: lock))
            }
            let zoomValues: [String: String] = [
                "25%": "25", "50%": "50", "75%": "75", "100%": "100",
                "150%": "150", "200%": "200", "300%": "300", "400%": "400",
                "zoom in": "ZoomIn", "zoom out": "ZoomOut"
            ]
            guard let value = zoomValues[lower] else {
                return .malformed("Set Zoom Level expects 25%, 50%, 75%, 100%, 150%, 200%, 300%, 400%, Zoom In, Zoom Out, or Custom")
            }
            return .step(.setZoomLevel(value: value, calculation: nil, lock: lock))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Move/Resize Window", in: line) {
            guard let target = parseWindowTarget(body) else {
                return .malformed("Move/Resize Window requires Current Window or Name: calculation")
            }
            let components = TextUtilities.topLevelComponents(in: body)
            func value(_ label: String) -> String? {
                components.compactMap { TextUtilities.value(afterLabel: label, in: $0) }.first
            }
            return .step(.moveResizeWindow(
                target: target,
                height: value("Height:"),
                width: value("Width:"),
                distanceFromTop: value("Top:"),
                distanceFromLeft: value("Left:")
            ))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Set Window Title", in: line) {
            guard let target = parseWindowTarget(body) else {
                return .malformed("Set Window Title requires Current Window or Name: calculation")
            }
            let components = TextUtilities.topLevelComponents(in: body)
            let newName = components.compactMap { TextUtilities.value(afterLabel: "New title:", in: $0) }.first
            return .step(.setWindowTitle(target: target, newName: newName))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Find Matching Records", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let first = components.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return .malformed("Find Matching Records requires Replace, Constrain, or Extend")
            }
            let modes = [
                "replace": "FindMatchingReplace",
                "constrain": "FindMatchingConstrain",
                "extend": "FindMatchingExtend"
            ]
            guard let mode = modes[first] else {
                return .malformed("Find Matching Records expects Replace, Constrain, or Extend")
            }
            let target = components.dropFirst().compactMap { TextUtilities.value(afterLabel: "Target:", in: $0) }.first
            if let target {
                guard let reference = TextUtilities.splitFieldReference(target) else {
                    return .malformed("Find Matching Records Target requires Table::Field")
                }
                return .step(.findMatchingRecords(mode: mode, table: reference.table, field: reference.field))
            }
            return .step(.findMatchingRecords(mode: mode, table: nil, field: nil))
        }

        if let calculation = TextUtilities.bracketBody(forPrefix: "Perform Quick Find", in: line) {
            guard !calculation.isEmpty else { return .malformed("Perform Quick Find requires a calculation") }
            return .step(.performQuickFind(calculation: calculation))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Sort Records by Field", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            guard let first = components.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return .malformed("Sort Records by Field requires Ascending, Descending, or Associated value list")
            }
            let modes = [
                "ascending": "SortAscending",
                "descending": "SortDescending",
                "associated value list": "SortValueList"
            ]
            guard let mode = modes[first] else {
                return .malformed("Sort Records by Field expects Ascending, Descending, or Associated value list")
            }
            let target = components.dropFirst().compactMap { TextUtilities.value(afterLabel: "Target:", in: $0) }.first
            if let target {
                guard let reference = TextUtilities.splitFieldReference(target) else {
                    return .malformed("Sort Records by Field Target requires Table::Field")
                }
                return .step(.sortRecordsByField(mode: mode, table: reference.table, field: reference.field))
            }
            return .step(.sortRecordsByField(mode: mode, table: nil, field: nil))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Constrain Found Set", in: line) {
            if body.isEmpty { return .step(.constrainFoundSet(findWithoutIndexes: false)) }
            let raw = TextUtilities.value(afterLabel: "Find without indexes:", in: body) ?? body
            guard let enabled = parseOnOff(raw) else {
                return .malformed("Constrain Found Set Find without indexes requires On or Off")
            }
            return .step(.constrainFoundSet(findWithoutIndexes: enabled))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Omit Multiple Records", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            let dialogRaw = components.compactMap { TextUtilities.value(afterLabel: "With dialog:", in: $0) }.first ?? "Off"
            guard let withDialog = parseOnOff(dialogRaw) else {
                return .malformed("Omit Multiple Records With dialog requires On or Off")
            }
            let calculation = components.compactMap { TextUtilities.value(afterLabel: "Records:", in: $0) }.first
            return .step(.omitMultipleRecords(withDialog: withDialog, calculation: calculation))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Sort Records", in: line) {
            let components = TextUtilities.topLevelComponents(in: body)
            let dialogRaw = components.compactMap { TextUtilities.value(afterLabel: "With dialog:", in: $0) }.first ?? "Off"
            guard let withDialog = parseOnOff(dialogRaw) else {
                return .malformed("Sort Records With dialog requires On or Off")
            }
            let blanksLastRaw = components.compactMap { TextUtilities.value(afterLabel: "Blanks last:", in: $0) }.first
            let keepSortedRaw = components.compactMap { TextUtilities.value(afterLabel: "Keep records sorted:", in: $0) }.first
            let criteriaComponents = components.filter {
                TextUtilities.value(afterLabel: "With dialog:", in: $0) == nil
                    && TextUtilities.value(afterLabel: "Blanks last:", in: $0) == nil
                    && TextUtilities.value(afterLabel: "Keep records sorted:", in: $0) == nil
            }
            guard !criteriaComponents.isEmpty || (blanksLastRaw == nil && keepSortedRaw == nil) else {
                return .malformed("Sort Records requires one or more Table::Field Ascending or Descending criteria")
            }
            guard (blanksLastRaw == nil) == (keepSortedRaw == nil) else {
                return .malformed("Sort Records stored sort lists require both Blanks last and Keep records sorted")
            }
            guard let blanksLastRaw, let keepSortedRaw else {
                return .step(.sortRecords(withDialog: withDialog, sortList: nil))
            }
            guard let blanksLast = parseOnOff(blanksLastRaw), let keepRecordsSorted = parseOnOff(keepSortedRaw) else {
                return .malformed("Sort Records Blanks last and Keep records sorted require On or Off")
            }
            var criteria: [SortRecordCriterion] = []
            for component in criteriaComponents {
                let words = component.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1).map(String.init)
                let order: SortOrder?
                switch words.count == 2 ? words[1].lowercased() : "" {
                case "ascending": order = .ascending
                case "descending": order = .descending
                default: order = nil
                }
                guard words.count == 2,
                      let reference = TextUtilities.splitFieldReference(words[0]),
                      let order else {
                    return .malformed("Sort Records criteria require Table::Field Ascending or Descending")
                }
                criteria.append(SortRecordCriterion(table: reference.table, field: reference.field, order: order))
            }
            return .step(.sortRecords(withDialog: withDialog, sortList: SortRecordList(blanksLast: blanksLast, keepRecordsSorted: keepRecordsSorted, criteria: criteria)))
        }

        if let body = TextUtilities.bracketBody(forPrefix: "Extend Found Set", in: line), body.isEmpty {
            return .step(.noOption(id: 127, name: "Extend Found Set"))
        }

        let simpleSteps: [(String, Int)] = [
            ("Exit Application", 44),
            ("New Record/Request", 7),
            ("Show All Records", 23),
            ("Commit Records/Requests", 75),
            ("Freeze Window", 79),
            ("Refresh Window", 80),
            ("Copy All Records/Requests", 98),
            ("Copy Record/Request", 101),
            ("Delete Portal Row", 104),
            ("Duplicate Record/Request", 8),
            ("Export Records", 36),
            ("Import Records", 35),
            ("Open Record/Request", 133),
            ("Save Records as Excel", 143),
            ("Save Records as JSONL", 225),
            ("Save Records as Snapshot Link", 152),
            ("Truncate Table", 182),
            ("Constrain Found Set", 126),
            ("Extend Found Set", 127),
            ("Find Matching Records", 155),
            ("Modify Last Find", 24),
            ("Omit Multiple Records", 26),
            ("Omit Record", 25),
            ("Perform Quick Find", 150),
            ("Show Omitted Only", 27),
            ("Sort Records", 39),
            ("Sort Records by Field", 154),
            ("Unsort Records", 21),
            ("Adjust Window", 31),
            ("Arrange All Windows", 120),
            ("Move/Resize Window", 119),
            ("Scroll Window", 81),
            ("Set Window Title", 124),
            ("Set Zoom Level", 97),
            ("Show/Hide Menubar", 166),
            ("Show/Hide Text Ruler", 92),
            ("Show/Hide Toolbars", 29),
            ("View As", 30),
            ("Open Edit Saved Finds", 149),
            ("Open Favorites", 183),
            ("Open File Options", 114),
            ("Open Find/Replace", 129),
            ("Open Help", 32),
            ("Open Hosts", 118),
            ("Open Manage Containers", 156),
            ("Open Manage Data Sources", 140),
            ("Open Manage Database", 38),
            ("Open Manage Layouts", 151),
            ("Open Manage Themes", 165),
            ("Open Manage Value Lists", 112),
            ("Open Settings", 105),
            ("Open Script Workspace", 88),
            ("Open Sharing", 113),
            ("Open Upload to Host", 172),
            ("Halt Script", 90),
            ("Beep", 93),
            ("Flush Cache to Disk", 102),
            ("Flush Web Viewer Cookies", 237)
        ]
        let capturedDefaultOnlyIDs: Set<Int> = [8, 21, 24, 25, 26, 27, 29, 35, 36, 39, 92, 97, 98, 101, 104, 119, 124, 126, 127, 133, 143, 150, 152, 154, 155, 166, 182, 225]
        for (name, id) in simpleSteps where isExact(line, name) || (!capturedDefaultOnlyIDs.contains(id) && TextUtilities.caseInsensitivePrefix(name + " [", in: line)) {
            return .step(.noOption(id: id, name: name))
        }

        return .unsupported(FileMakerScriptStepCatalog.officialStep(matching: line)?.name)
    }

    private func validateStructure(
        _ step: CompiledStep,
        line: LogicalLine,
        structures: inout [(kind: StructureKind, line: LogicalLine)],
        issues: inout [CompilationIssue]
    ) {
        switch step {
        case .ifStep:
            structures.append((.ifBlock, line))
        case .loop:
            structures.append((.loopBlock, line))
        case .elseIf, .elseStep:
            if structures.last?.kind != .ifBlock {
                issues.append(structureIssue(line, message: "This step must be inside an If block"))
            }
        case .endIf:
            if structures.last?.kind == .ifBlock {
                structures.removeLast()
            } else {
                issues.append(structureIssue(line, message: "End If does not match an open If"))
            }
        case .exitLoopIf:
            if !structures.contains(where: { $0.kind == .loopBlock }) {
                issues.append(structureIssue(line, message: "Exit Loop If must be inside a Loop"))
            }
        case .endLoop:
            if structures.last?.kind == .loopBlock {
                structures.removeLast()
            } else {
                issues.append(structureIssue(line, message: "End Loop does not match an open Loop"))
            }
        default:
            break
        }
    }

    private func appendFallback(
        _ line: LogicalLine,
        reason: String,
        options: CompilationOptions,
        steps: inout [CompiledStep],
        issues: inout [CompilationIssue]
    ) {
        let severity: IssueSeverity = options.convertUnsupportedLinesToComments ? .warning : .error
        issues.append(CompilationIssue(
            severity: severity,
            line: line.lineNumber,
            message: options.convertUnsupportedLinesToComments
                ? "\(reason); converted to a FileMaker comment"
                : reason,
            source: line.text
        ))
        if options.convertUnsupportedLinesToComments {
            let templateName = FileMakerScriptStepCatalog.officialStep(matching: line.text)?.name ?? "unmapped script step"
            steps.append(.comment(text: "-----------------  FileMaker Script Bridge TODO -----------------", isFallback: true))
            steps.append(.comment(text: "\(templateName) in FileMaker. AI draft: \(line.text)", isFallback: true))
        }
    }

    private func dataReference(_ raw: String) -> DataReference? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^\${1,2}[\p{L}_][\p{L}\p{N}_]*$"#, options: .regularExpression) != nil {
            return .variable(value)
        }
        if !value.contains(where: { ";[]()&=\"".contains($0) }),
           let field = TextUtilities.splitFieldReference(value) {
            return .field(table: field.table, name: field.field)
        }
        return nil
    }

    private func parseDataAndURLStep(_ line: String) -> LineParseResult? {
        let names = ["Create Data File", "Open Data File", "Write to Data File", "Close Data File", "Insert from URL"]
        guard let name = names.first(where: { TextUtilities.hasStepNamePrefix($0, in: line) }) else { return nil }
        guard let body = TextUtilities.bracketBody(forPrefix: name, in: line) else {
            return .malformed("\(name) requires an option block")
        }
        var options: [String: String] = [:]
        var positional: [String] = []
        let labels: [String]
        switch name {
        case "Create Data File": labels = ["File:", "Create folders:"]
        case "Open Data File": labels = ["File:", "Target:"]
        case "Write to Data File": labels = ["File ID:", "Data source:", "Write as:", "Append line feed:"]
        case "Close Data File": labels = ["File ID:"]
        default: labels = ["Target:", "URL:", "cURL options:", "Select:", "With dialog:", "Verify SSL Certificates:", "Automatically encode URL:"]
        }
        for part in TextUtilities.topLevelComponents(in: body) where !part.isEmpty {
            var key: String?
            var value = ""
            if let label = labels.first(where: { TextUtilities.value(afterLabel: $0, in: part) != nil }) {
                key = label.lowercased()
                value = TextUtilities.value(afterLabel: label, in: part)!
            } else {
                let flags: [String: (String, String)] = name == "Insert from URL" ? [
                    "select": ("select:", "On"), "no dialog": ("with dialog:", "Off"),
                    "verify ssl certificates": ("verify ssl certificates:", "On"),
                    "do not automatically encode url": ("automatically encode url:", "Off")
                ] : name == "Write to Data File" ? ["append line feed": ("append line feed:", "On")] : [:]
                if let flag = flags[part.lowercased()] { key = flag.0; value = flag.1 }
            }
            if let key {
                guard options[key] == nil, !value.isEmpty else { return .malformed("\(name) has a duplicate or empty option: \(part)") }
                options[key] = value
            } else { positional.append(part) }
        }
        func boolean(_ label: String, _ defaultValue: Bool) -> Bool? {
            guard let raw = options[label] else { return defaultValue }
            return parseYesNo(raw)
        }
        switch name {
        case "Create Data File", "Open Data File":
            guard positional.count <= 1, !(options["file:"] != nil && !positional.isEmpty),
                  let rawPath = options["file:"] ?? positional.first else { return .malformed("\(name) requires one file path") }
            let path = TextUtilities.unquote(rawPath)
            guard !path.isEmpty else { return .malformed("\(name) requires a nonempty file path") }
            if name == "Create Data File" {
                guard let folders = boolean("create folders:", true) else { return .malformed("Create folders requires On or Off") }
                return .step(.createDataFile(path: path, createDirectories: folders))
            }
            guard let raw = options["target:"], let target = dataReference(raw) else { return .malformed("Open Data File Target requires a variable or Table::Field") }
            return .step(.openDataFile(path: path, target: target))
        case "Write to Data File":
            guard positional.isEmpty, let fileID = options["file id:"],
                  let rawSource = options["data source:"], let source = dataReference(rawSource),
                  let append = boolean("append line feed:", false) else { return .malformed("Write to Data File requires File ID, a variable or field Data source, and valid options") }
            let encoding = TextUtilities.unquote(options["write as:"] ?? "UTF-16").uppercased()
            guard ["UTF-8", "UTF-16"].contains(encoding) else { return .malformed("Write as requires UTF-8 or UTF-16") }
            return .step(.writeDataFile(fileID: fileID, source: source, utf8: encoding == "UTF-8", appendLineFeed: append))
        case "Close Data File":
            guard positional.isEmpty, let fileID = options["file id:"] else { return .malformed("Close Data File requires File ID: calculation") }
            return .step(.closeDataFile(fileID: fileID))
        default:
            var rawTarget = options["target:"]
            var url = options["url:"]
            if rawTarget == nil, positional.count == 2 { rawTarget = positional.removeFirst() }
            if url == nil, positional.count == 1 { url = positional.removeFirst() }
            guard positional.isEmpty, let rawTarget, let target = dataReference(rawTarget), let url, !url.isEmpty,
                  let select = boolean("select:", false), let dialog = boolean("with dialog:", false),
                  let ssl = boolean("verify ssl certificates:", false), let encode = boolean("automatically encode url:", true) else {
                return .malformed("Insert from URL requires a variable or field Target, URL calculation, and valid On/Off options")
            }
            return .step(.insertFromURL(target: target, url: url, curl: options["curl options:"], selectAll: select, withDialog: dialog, verifySSL: ssl, encodeURL: encode))
        }
    }

    private func parseOnOff(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "on", "true", "1", "yes": return true
        case "off", "false", "0", "no": return false
        default: return nil
        }
    }

    private func parseYesNo(_ value: String) -> Bool? {
        parseOnOff(TextUtilities.unquote(value))
    }

    private func normalizeSmartQuotedCalculation(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.first == "“" && trimmed.last == "”")
                || (trimmed.first == "‘" && trimmed.last == "’") else {
            return trimmed
        }
        let inner = TextUtilities.unquote(trimmed).replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(inner)\""
    }

    private func parseWindowTarget(_ body: String) -> WindowTarget? {
        let components = TextUtilities.topLevelComponents(in: body)
        if components.first?.caseInsensitiveCompare("Current Window") == .orderedSame {
            return .current
        }
        guard let calculation = components.compactMap({
            TextUtilities.value(afterLabel: "Name:", in: $0)
        }).first, !calculation.isEmpty else {
            return nil
        }
        let currentFileOnly = components.contains {
            $0.caseInsensitiveCompare("Current file") == .orderedSame
        }
        return .byName(calculation: calculation, currentFileOnly: currentFileOnly)
    }

    private func isExact(_ value: String, _ expected: String) -> Bool {
        value.compare(expected, options: [.caseInsensitive], range: nil, locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
    }

    private func structureIssue(_ line: LogicalLine, message: String) -> CompilationIssue {
        CompilationIssue(
            severity: .error,
            line: line.lineNumber,
            message: message,
            source: line.text
        )
    }

    private func preservationToken(in line: String) -> String? {
        guard let open = line.lastIndex(of: "["),
              let close = line.lastIndex(of: "]"),
              open < close else {
            return nil
        }
        let token = String(line[line.index(after: open)..<close])
        return token.hasPrefix("SCKC-P") ? token : nil
    }
}

private enum StructureKind {
    case ifBlock
    case loopBlock
}

private enum LineParseResult {
    case step(CompiledStep)
    case malformed(String)
    case blocking(String)
    case unsupported(String?)
}
