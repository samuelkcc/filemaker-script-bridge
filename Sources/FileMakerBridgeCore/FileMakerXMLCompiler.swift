import Foundation

public struct FileMakerXMLCompiler: Sendable {
    public init() {}

    public func compile(
        _ source: String,
        options: CompilationOptions = CompilationOptions(),
        preservedSteps: [String: PreservedFileMakerStep] = [:]
    ) -> CompilationResult {
        let parsed = FileMakerTextParser().parse(
            source,
            options: options,
            preservedSteps: preservedSteps
        )
        let xml = renderDocument(parsed.steps)
        return CompilationResult(
            source: source,
            logicalLines: parsed.logicalLines,
            steps: parsed.steps,
            issues: parsed.issues,
            xml: xml,
            supportedStepCount: parsed.steps.filter { !$0.isFallbackComment && !$0.isPreservedStep }.count,
            commentFallbackCount: parsed.steps.filter(\.isFallbackComment).count,
            preservedStepCount: parsed.steps.filter(\.isPreservedStep).count
        )
    }

    public func renderDocument(_ steps: [CompiledStep]) -> String {
        let body = steps.map(renderStep).joined(separator: "\n")
        return "<fmxmlsnippet type=\"FMObjectList\">\n\(body)\n</fmxmlsnippet>"
    }

    private func renderStep(_ step: CompiledStep) -> String {
        switch step {
        case .comment(let text, _):
            return stepElement(id: 89, name: "# (comment)", body: "  <Text>\(escapeXML(text))</Text>")

        case .setVariable(let name, let value, let repetition):
            var nodes = [
                "  <Value>",
                "    <Calculation>\(cdata(value))</Calculation>",
                "  </Value>"
            ]
            if let repetition, !repetition.isEmpty {
                nodes += [
                    "  <Repetition>",
                    "    <Calculation>\(cdata(repetition))</Calculation>",
                    "  </Repetition>"
                ]
            }
            nodes.append("  <Name>\(escapeXML(name))</Name>")
            return stepElement(id: 141, name: "Set Variable", body: nodes.joined(separator: "\n"))

        case .setField(let table, let field, let value):
            let body = [
                "  <Calculation>\(cdata(value))</Calculation>",
                "  <Field table=\"\(escapeAttribute(table))\" id=\"0\" name=\"\(escapeAttribute(field))\"></Field>"
            ].joined(separator: "\n")
            return stepElement(id: 76, name: "Set Field", body: body)

        case .setFieldByName(let target, let value):
            let body = [
                "  <TargetName>",
                "    <Calculation>\(cdata(target))</Calculation>",
                "  </TargetName>",
                "  <Result>",
                "    <Calculation>\(cdata(value))</Calculation>",
                "  </Result>"
            ].joined(separator: "\n")
            return stepElement(id: 147, name: "Set Field By Name", body: body)

        case .ifStep(let calculation):
            return calculationStep(id: 68, name: "If", calculation: calculation)
        case .elseIf(let calculation):
            return calculationStep(id: 125, name: "Else If", calculation: calculation)
        case .elseStep:
            return stepElement(id: 69, name: "Else", body: "  <Restore state=\"False\"></Restore>")
        case .endIf:
            return emptyStep(id: 70, name: "End If")
        case .loop(let flush):
            let body = [
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <Restore state=\"False\"></Restore>",
                "  <FlushType value=\"\(flush.rawValue)\"></FlushType>"
            ].joined(separator: "\n")
            return stepElement(id: 71, name: "Loop", body: body)
        case .exitLoopIf(let calculation):
            return calculationStep(id: 72, name: "Exit Loop If", calculation: calculation)
        case .endLoop:
            return emptyStep(id: 73, name: "End Loop")

        case .performScript(let name, let parameter):
            var nodes: [String] = []
            if let parameter, !parameter.isEmpty {
                nodes.append("  <Calculation>\(cdata(parameter))</Calculation>")
            }
            nodes.append("  <Script id=\"0\" name=\"\(escapeAttribute(name))\"></Script>")
            return stepElement(id: 1, name: "Perform Script", body: nodes.joined(separator: "\n"))

        case .performScriptOnServer(let name, let parameter, let waitForCompletion):
            var nodes = [
                "  <WaitForCompletion state=\"\(waitForCompletion ? "True" : "False")\"></WaitForCompletion>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"
            ]
            if let parameter, !parameter.isEmpty {
                nodes.append("  <Calculation>\(cdata(parameter))</Calculation>")
            }
            nodes.append("  <Script id=\"0\" name=\"\(escapeAttribute(name))\"></Script>")
            return stepElement(id: 164, name: "Perform Script on Server", body: nodes.joined(separator: "\n"))

        case .goToLayout(let name):
            let body = [
                "  <LayoutDestination value=\"SelectedLayout\"></LayoutDestination>",
                "  <Layout id=\"0\" name=\"\(escapeAttribute(name))\"></Layout>"
            ].joined(separator: "\n")
            return stepElement(id: 6, name: "Go to Layout", body: body)

        case .goToRecord(let destination, let exitAfterLast):
            var nodes: [String] = []
            let location: String
            switch destination {
            case .first: location = "First"
            case .last: location = "Last"
            case .previous: location = "Previous"
            case .next: location = "Next"
            case .byCalculation(let calculation):
                location = "ByCalculation"
                nodes.append("  <NoInteract state=\"True\"></NoInteract>")
                nodes.append("  <RowPageLocation value=\"\(location)\"></RowPageLocation>")
                nodes.append("  <Calculation>\(cdata(calculation))</Calculation>")
                return stepElement(id: 16, name: "Go to Record/Request/Page", body: nodes.joined(separator: "\n"))
            }
            if destination == .next || destination == .previous {
                nodes.append("  <Exit state=\"\(exitAfterLast ? "True" : "False")\"></Exit>")
            }
            nodes.append("  <RowPageLocation value=\"\(location)\"></RowPageLocation>")
            return stepElement(id: 16, name: "Go to Record/Request/Page", body: nodes.joined(separator: "\n"))

        case .showCustomDialog(let title, let message, let buttons):
            var nodes: [String] = []
            if let title, !title.isEmpty {
                nodes += [
                    "  <Title>",
                    "    <Calculation>\(cdata(title))</Calculation>",
                    "  </Title>"
                ]
            }
            nodes += [
                "  <Message>",
                "    <Calculation>\(cdata(message))</Calculation>",
                "  </Message>",
                "  <Buttons>"
            ]
            for button in Array(buttons.prefix(3)) {
                nodes += [
                    "    <Button CommitState=\"\(button.commitsRecord ? "True" : "False")\">",
                    "      <Calculation>\(cdata(button.calculation))</Calculation>",
                    "    </Button>"
                ]
            }
            for _ in buttons.count..<3 {
                nodes.append("    <Button CommitState=\"False\"></Button>")
            }
            nodes.append("  </Buttons>")
            return stepElement(id: 87, name: "Show Custom Dialog", body: nodes.joined(separator: "\n"))

        case .newWindow(let options):
            let styles = options.toolbars ? "0" : "1"
            let body = [
                "  <Name>",
                "    <Calculation>\(cdata(options.nameCalculation))</Calculation>",
                "  </Name>",
                "  <NewWndStyles Style=\"\(escapeAttribute(options.style))\" Close=\"\(yesNo(options.close))\" Minimize=\"\(yesNo(options.minimize))\" Maximize=\"\(yesNo(options.maximize))\" Resize=\"\(yesNo(options.resize))\" MenuBar=\"\(yesNo(options.menuBar))\" DimParentWindow=\"\(yesNo(options.dimParentWindow))\" Styles=\"\(styles)\"></NewWndStyles>",
                "  <LayoutDestination value=\"SelectedLayout\"></LayoutDestination>",
                "  <Layout name=\"\(escapeAttribute(options.layoutName))\" id=\"0\"></Layout>"
            ].joined(separator: "\n")
            return stepElement(id: 122, name: "New Window", body: body)

        case .selectWindow(let target):
            return windowStep(id: 123, name: "Select Window", target: target)

        case .closeWindow(let target):
            return windowStep(id: 121, name: "Close Window", target: target)

        case .recordDialogStep(let id, let name, let noInteract):
            return stepElement(
                id: id,
                name: name,
                body: "  <NoInteract state=\"\(noInteract ? "True" : "False")\"></NoInteract>"
            )

        case .enterFindMode(let pause):
            let body = [
                "  <Pause state=\"\(pause ? "True" : "False")\"></Pause>",
                "  <Restore state=\"False\"></Restore>"
            ].joined(separator: "\n")
            return stepElement(id: 22, name: "Enter Find Mode", body: body)

        case .performFind(let restore):
            return stepElement(
                id: 28,
                name: "Perform Find",
                body: "  <Restore state=\"\(restore ? "True" : "False")\"></Restore>"
            )

        case .exitScript(let result):
            if let result, !result.isEmpty {
                return calculationStep(id: 103, name: "Exit Script", calculation: result)
            }
            return emptyStep(id: 103, name: "Exit Script")

        case .toggle(let id, let name, let enabled):
            let body: String
            switch id {
            case 94, 115:
                body = [
                    "  <Set state=\"\(enabled ? "True" : "False")\"></Set>",
                    "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"
                ].joined(separator: "\n")
            case 174:
                body = [
                    "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                    "  <ShowHide value=\"\(enabled ? "Show" : "Hide")\"></ShowHide>"
                ].joined(separator: "\n")
            default:
                body = "  <Set state=\"\(enabled ? "True" : "False")\"></Set>"
            }
            return stepElement(
                id: id,
                name: name,
                body: body
            )

        case .enumOption(let id, let name, let element, let value):
            let body = [
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <\(element) value=\"\(escapeAttribute(value))\"></\(element)>"
            ].joined(separator: "\n")
            return stepElement(id: id, name: name, body: body)

        case .showHide(let id, let name, let value, let lock, let includeEditRecordToolbar):
            var nodes: [String] = []
            if let includeEditRecordToolbar {
                nodes.append("  <IncludeEditRecordToolbar state=\"\(includeEditRecordToolbar ? "True" : "False")\"></IncludeEditRecordToolbar>")
            }
            nodes += [
                "  <Lock state=\"\(lock ? "True" : "False")\"></Lock>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <ShowHide value=\"\(escapeAttribute(value))\"></ShowHide>"
            ]
            return stepElement(id: id, name: name, body: nodes.joined(separator: "\n"))

        case .setZoomLevel(let value, let calculation, let lock):
            var nodes = [
                "  <Lock state=\"\(lock ? "True" : "False")\"></Lock>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <Zoom value=\"\(escapeAttribute(value))\"></Zoom>"
            ]
            if let calculation {
                nodes.append("  <Calculation>\(cdata(calculation))</Calculation>")
            }
            return stepElement(id: 97, name: "Set Zoom Level", body: nodes.joined(separator: "\n"))

        case .moveResizeWindow(let target, let height, let width, let distanceFromTop, let distanceFromLeft):
            var nodes = ["  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"]
            switch target {
            case .current:
                nodes += [
                    "  <LimitToWindowsOfCurrentFile state=\"True\"></LimitToWindowsOfCurrentFile>",
                    "  <Window value=\"Current\"></Window>"
                ]
            case .byName(let calculation, let currentFileOnly):
                nodes += [
                    "  <LimitToWindowsOfCurrentFile state=\"\(currentFileOnly ? "True" : "False")\"></LimitToWindowsOfCurrentFile>",
                    "  <Window value=\"ByName\"></Window>",
                    "  <Name>",
                    "    <Calculation>\(cdata(calculation))</Calculation>",
                    "  </Name>"
                ]
            }
            for (element, calculation) in [
                ("Height", height), ("Width", width),
                ("DistanceFromTop", distanceFromTop), ("DistanceFromLeft", distanceFromLeft)
            ] where calculation != nil {
                nodes += [
                    "  <\(element)>",
                    "    <Calculation>\(cdata(calculation!))</Calculation>",
                    "  </\(element)>"
                ]
            }
            return stepElement(id: 119, name: "Move/Resize Window", body: nodes.joined(separator: "\n"))

        case .setWindowTitle(let target, let newName):
            var nodes = ["  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"]
            switch target {
            case .current:
                nodes += [
                    "  <LimitToWindowsOfCurrentFile state=\"True\"></LimitToWindowsOfCurrentFile>",
                    "  <Window value=\"Current\"></Window>"
                ]
            case .byName(let calculation, let currentFileOnly):
                nodes += [
                    "  <LimitToWindowsOfCurrentFile state=\"\(currentFileOnly ? "True" : "False")\"></LimitToWindowsOfCurrentFile>",
                    "  <Window value=\"ByName\"></Window>",
                    "  <Name>",
                    "    <Calculation>\(cdata(calculation))</Calculation>",
                    "  </Name>"
                ]
            }
            if let newName {
                nodes += [
                    "  <NewName>",
                    "    <Calculation>\(cdata(newName))</Calculation>",
                    "  </NewName>"
                ]
            }
            return stepElement(id: 124, name: "Set Window Title", body: nodes.joined(separator: "\n"))

        case .findMatchingRecords(let mode, let table, let field):
            var nodes = [
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <FindMatchingRecordsByField value=\"\(escapeAttribute(mode))\"></FindMatchingRecordsByField>"
            ]
            if let table, let field {
                nodes.append("  <Field table=\"\(escapeAttribute(table))\" id=\"0\" name=\"\(escapeAttribute(field))\"></Field>")
            }
            return stepElement(id: 155, name: "Find Matching Records", body: nodes.joined(separator: "\n"))

        case .performQuickFind(let calculation):
            let body = [
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <Calculation>\(cdata(calculation))</Calculation>"
            ].joined(separator: "\n")
            return stepElement(id: 150, name: "Perform Quick Find", body: body)

        case .sortRecordsByField(let mode, let table, let field):
            var nodes = [
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <SortRecordsByField value=\"\(escapeAttribute(mode))\"></SortRecordsByField>"
            ]
            if let table, let field {
                nodes.append("  <Field table=\"\(escapeAttribute(table))\" id=\"0\" name=\"\(escapeAttribute(field))\"></Field>")
            }
            return stepElement(id: 154, name: "Sort Records by Field", body: nodes.joined(separator: "\n"))

        case .constrainFoundSet(let findWithoutIndexes):
            let body = [
                "  <Option state=\"\(findWithoutIndexes ? "True" : "False")\"></Option>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <Restore state=\"False\"></Restore>"
            ].joined(separator: "\n")
            return stepElement(id: 126, name: "Constrain Found Set", body: body)

        case .omitMultipleRecords(let withDialog, let calculation):
            var nodes = [
                "  <NoInteract state=\"\(withDialog ? "False" : "True")\"></NoInteract>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"
            ]
            if let calculation {
                nodes.append("  <Calculation>\(cdata(calculation))</Calculation>")
            }
            return stepElement(id: 26, name: "Omit Multiple Records", body: nodes.joined(separator: "\n"))

        case .sortRecords(let withDialog, let sortList):
            var nodes = [
                "  <NoInteract state=\"\(withDialog ? "False" : "True")\"></NoInteract>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <Restore state=\"\(sortList == nil ? "False" : "True")\"></Restore>"
            ]
            if let sortList {
                nodes.append("  <SortList BlanksLast=\"\(sortList.blanksLast ? "True" : "False")\" Maintain=\"\(sortList.keepRecordsSorted ? "True" : "False")\" value=\"True\">")
                for criterion in sortList.criteria {
                    nodes += [
                        "    <Sort type=\"\(criterion.order.rawValue)\">",
                        "      <PrimaryField><Field table=\"\(escapeAttribute(criterion.table))\" id=\"0\" name=\"\(escapeAttribute(criterion.field))\"></Field></PrimaryField>",
                        "    </Sort>"
                    ]
                }
                nodes.append("  </SortList>")
            }
            return stepElement(id: 39, name: "Sort Records", body: nodes.joined(separator: "\n"))

        case .importRecords(let options):
            let body = [
                "  <NoInteract state=\"\(options.withDialog ? "False" : "True")\"></NoInteract>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <Restore state=\"False\"></Restore>",
                "  <VerifySSLCertificates state=\"False\"></VerifySSLCertificates>",
                "  <DataSourceType value=\"File\"></DataSourceType>",
                "  <Profile FileName=\"\(escapeAttribute(options.path))\" WorksheetName=\"\" SelectedSheet=\"0\" FieldDelimiter=\"&#09;\" IsPredefined=\"-1\" FieldNameRow=\"-1\" DataType=\"XLSX\"></Profile>",
                "  <UniversalPathList>\(escapeXML(options.path))</UniversalPathList>"
            ].joined(separator: "\n")
            return stepElement(id: 35, name: "Import Records", body: body)

        case .exportRecords(let options):
            var nodes = [
                "  <NoInteract state=\"\(options.withDialog ? "False" : "True")\"></NoInteract>",
                "  <CreateDirectories state=\"\(options.createDirectories ? "True" : "False")\"></CreateDirectories>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <Restore state=\"True\"></Restore>",
                "  <AutoOpen state=\"False\"></AutoOpen>",
                "  <CreateEmail state=\"False\"></CreateEmail>",
                "  <Profile FieldDelimiter=\"&#09;\" IsPredefined=\"-1\" FieldNameRow=\"-1\" DataType=\"XLXE\"></Profile>",
                "  <UniversalPathList>\(escapeXML(options.path))</UniversalPathList>",
                "  <UseFieldNames state=\"\(options.useFieldNames ? "True" : "False")\"></UseFieldNames>",
                "  <ExportOptions FormatUsingCurrentLayout=\"False\" CharacterSet=\"\(options.characterSet)\"></ExportOptions>",
                "  <ExportEntries>"
            ]
            for field in options.fields {
                nodes.append("    <ExportEntry><Field table=\"\(escapeAttribute(field.table))\" id=\"0\" name=\"\(escapeAttribute(field.field))\"></Field></ExportEntry>")
            }
            nodes.append("  </ExportEntries>")
            return stepElement(id: 36, name: "Export Records", body: nodes.joined(separator: "\n"))

        case .saveRecordsAsExcel(let options):
            let body = [
                "  <NoInteract state=\"\(options.withDialog ? "False" : "True")\"></NoInteract>",
                "  <CreateDirectories state=\"\(options.createDirectories ? "True" : "False")\"></CreateDirectories>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <Restore state=\"False\"></Restore>",
                "  <AutoOpen state=\"False\"></AutoOpen>",
                "  <CreateEmail state=\"False\"></CreateEmail>",
                "  <Profile FieldDelimiter=\"&#09;\" IsPredefined=\"-1\" FieldNameRow=\"-1\" DataType=\"XLXE\"></Profile>",
                "  <UniversalPathList>\(escapeXML(options.path))</UniversalPathList>",
                "  <SaveType value=\"\(escapeAttribute(options.saveType))\"></SaveType>",
                "  <UseFieldNames state=\"\(options.useFieldNames ? "True" : "False")\"></UseFieldNames>"
            ].joined(separator: "\n")
            return stepElement(id: 143, name: "Save Records as Excel", body: body)

        case .sendMail(let options):
            let body = [
                "  <NoInteract state=\"\(options.withDialog ? "False" : "True")\"></NoInteract>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <Attachment><UniversalPathList>\(escapeXML(options.attachmentPath))</UniversalPathList></Attachment>",
                "  <MultipleEmails state=\"False\"></MultipleEmails>",
                "  <SendViaSMTP state=\"False\"></SendViaSMTP>",
                "  <SendViaOAuthAuthentication state=\"False\"></SendViaOAuthAuthentication>",
                "  <SMTPEncryptionType type=\"SMTPEncryptionNone\"></SMTPEncryptionType>",
                "  <SMTPAuthenticationType type=\"SMTPAuthenticationNone\"></SMTPAuthenticationType>",
                "  <OAuthProvider type=\"OAuthProviderGoogle\"></OAuthProvider>"
            ].joined(separator: "\n")
            return stepElement(id: 63, name: "Send Mail", body: body)

        case .noOption(let id, let name):
            if let body = capturedDefaultBody(for: id) {
                return stepElement(id: id, name: name, body: body)
            }
            switch id {
            case 75:
                let body = [
                    "  <NoInteract state=\"True\"></NoInteract>",
                    "  <Option state=\"False\"></Option>"
                ].joined(separator: "\n")
                return stepElement(id: id, name: name, body: body)
            case 80:
                return stepElement(id: id, name: name, body: "  <FlushJoinResults state=\"False\"></FlushJoinResults>")
            case 32, 38, 44, 102, 105, 112, 113, 114, 118, 129, 140, 149, 151, 156, 165, 172, 183, 237:
                return stepElement(
                    id: id,
                    name: name,
                    body: "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"
                )
            default:
                return emptyStep(id: id, name: name)
            }

        case .exportFieldContents(let table, let field, let path, let createDirectories):
            let body = [
                "  <CreateDirectories state=\"\(createDirectories ? "True" : "False")\"></CreateDirectories>",
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <AutoOpen state=\"False\"></AutoOpen>",
                "  <CreateEmail state=\"False\"></CreateEmail>",
                "  <UniversalPathList>\(escapeXML(path))</UniversalPathList>",
                "  <Field table=\"\(escapeAttribute(table))\" id=\"0\" name=\"\(escapeAttribute(field))\"></Field>"
            ].joined(separator: "\n")
            return stepElement(id: 132, name: "Export Field Contents", body: body)

        case .insertFile(let table, let field, let path):
            let body = [
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <UniversalPathList type=\"Embedded\">\(escapeXML(path))</UniversalPathList>",
                "  <Field table=\"\(escapeAttribute(table))\" id=\"0\" name=\"\(escapeAttribute(field))\"></Field>",
                "  <DialogOptions asFile=\"True\" enable=\"False\">",
                "    <Storage type=\"UserChoice\"></Storage>",
                "    <Compress type=\"UserChoice\"></Compress>",
                "    <FilterList></FilterList>",
                "  </DialogOptions>"
            ].joined(separator: "\n")
            return stepElement(id: 131, name: "Insert File", body: body)

        case .refreshObject(let objectName, let repetition):
            let body = [
                "  <DisableStepCollapsed state=\"False\"></DisableStepCollapsed>",
                "  <ObjectName>",
                "    <Calculation>\(cdata(objectName))</Calculation>",
                "  </ObjectName>",
                "  <Repetition>",
                "    <Calculation>\(cdata(repetition))</Calculation>",
                "  </Repetition>"
            ].joined(separator: "\n")
            return stepElement(id: 167, name: "Refresh Object", body: body)

        case .preservedXML(_, _, let xml):
            return xml
        }
    }

    private func calculationStep(id: Int, name: String, calculation: String) -> String {
        stepElement(id: id, name: name, body: "  <Calculation>\(cdata(calculation))</Calculation>")
    }

    private func emptyStep(id: Int, name: String) -> String {
        "  <Step enable=\"True\" id=\"\(id)\" name=\"\(escapeAttribute(name))\"></Step>"
    }

    private func capturedDefaultBody(for id: Int) -> String? {
        let elements: [String]
        switch id {
        case 8, 21, 24, 25, 27, 98, 101, 133:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"]
        case 104:
            elements = ["<NoInteract state=\"False\"></NoInteract>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"]
        case 36:
            elements = ["<NoInteract state=\"True\"></NoInteract>", "<CreateDirectories state=\"True\"></CreateDirectories>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<Restore state=\"False\"></Restore>", "<AutoOpen state=\"False\"></AutoOpen>", "<CreateEmail state=\"False\"></CreateEmail>"]
        case 35:
            elements = ["<NoInteract state=\"True\"></NoInteract>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<Restore state=\"False\"></Restore>", "<VerifySSLCertificates state=\"False\"></VerifySSLCertificates>"]
        case 143:
            elements = ["<NoInteract state=\"True\"></NoInteract>", "<CreateDirectories state=\"True\"></CreateDirectories>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<Restore state=\"False\"></Restore>", "<AutoOpen state=\"False\"></AutoOpen>", "<CreateEmail state=\"False\"></CreateEmail>", "<SaveType value=\"BrowsedRecords\"></SaveType>", "<UseFieldNames state=\"False\"></UseFieldNames>"]
        case 225:
            elements = ["<Option state=\"False\"></Option>", "<CreateDirectories state=\"False\"></CreateDirectories>", "<FineTuneFormat state=\"False\"></FineTuneFormat>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<AutoOpen state=\"False\"></AutoOpen>", "<CreateEmail state=\"False\"></CreateEmail>", "<SaveAsJSONL></SaveAsJSONL>"]
        case 152:
            elements = ["<CreateDirectories state=\"True\"></CreateDirectories>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<CreateEmail state=\"False\"></CreateEmail>", "<SaveType value=\"BrowsedRecords\"></SaveType>"]
        case 182:
            elements = ["<NoInteract state=\"False\"></NoInteract>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<BaseTable id=\"-1\" name=\"&lt;Current Table&gt;\"></BaseTable>"]
        case 126:
            elements = ["<Option state=\"False\"></Option>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<Restore state=\"False\"></Restore>"]
        case 127:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<Restore state=\"False\"></Restore>"]
        case 155:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<FindMatchingRecordsByField value=\"FindMatchingReplace\"></FindMatchingRecordsByField>"]
        case 26:
            elements = ["<NoInteract state=\"True\"></NoInteract>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"]
        case 150:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>"]
        case 39:
            elements = ["<NoInteract state=\"True\"></NoInteract>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<Restore state=\"False\"></Restore>"]
        case 154:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<SortRecordsByField value=\"SortAscending\"></SortRecordsByField>"]
        case 31:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<WindowState value=\"ResizeToFit\"></WindowState>"]
        case 120:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<WindowArrangement value=\"TileHorizontally\"></WindowArrangement>"]
        case 119:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<LimitToWindowsOfCurrentFile state=\"True\"></LimitToWindowsOfCurrentFile>", "<Window value=\"Current\"></Window>"]
        case 81:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<ScrollOperation value=\"Home\"></ScrollOperation>"]
        case 124:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<LimitToWindowsOfCurrentFile state=\"True\"></LimitToWindowsOfCurrentFile>", "<Window value=\"Current\"></Window>"]
        case 97:
            elements = ["<Lock state=\"False\"></Lock>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<Zoom value=\"100\"></Zoom>"]
        case 166:
            elements = ["<Lock state=\"False\"></Lock>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<ShowHide value=\"Hide\"></ShowHide>"]
        case 92:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<ShowHide value=\"Show\"></ShowHide>"]
        case 29:
            elements = ["<IncludeEditRecordToolbar state=\"True\"></IncludeEditRecordToolbar>", "<Lock state=\"False\"></Lock>", "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<ShowHide value=\"Hide\"></ShowHide>"]
        case 30:
            elements = ["<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>", "<View value=\"Cycle\"></View>"]
        default:
            return nil
        }
        return elements.map { "  \($0)" }.joined(separator: "\n")
    }

    private func windowStep(id: Int, name: String, target: WindowTarget) -> String {
        switch target {
        case .current:
            let body = [
                "  <Window value=\"Current\"></Window>",
                "  <LimitToWindowsOfCurrentFile state=\"True\"></LimitToWindowsOfCurrentFile>"
            ].joined(separator: "\n")
            return stepElement(id: id, name: name, body: body)
        case .byName(let calculation, let currentFileOnly):
            let body = [
                "  <Window value=\"ByName\"></Window>",
                "  <LimitToWindowsOfCurrentFile state=\"\(currentFileOnly ? "True" : "False")\"></LimitToWindowsOfCurrentFile>",
                "  <Name>",
                "    <Calculation>\(cdata(calculation))</Calculation>",
                "  </Name>"
            ].joined(separator: "\n")
            return stepElement(id: id, name: name, body: body)
        }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func stepElement(id: Int, name: String, body: String) -> String {
        "  <Step enable=\"True\" id=\"\(id)\" name=\"\(escapeAttribute(name))\">\n\(body)\n  </Step>"
    }

    private func cdata(_ value: String) -> String {
        "<![CDATA[\(value.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>"))]]>"
    }

    private func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escapeXML(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
