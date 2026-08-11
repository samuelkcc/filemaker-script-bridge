import XCTest
@testable import FileMakerBridgeCore

final class FileMakerXMLCompilerTests: XCTestCase {
    private let compiler = FileMakerXMLCompiler()
    private let decompiler = FileMakerXMLDecompiler()

    func testExampleCompilesWithoutIssues() {
        let result = compiler.compile(ExampleScript.fileMaker26)

        XCTAssertTrue(result.canCopyToFileMaker)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.warningCount, 0)
        XCTAssertEqual(result.steps.count, 9)
        XCTAssertTrue(result.xml.contains("id=\"141\" name=\"Set Variable\""))
        XCTAssertTrue(result.xml.contains("id=\"68\" name=\"If\""))
        XCTAssertTrue(result.xml.contains("id=\"87\" name=\"Show Custom Dialog\""))
        XCTAssertTrue(result.xml.contains("id=\"103\" name=\"Exit Script\""))
    }

    func testWrappedStepIsJoinedWithoutBreakingFunctionSemicolons() {
        let source = """
        Set Variable [
            $payload ;
            Value: JSONSetElement ( "{}" ; [ "name" ; "Sam" ; JSONString ] )
        ]
        """

        let result = compiler.compile(source)

        XCTAssertEqual(result.logicalLines.count, 1)
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(result.xml.contains("JSONSetElement"))
        XCTAssertTrue(result.xml.contains("<Name>$payload</Name>"))
    }

    func testSetFieldUsesFileMakerClipboardShape() {
        let result = compiler.compile("Set Field [ Orders::Status ; \"Approved\" ]")

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(result.xml.contains("id=\"76\" name=\"Set Field\""))
        XCTAssertTrue(result.xml.contains("<Calculation><![CDATA[\"Approved\"]]></Calculation>"))
        XCTAssertTrue(result.xml.contains("<Field table=\"Orders\" id=\"0\" name=\"Status\"></Field>"))
    }

    func testGoToRecordVariantsUseNativeFileMakerClipboardShape() {
        let result = compiler.compile("""
        Go to Record/Request/Page [ First ]
        Go to Record/Request/Page [ Next ; Exit after last ]
        Go to Record/Request/Page [ By calculation: $sourceRecordNumber ]
        """)

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.steps.count, 3)
        XCTAssertEqual(result.xml.components(separatedBy: "id=\"16\"").count - 1, 3)
        XCTAssertTrue(result.xml.contains("<RowPageLocation value=\"First\"></RowPageLocation>"))
        XCTAssertTrue(result.xml.contains("<Exit state=\"True\"></Exit>"))
        XCTAssertTrue(result.xml.contains("<RowPageLocation value=\"Next\"></RowPageLocation>"))
        XCTAssertTrue(result.xml.contains("<NoInteract state=\"True\"></NoInteract>"))
        XCTAssertTrue(result.xml.contains("<RowPageLocation value=\"ByCalculation\"></RowPageLocation>"))
        XCTAssertTrue(result.xml.contains("<Calculation><![CDATA[$sourceRecordNumber]]></Calculation>"))
    }

    func testGoToRecordVariantsRoundTripToReadableText() {
        let source = """
        Go to Record/Request/Page [ Previous ; Exit after last ]
        Go to Record/Request/Page [ By calculation: Get ( RecordNumber ) + 2 ]
        """

        let imported = decompiler.decompile(compiler.compile(source).xml)

        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertTrue(imported.text.contains("Go to Record/Request/Page [ Previous ; Exit after last ]"))
        XCTAssertTrue(imported.text.contains("Go to Record/Request/Page [ By calculation: Get ( RecordNumber ) + 2 ]"))
    }

    func testDKApprovalWindowFindAndRecordStepsUseNativeClipboardShapes() {
        let source = """
        New Window [ Style: Document ; Name: $workWindow ; Using layout: “dk_approval_db_list” (dk_approval_db_list) ; Close: Yes ; Minimize: No ; Maximize: Yes ; Resize: Yes ; Menu Bar: Yes ; Dim parent window: No ; Toolbars: Yes ]
        Select Window [ Name: $sourceWindow ; Current file ]
        Close Window [ Current Window ]
        Revert Record/Request [ With dialog: Off ]
        Delete Record/Request [ With dialog: Off ]
        Enter Find Mode [ Pause: Off ]
        Perform Find [ ]
        """

        let result = compiler.compile(
            source,
            options: CompilationOptions(convertUnsupportedLinesToComments: false)
        )

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.warningCount, 0)
        XCTAssertEqual(result.steps.count, 7)
        XCTAssertTrue(result.xml.contains("id=\"122\" name=\"New Window\""))
        XCTAssertTrue(result.xml.contains("<Calculation><![CDATA[$workWindow]]></Calculation>"))
        XCTAssertTrue(result.xml.contains("<NewWndStyles Style=\"Document\" Close=\"Yes\" Minimize=\"No\" Maximize=\"Yes\" Resize=\"Yes\" MenuBar=\"Yes\" DimParentWindow=\"No\" Styles=\"0\"></NewWndStyles>"))
        XCTAssertTrue(result.xml.contains("<Layout name=\"dk_approval_db_list\" id=\"0\"></Layout>"))
        XCTAssertTrue(result.xml.contains("id=\"123\" name=\"Select Window\""))
        XCTAssertTrue(result.xml.contains("<Window value=\"ByName\"></Window>"))
        XCTAssertTrue(result.xml.contains("<LimitToWindowsOfCurrentFile state=\"True\"></LimitToWindowsOfCurrentFile>"))
        XCTAssertTrue(result.xml.contains("id=\"121\" name=\"Close Window\""))
        XCTAssertTrue(result.xml.contains("<Window value=\"Current\"></Window>"))
        XCTAssertTrue(result.xml.contains("id=\"51\" name=\"Revert Record/Request\""))
        XCTAssertTrue(result.xml.contains("id=\"9\" name=\"Delete Record/Request\""))
        XCTAssertEqual(result.xml.components(separatedBy: "<NoInteract state=\"True\"></NoInteract>").count - 1, 2)
        XCTAssertTrue(result.xml.contains("id=\"22\" name=\"Enter Find Mode\""))
        XCTAssertTrue(result.xml.contains("<Pause state=\"False\"></Pause>"))
        XCTAssertTrue(result.xml.contains("id=\"28\" name=\"Perform Find\""))
        XCTAssertTrue(result.xml.contains("<Restore state=\"False\"></Restore>"))
    }

    func testDKApprovalWindowFindAndRecordStepsRoundTrip() {
        let source = """
        New Window [ Style: Document ; Name: $workWindow ; Using layout: “dk_approval_db_list” (dk_approval_db_list) ; Close: Yes ; Minimize: No ; Maximize: Yes ; Resize: Yes ; Menu Bar: Yes ; Dim parent window: No ; Toolbars: Yes ]
        Select Window [ Name: $sourceWindow ; Current file ]
        Close Window [ Current Window ]
        Revert Record/Request [ With dialog: Off ]
        Delete Record/Request [ With dialog: Off ]
        Enter Find Mode [ Pause: Off ]
        Perform Find [ ]
        """

        let imported = decompiler.decompile(compiler.compile(source).xml)

        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertTrue(imported.text.contains("Using layout: \"dk_approval_db_list\""))
        XCTAssertTrue(imported.text.contains("Select Window [ Name: $sourceWindow ; Current file ]"))
        XCTAssertTrue(imported.text.contains("Close Window [ Current Window ]"))
        XCTAssertTrue(imported.text.contains("Revert Record/Request [ With dialog: Off ]"))
        XCTAssertTrue(imported.text.contains("Delete Record/Request [ With dialog: Off ]"))
        XCTAssertTrue(imported.text.contains("Enter Find Mode [ Pause: Off ]"))
        XCTAssertTrue(imported.text.contains("Perform Find [ ]"))
    }

    func testCustomDialogButtonsKeepLabelsAndCommitSettings() {
        let source = """
        Show Custom Dialog [ Title: "Create DK Price Approval?" ; Message: "Continue?" ; Default Button: “Cancel”, Commit: “No” ; Button 2: “Create”, Commit: “Yes” ]
        """

        let compiled = compiler.compile(source)
        let imported = decompiler.decompile(compiled.xml)

        XCTAssertEqual(compiled.errorCount, 0)
        XCTAssertTrue(compiled.xml.contains("<Button CommitState=\"False\">"))
        XCTAssertTrue(compiled.xml.contains("<Calculation><![CDATA[\"Cancel\"]]></Calculation>"))
        XCTAssertTrue(compiled.xml.contains("<Button CommitState=\"True\">"))
        XCTAssertTrue(compiled.xml.contains("<Calculation><![CDATA[\"Create\"]]></Calculation>"))
        XCTAssertTrue(imported.text.contains("Default Button: \"Cancel\", Commit: No"))
        XCTAssertTrue(imported.text.contains("Button 2: \"Create\", Commit: Yes"))
    }

    func testCommonAITextVariantsAreNormalizedSafely() {
        let source = """
        If [ $ready ]
        Show Custom Dialog [ Title: \"Continue?\" ; Message: \"Proceed\" ; Default Button: \"OK\" ; Commit: Yes ; Button 2: \"Cancel\" ; Commit: No ]
        Else [ ]
        Enter Find Mode [ ]
        End If
        """

        let result = compiler.compile(source, options: CompilationOptions(convertUnsupportedLinesToComments: false))

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.warningCount, 0)
        XCTAssertTrue(result.xml.contains("id=\"87\" name=\"Show Custom Dialog\""))
        XCTAssertTrue(result.xml.contains("<Button CommitState=\"True\">"))
        XCTAssertTrue(result.xml.contains("<Button CommitState=\"False\">"))
        XCTAssertTrue(result.xml.contains("id=\"69\" name=\"Else\""))
        XCTAssertTrue(result.xml.contains("id=\"22\" name=\"Enter Find Mode\""))
        XCTAssertTrue(result.xml.contains("<Pause state=\"False\"></Pause>"))
    }

    func testUnsupportedEditableStepExplainsItsUnmappedSyntax() {
        let result = compiler.compile("Enter Find Mode [ Pause: Maybe ]")

        XCTAssertEqual(result.warningCount, 1)
        XCTAssertTrue(result.issues[0].message.contains("Pause requires On or Off"))
    }

    func testExportRecordsExplainsWhyItsRichOptionsAreBlocked() {
        let result = compiler.compile("Export Records [ File Name: $path ; Field Order: TEST::test ]")

        XCTAssertEqual(result.warningCount, 1)
        XCTAssertTrue(result.issues[0].message.contains("output path"))
        XCTAssertTrue(result.issues[0].message.contains("field order"))
    }

    func testCapturedXLSXExportRecordsAndMailAttachmentRoundTrip() {
        let source = """
        Export Records [ With dialog: Off ; Create folders: On ; File: "file:temp/SCKC-Export.xlsx" ; Format: XLSX ; Character set: Unicode ; Use field names: Off ; Field order: TEST::test, TEST::number ]
        Send Mail [ Send via: E-Mail Client ; With dialog: Off ; Attachment: "file:temp/SCKC-Export.xlsx" ]
        """

        let compiled = compiler.compile(source, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        let imported = decompiler.decompile(compiled.xml)

        XCTAssertEqual(compiled.errorCount, 0)
        XCTAssertEqual(compiled.warningCount, 0)
        XCTAssertTrue(compiled.xml.contains("<Profile FieldDelimiter=\"&#09;\" IsPredefined=\"-1\" FieldNameRow=\"-1\" DataType=\"XLXE\"></Profile>"))
        XCTAssertTrue(compiled.xml.contains("<UniversalPathList>file:temp/SCKC-Export.xlsx</UniversalPathList>"))
        XCTAssertTrue(compiled.xml.contains("<AutoOpen state=\"False\"></AutoOpen>"))
        XCTAssertTrue(compiled.xml.contains("<ExportEntry><Field table=\"TEST\" id=\"0\" name=\"test\"></Field></ExportEntry>"))
        XCTAssertTrue(compiled.xml.contains("id=\"63\" name=\"Send Mail\""))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, source)
    }

    func testCapturedXLSXImportRecordsRoundTrip() {
        let source = "Import Records [ With dialog: Off ; File: \"file:temp/SCKC-Import.xlsx\" ; Format: XLSX ]"

        let compiled = compiler.compile(source, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        let imported = decompiler.decompile(compiled.xml)

        XCTAssertEqual(compiled.errorCount, 0)
        XCTAssertEqual(compiled.warningCount, 0)
        XCTAssertTrue(compiled.xml.contains("id=\"35\" name=\"Import Records\""))
        XCTAssertTrue(compiled.xml.contains("<DataSourceType value=\"File\"></DataSourceType>"))
        XCTAssertTrue(compiled.xml.contains("<Profile FileName=\"file:temp/SCKC-Import.xlsx\" WorksheetName=\"\" SelectedSheet=\"0\" FieldDelimiter=\"&#09;\" IsPredefined=\"-1\" FieldNameRow=\"-1\" DataType=\"XLSX\"></Profile>"))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, source)
    }

    func testImportRecordsUnsupportedNativeOptionsRemainPreserved() {
        let xml = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="35" name="Import Records"><NoInteract state="True"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore><VerifySSLCertificates state="False"></VerifySSLCertificates><DataSourceType value="File"></DataSourceType><Profile FileName="file:temp/SCKC-Import.xlsx" WorksheetName="Orders" SelectedSheet="1" FieldDelimiter="&#09;" IsPredefined="-1" FieldNameRow="-1" DataType="XLSX"></Profile><UniversalPathList>file:temp/SCKC-Import.xlsx</UniversalPathList></Step></fmxmlsnippet>
        """

        let imported = decompiler.decompile(xml)
        let recompiled = compiler.compile(imported.text, preservedSteps: imported.preservedSteps)

        XCTAssertEqual(imported.unsupportedStepCount, 1)
        XCTAssertEqual(recompiled.preservedStepCount, 1)
        XCTAssertTrue(recompiled.xml.contains("WorksheetName=\"Orders\""))
    }

    func testExportRecordsAndMailUnsupportedNativeOptionsRemainPreserved() {
        let xml = """
        <fmxmlsnippet type="FMObjectList">
          <Step enable="True" id="36" name="Export Records"><NoInteract state="True"></NoInteract><CreateDirectories state="True"></CreateDirectories><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="True"></Restore><AutoOpen state="True"></AutoOpen><CreateEmail state="False"></CreateEmail><Profile FieldDelimiter="&#09;" IsPredefined="-1" FieldNameRow="-1" DataType="XLXE"></Profile><UniversalPathList>file:temp/SCKC-Export.xlsx</UniversalPathList><UseFieldNames state="False"></UseFieldNames><ExportOptions FormatUsingCurrentLayout="False" CharacterSet="Unicode"></ExportOptions><ExportEntries><ExportEntry><Field table="TEST" id="8" name="test"></Field></ExportEntry></ExportEntries></Step>
          <Step enable="True" id="63" name="Send Mail"><NoInteract state="True"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed><Attachment><UniversalPathList>file:temp/SCKC-Export.xlsx</UniversalPathList></Attachment><MultipleEmails state="False"></MultipleEmails><SendViaSMTP state="False"></SendViaSMTP><SendViaOAuthAuthentication state="False"></SendViaOAuthAuthentication><SMTPEncryptionType type="SMTPEncryptionNone"></SMTPEncryptionType><SMTPAuthenticationType type="SMTPAuthenticationNone"></SMTPAuthenticationType><OAuthProvider type="OAuthProviderGoogle"></OAuthProvider><Subject><Calculation><![CDATA[\"Unexpected\"]]></Calculation></Subject></Step>
        </fmxmlsnippet>
        """

        let imported = decompiler.decompile(xml)
        let recompiled = compiler.compile(imported.text, preservedSteps: imported.preservedSteps)

        XCTAssertEqual(imported.unsupportedStepCount, 2)
        XCTAssertEqual(recompiled.preservedStepCount, 2)
        XCTAssertTrue(recompiled.xml.contains("<AutoOpen state=\"True\"></AutoOpen>"))
        XCTAssertTrue(recompiled.xml.contains("<Subject>"))
    }

    func testGoToLayoutRemovesCopiedContextSuffix() {
        let result = compiler.compile("Go to Layout [ “dk approval | form” (dk_approval_db_list) ]")

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(result.xml.contains("name=\"dk approval | form\""))
        XCTAssertFalse(result.xml.contains("(dk_approval_db_list)"))
    }

    func testBlankLinesAreOmittedFromFileMakerClipboard() {
        let source = "Beep\n\n\nHalt Script\n"

        let result = compiler.compile(source)

        XCTAssertEqual(result.steps.count, 2)
        XCTAssertFalse(result.xml.contains("<Text></Text>"))
    }

    func testUnsupportedLineBecomesVisibleCommentByDefault() {
        let result = compiler.compile("Send Mail [ completely unsupported options ]")

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.warningCount, 1)
        XCTAssertEqual(result.commentFallbackCount, 2)
        XCTAssertTrue(result.xml.contains("FileMaker Script Bridge TODO"))
        XCTAssertTrue(result.xml.contains("Send Mail in FileMaker. AI draft:"))
        XCTAssertTrue(result.canCopyToFileMaker)
    }

    func testUnsupportedLineCanBeBlocking() {
        let result = compiler.compile(
            "Send Mail [ completely unsupported options ]",
            options: CompilationOptions(convertUnsupportedLinesToComments: false)
        )

        XCTAssertEqual(result.errorCount, 1)
        XCTAssertTrue(result.steps.isEmpty)
        XCTAssertFalse(result.canCopyToFileMaker)
    }

    func testOfficialPreserveOnlyStepGetsSpecificBlockingGuidance() {
        let result = compiler.compile(
            "Set Next Serial Value [ TEST::id ; 100 ]",
            options: CompilationOptions(convertUnsupportedLinesToComments: false)
        )

        XCTAssertEqual(result.errorCount, 1)
        XCTAssertTrue(result.steps.isEmpty)
        XCTAssertTrue(result.issues.first?.message.contains("Official FileMaker step ‘Set Next Serial Value’") == true)
        XCTAssertTrue(result.issues.first?.message.contains("preserve-only") == true)
    }

    func testPerformScriptOnServerDoesNotMatchPerformScriptPrefix() {
        let result = compiler.compile(
            "Perform Script On Server [ \"Build Report\" ; Parameter: $payload ; Wait for completion: On ]",
            options: CompilationOptions(convertUnsupportedLinesToComments: false)
        )

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(result.xml.contains("id=\"164\" name=\"Perform Script on Server\""))
        XCTAssertTrue(result.xml.contains("WaitForCompletion state=\"True\""))
        XCTAssertTrue(result.xml.contains("name=\"Build Report\""))
        XCTAssertFalse(result.xml.contains("id=\"1\" name=\"Perform Script\""))
    }

    func testSampleFileAndRefreshStepsRoundTripAsEditableText() {
        let source = """
        Export Field Contents [ TEST::container ; “$fileName” ; Create folders: Yes ]
        Insert File [ Target: TEST::container ; “$filePath” ]
        Delete All Records [ With dialog: Off ]
        Refresh Object [ Object Name: "temp_download" ; Repetition: 1 ]
        Loop [ Flush: Always ]
        End Loop
        """

        let compiled = compiler.compile(
            source,
            options: CompilationOptions(convertUnsupportedLinesToComments: false)
        )
        let imported = decompiler.decompile(compiled.xml)

        XCTAssertEqual(compiled.errorCount, 0)
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertTrue(compiled.xml.contains("<UniversalPathList>$fileName</UniversalPathList>"))
        XCTAssertTrue(compiled.xml.contains("<UniversalPathList type=\"Embedded\">$filePath</UniversalPathList>"))
        XCTAssertTrue(imported.text.contains("Export Field Contents [ TEST::container ; \"$fileName\" ; Create folders: Yes ]"))
        XCTAssertTrue(imported.text.contains("Insert File [ Target: TEST::container ; \"$filePath\" ]"))
        XCTAssertTrue(imported.text.contains("Delete All Records [ With dialog: Off ]"))
        XCTAssertTrue(imported.text.contains("Refresh Object [ Object Name: \"temp_download\" ; Repetition: 1 ]"))
        XCTAssertTrue(imported.text.contains("Loop [ Flush: Always ]"))
    }

    func testNoDialogRecordAliasesUseNativeNoInteractShape() {
        let result = compiler.compile(
            "Revert Record/Request [ No dialog ]\nDelete All Records [ No dialog ]",
            options: CompilationOptions(convertUnsupportedLinesToComments: false)
        )

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.warningCount, 0)
        XCTAssertTrue(result.xml.contains("id=\"51\" name=\"Revert Record/Request\""))
        XCTAssertTrue(result.xml.contains("id=\"10\" name=\"Delete All Records\""))
        XCTAssertEqual(result.xml.components(separatedBy: "<NoInteract state=\"True\"></NoInteract>").count - 1, 2)
    }

    func testCapturedFileMakerFormattingCacheAndSystemStepsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="115" name="Allow Formatting Bar"><Set state="False"></Set><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="102" name="Flush Cache to Disk"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="237" name="Flush Web Viewer Cookies"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="44" name="Exit Application"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="174" name="Enable Touch Keyboard"><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Show"></ShowHide></Step><Step enable="True" id="94" name="Set Use System Formats"><Set state="True"></Set><DisableStepCollapsed state="False"></DisableStepCollapsed></Step></fmxmlsnippet>
        """
        let expectedText = """
        Allow Formatting Bar [ Off ]
        Flush Cache to Disk
        Flush Web Viewer Cookies
        Exit Application
        Enable Touch Keyboard [ On ]
        Set Use System Formats [ On ]
        """

        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(
            expectedText,
            options: CompilationOptions(convertUnsupportedLinesToComments: false)
        )
        let reimported = decompiler.decompile(rebuilt.xml)

        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(reimported.text, expectedText)
        XCTAssertTrue(rebuilt.xml.contains("id=\"115\" name=\"Allow Formatting Bar\""))
        XCTAssertTrue(rebuilt.xml.contains("<Set state=\"False\"></Set>"))
        XCTAssertTrue(rebuilt.xml.contains("id=\"102\" name=\"Flush Cache to Disk\""))
        XCTAssertTrue(rebuilt.xml.contains("id=\"237\" name=\"Flush Web Viewer Cookies\""))
        XCTAssertTrue(rebuilt.xml.contains("id=\"44\" name=\"Exit Application\""))
        XCTAssertTrue(rebuilt.xml.contains("id=\"174\" name=\"Enable Touch Keyboard\""))
        XCTAssertTrue(rebuilt.xml.contains("<ShowHide value=\"Show\"></ShowHide>"))
        XCTAssertTrue(rebuilt.xml.contains("id=\"94\" name=\"Set Use System Formats\""))
    }

    func testCapturedFileMakerOpenMenuStepsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="149" name="Open Edit Saved Finds"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="183" name="Open Favorites"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="114" name="Open File Options"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="129" name="Open Find/Replace"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="32" name="Open Help"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="118" name="Open Hosts"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="156" name="Open Manage Containers"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="140" name="Open Manage Data Sources"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="38" name="Open Manage Database"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="151" name="Open Manage Layouts"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="165" name="Open Manage Themes"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="112" name="Open Manage Value Lists"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="105" name="Open Settings"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="113" name="Open Sharing"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="172" name="Open Upload to Host"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step></fmxmlsnippet>
        """
        let expectedText = """
        Open Edit Saved Finds
        Open Favorites
        Open File Options
        Open Find/Replace
        Open Help
        Open Hosts
        Open Manage Containers
        Open Manage Data Sources
        Open Manage Database
        Open Manage Layouts
        Open Manage Themes
        Open Manage Value Lists
        Open Settings
        Open Sharing
        Open Upload to Host
        """

        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        let reimported = decompiler.decompile(rebuilt.xml)

        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(reimported.text, expectedText)
        XCTAssertEqual(rebuilt.xml.components(separatedBy: "<DisableStepCollapsed state=\"False\"></DisableStepCollapsed>").count - 1, 15)
        XCTAssertTrue(rebuilt.xml.contains("id=\"149\" name=\"Open Edit Saved Finds\""))
        XCTAssertTrue(rebuilt.xml.contains("id=\"172\" name=\"Open Upload to Host\""))
    }

    func testCapturedPriorityRecordFoundSetAndWindowDefaultsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="98" name="Copy All Records/Requests"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="101" name="Copy Record/Request"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="104" name="Delete Portal Row"><NoInteract state="False"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="8" name="Duplicate Record/Request"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="36" name="Export Records"><NoInteract state="True"></NoInteract><CreateDirectories state="True"></CreateDirectories><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore><AutoOpen state="False"></AutoOpen><CreateEmail state="False"></CreateEmail></Step><Step enable="True" id="35" name="Import Records"><NoInteract state="True"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore><VerifySSLCertificates state="False"></VerifySSLCertificates></Step><Step enable="True" id="133" name="Open Record/Request"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="143" name="Save Records as Excel"><NoInteract state="True"></NoInteract><CreateDirectories state="True"></CreateDirectories><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore><AutoOpen state="False"></AutoOpen><CreateEmail state="False"></CreateEmail><SaveType value="BrowsedRecords"></SaveType><UseFieldNames state="False"></UseFieldNames></Step><Step enable="True" id="225" name="Save Records as JSONL"><Option state="False"></Option><CreateDirectories state="False"></CreateDirectories><FineTuneFormat state="False"></FineTuneFormat><DisableStepCollapsed state="False"></DisableStepCollapsed><AutoOpen state="False"></AutoOpen><CreateEmail state="False"></CreateEmail><SaveAsJSONL></SaveAsJSONL></Step><Step enable="True" id="152" name="Save Records as Snapshot Link"><CreateDirectories state="True"></CreateDirectories><DisableStepCollapsed state="False"></DisableStepCollapsed><CreateEmail state="False"></CreateEmail><SaveType value="BrowsedRecords"></SaveType></Step><Step enable="True" id="182" name="Truncate Table"><NoInteract state="False"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed><BaseTable id="-1" name="&lt;Current Table&gt;"></BaseTable></Step><Step enable="True" id="126" name="Constrain Found Set"><Option state="False"></Option><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore></Step><Step enable="True" id="127" name="Extend Found Set"><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore></Step><Step enable="True" id="155" name="Find Matching Records"><DisableStepCollapsed state="False"></DisableStepCollapsed><FindMatchingRecordsByField value="FindMatchingReplace"></FindMatchingRecordsByField></Step><Step enable="True" id="24" name="Modify Last Find"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="26" name="Omit Multiple Records"><NoInteract state="True"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="25" name="Omit Record"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="150" name="Perform Quick Find"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="27" name="Show Omitted Only"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="39" name="Sort Records"><NoInteract state="True"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore></Step><Step enable="True" id="154" name="Sort Records by Field"><DisableStepCollapsed state="False"></DisableStepCollapsed><SortRecordsByField value="SortAscending"></SortRecordsByField></Step><Step enable="True" id="21" name="Unsort Records"><DisableStepCollapsed state="False"></DisableStepCollapsed></Step><Step enable="True" id="31" name="Adjust Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowState value="ResizeToFit"></WindowState></Step><Step enable="True" id="120" name="Arrange All Windows"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowArrangement value="TileHorizontally"></WindowArrangement></Step><Step enable="True" id="119" name="Move/Resize Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><LimitToWindowsOfCurrentFile state="True"></LimitToWindowsOfCurrentFile><Window value="Current"></Window></Step><Step enable="True" id="81" name="Scroll Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><ScrollOperation value="Home"></ScrollOperation></Step><Step enable="True" id="124" name="Set Window Title"><DisableStepCollapsed state="False"></DisableStepCollapsed><LimitToWindowsOfCurrentFile state="True"></LimitToWindowsOfCurrentFile><Window value="Current"></Window></Step><Step enable="True" id="97" name="Set Zoom Level"><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><Zoom value="100"></Zoom></Step><Step enable="True" id="166" name="Show/Hide Menubar"><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Hide"></ShowHide></Step><Step enable="True" id="92" name="Show/Hide Text Ruler"><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Show"></ShowHide></Step><Step enable="True" id="29" name="Show/Hide Toolbars"><IncludeEditRecordToolbar state="True"></IncludeEditRecordToolbar><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Hide"></ShowHide></Step><Step enable="True" id="30" name="View As"><DisableStepCollapsed state="False"></DisableStepCollapsed><View value="Cycle"></View></Step></fmxmlsnippet>
        """
        let expectedText = """
        Copy All Records/Requests
        Copy Record/Request
        Delete Portal Row
        Duplicate Record/Request
        Export Records
        Import Records
        Open Record/Request
        Save Records as Excel
        Save Records as JSONL
        Save Records as Snapshot Link
        Truncate Table
        Constrain Found Set [ Find without indexes: Off ]
        Extend Found Set
        Find Matching Records [ Replace ]
        Modify Last Find
        Omit Multiple Records [ With dialog: Off ]
        Omit Record
        Perform Quick Find
        Show Omitted Only
        Sort Records [ With dialog: Off ]
        Sort Records by Field [ Ascending ]
        Unsort Records
        Adjust Window [ Resize to Fit ]
        Arrange All Windows [ Tile Horizontally ]
        Move/Resize Window [ Current Window ]
        Scroll Window [ Home ]
        Set Window Title [ Current Window ]
        Set Zoom Level [ 100% ; Lock: Off ]
        Show/Hide Menubar [ Hide ; Lock: Off ]
        Show/Hide Text Ruler [ Show ]
        Show/Hide Toolbars [ Hide ; Lock: Off ; Include Edit Record Toolbar: On ]
        View As [ Cycle ]
        """

        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        let reimported = decompiler.decompile(rebuilt.xml)

        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(reimported.text, expectedText)
        XCTAssertTrue(rebuilt.xml.contains("id=\"126\" name=\"Constrain Found Set\""))
        XCTAssertTrue(rebuilt.xml.contains("id=\"182\" name=\"Truncate Table\""))
        XCTAssertTrue(rebuilt.xml.contains("id=\"119\" name=\"Move/Resize Window\""))
    }

    func testCapturedSaveRecordsAsExcelProfileRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="143" name="Save Records as Excel"><NoInteract state="True"></NoInteract><CreateDirectories state="True"></CreateDirectories><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore><AutoOpen state="False"></AutoOpen><CreateEmail state="False"></CreateEmail><Profile FieldDelimiter="&#09;" IsPredefined="-1" FieldNameRow="-1" DataType="XLXE"></Profile><UniversalPathList>file:temp/SCKC-Records.xlsx</UniversalPathList><SaveType value="BrowsedRecords"></SaveType><UseFieldNames state="False"></UseFieldNames></Step></fmxmlsnippet>
        """
        let text = "Save Records as Excel [ With dialog: Off ; File: \"file:temp/SCKC-Records.xlsx\" ; Records being browsed ; Create folders: On ; Use field names: Off ]"
        let decompiler = FileMakerXMLDecompiler()
        let compiler = FileMakerXMLCompiler()

        XCTAssertEqual(decompiler.decompile(capturedXML).text, text)
        let compiled = compiler.compile(text, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(compiled.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(compiled.xml).text, text)
        XCTAssertTrue(compiled.xml.contains("DataType=\"XLXE\""))
    }

    func testCapturedAdjustWindowOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="31" name="Adjust Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowState value="Maximize"></WindowState></Step><Step enable="True" id="31" name="Adjust Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowState value="ResizeToFit"></WindowState></Step><Step enable="True" id="31" name="Adjust Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowState value="Minimize"></WindowState></Step><Step enable="True" id="31" name="Adjust Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowState value="Restore"></WindowState></Step><Step enable="True" id="31" name="Adjust Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowState value="Hide"></WindowState></Step></fmxmlsnippet>
        """
        let expectedText = """
        Adjust Window [ Maximize ]
        Adjust Window [ Resize to Fit ]
        Adjust Window [ Minimize ]
        Adjust Window [ Restore ]
        Adjust Window [ Hide ]
        """

        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        let reimported = decompiler.decompile(rebuilt.xml)

        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(reimported.text, expectedText)
    }

    func testCapturedArrangeAllWindowsOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="120" name="Arrange All Windows"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowArrangement value="TileVertically"></WindowArrangement></Step><Step enable="True" id="120" name="Arrange All Windows"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowArrangement value="TileHorizontally"></WindowArrangement></Step><Step enable="True" id="120" name="Arrange All Windows"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowArrangement value="Cascade"></WindowArrangement></Step><Step enable="True" id="120" name="Arrange All Windows"><DisableStepCollapsed state="False"></DisableStepCollapsed><WindowArrangement value="BringAllToFront"></WindowArrangement></Step></fmxmlsnippet>
        """
        let expectedText = """
        Arrange All Windows [ Tile Vertically ]
        Arrange All Windows [ Tile Horizontally ]
        Arrange All Windows [ Cascade ]
        Arrange All Windows [ Bring All to Front ]
        """

        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedViewAndScrollWindowOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="30" name="View As"><DisableStepCollapsed state="False"></DisableStepCollapsed><View value="Form"></View></Step><Step enable="True" id="30" name="View As"><DisableStepCollapsed state="False"></DisableStepCollapsed><View value="Cycle"></View></Step><Step enable="True" id="30" name="View As"><DisableStepCollapsed state="False"></DisableStepCollapsed><View value="List"></View></Step><Step enable="True" id="30" name="View As"><DisableStepCollapsed state="False"></DisableStepCollapsed><View value="Table"></View></Step><Step enable="True" id="81" name="Scroll Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><ScrollOperation value="End"></ScrollOperation></Step><Step enable="True" id="81" name="Scroll Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><ScrollOperation value="Home"></ScrollOperation></Step><Step enable="True" id="81" name="Scroll Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><ScrollOperation value="PageUp"></ScrollOperation></Step><Step enable="True" id="81" name="Scroll Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><ScrollOperation value="PageDown"></ScrollOperation></Step><Step enable="True" id="81" name="Scroll Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><ScrollOperation value="ToSelection"></ScrollOperation></Step></fmxmlsnippet>
        """
        let expectedText = """
        View As [ Form ]
        View As [ Cycle ]
        View As [ List ]
        View As [ Table ]
        Scroll Window [ End ]
        Scroll Window [ Home ]
        Scroll Window [ Page Up ]
        Scroll Window [ Page Down ]
        Scroll Window [ To Selection ]
        """
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedShowHideTextRulerOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="92" name="Show/Hide Text Ruler"><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Show"></ShowHide></Step><Step enable="True" id="92" name="Show/Hide Text Ruler"><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Hide"></ShowHide></Step><Step enable="True" id="92" name="Show/Hide Text Ruler"><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Toggle"></ShowHide></Step></fmxmlsnippet>
        """
        let expectedText = """
        Show/Hide Text Ruler [ Show ]
        Show/Hide Text Ruler [ Hide ]
        Show/Hide Text Ruler [ Toggle ]
        """
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedMenubarAndToolbarOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="166" name="Show/Hide Menubar"><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Hide"></ShowHide></Step><Step enable="True" id="166" name="Show/Hide Menubar"><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Show"></ShowHide></Step><Step enable="True" id="166" name="Show/Hide Menubar"><Lock state="True"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Toggle"></ShowHide></Step><Step enable="True" id="29" name="Show/Hide Toolbars"><IncludeEditRecordToolbar state="True"></IncludeEditRecordToolbar><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Hide"></ShowHide></Step><Step enable="True" id="29" name="Show/Hide Toolbars"><IncludeEditRecordToolbar state="False"></IncludeEditRecordToolbar><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Show"></ShowHide></Step><Step enable="True" id="29" name="Show/Hide Toolbars"><IncludeEditRecordToolbar state="True"></IncludeEditRecordToolbar><Lock state="True"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><ShowHide value="Toggle"></ShowHide></Step></fmxmlsnippet>
        """
        let expectedText = """
        Show/Hide Menubar [ Hide ; Lock: Off ]
        Show/Hide Menubar [ Show ; Lock: Off ]
        Show/Hide Menubar [ Toggle ; Lock: On ]
        Show/Hide Toolbars [ Hide ; Lock: Off ; Include Edit Record Toolbar: On ]
        Show/Hide Toolbars [ Show ; Lock: Off ; Include Edit Record Toolbar: Off ]
        Show/Hide Toolbars [ Toggle ; Lock: On ; Include Edit Record Toolbar: On ]
        """
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedZoomLevelOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="97" name="Set Zoom Level"><Lock state="True"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><Zoom value="25"></Zoom></Step><Step enable="True" id="97" name="Set Zoom Level"><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><Zoom value="ZoomIn"></Zoom></Step><Step enable="True" id="97" name="Set Zoom Level"><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><Zoom value="ZoomOut"></Zoom></Step><Step enable="True" id="97" name="Set Zoom Level"><Lock state="False"></Lock><DisableStepCollapsed state="False"></DisableStepCollapsed><Zoom value="ByCalculation"></Zoom><Calculation><![CDATA[125]]></Calculation></Step></fmxmlsnippet>
        """
        let expectedText = """
        Set Zoom Level [ 25% ; Lock: On ]
        Set Zoom Level [ Zoom In ; Lock: Off ]
        Set Zoom Level [ Zoom Out ; Lock: Off ]
        Set Zoom Level [ Custom: 125 ; Lock: Off ]
        """
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedMoveResizeWindowOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="119" name="Move/Resize Window"><DisableStepCollapsed state="False"></DisableStepCollapsed><LimitToWindowsOfCurrentFile state="True"></LimitToWindowsOfCurrentFile><Window value="ByName"></Window><Name><Calculation><![CDATA[$windowName]]></Calculation></Name><Height><Calculation><![CDATA[600]]></Calculation></Height><Width><Calculation><![CDATA[800]]></Calculation></Width><DistanceFromTop><Calculation><![CDATA[40]]></Calculation></DistanceFromTop><DistanceFromLeft><Calculation><![CDATA[50]]></Calculation></DistanceFromLeft></Step></fmxmlsnippet>
        """
        let expectedText = "Move/Resize Window [ Name: $windowName ; Current file ; Height: 600 ; Width: 800 ; Top: 40 ; Left: 50 ]"
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedSetWindowTitleOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="124" name="Set Window Title"><DisableStepCollapsed state="False"></DisableStepCollapsed><LimitToWindowsOfCurrentFile state="True"></LimitToWindowsOfCurrentFile><Window value="ByName"></Window><Name><Calculation><![CDATA[$windowName]]></Calculation></Name><NewName><Calculation><![CDATA[$title]]></Calculation></NewName></Step></fmxmlsnippet>
        """
        let expectedText = "Set Window Title [ Name: $windowName ; Current file ; New title: $title ]"
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedFindMatchingRecordsOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="155" name="Find Matching Records"><DisableStepCollapsed state="False"></DisableStepCollapsed><FindMatchingRecordsByField value="FindMatchingReplace"></FindMatchingRecordsByField><Field table="TEST" id="8" name="test"></Field></Step><Step enable="True" id="155" name="Find Matching Records"><DisableStepCollapsed state="False"></DisableStepCollapsed><FindMatchingRecordsByField value="FindMatchingConstrain"></FindMatchingRecordsByField></Step><Step enable="True" id="155" name="Find Matching Records"><DisableStepCollapsed state="False"></DisableStepCollapsed><FindMatchingRecordsByField value="FindMatchingExtend"></FindMatchingRecordsByField></Step></fmxmlsnippet>
        """
        let expectedText = """
        Find Matching Records [ Replace ; Target: TEST::test ]
        Find Matching Records [ Constrain ]
        Find Matching Records [ Extend ]
        """
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedPerformQuickFindCalculationRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="150" name="Perform Quick Find"><DisableStepCollapsed state="False"></DisableStepCollapsed><Calculation><![CDATA[$query]]></Calculation></Step></fmxmlsnippet>
        """
        let expectedText = "Perform Quick Find [ $query ]"
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedSortRecordsByFieldOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="154" name="Sort Records by Field"><DisableStepCollapsed state="False"></DisableStepCollapsed><SortRecordsByField value="SortAscending"></SortRecordsByField></Step><Step enable="True" id="154" name="Sort Records by Field"><DisableStepCollapsed state="False"></DisableStepCollapsed><SortRecordsByField value="SortDescending"></SortRecordsByField></Step><Step enable="True" id="154" name="Sort Records by Field"><DisableStepCollapsed state="False"></DisableStepCollapsed><SortRecordsByField value="SortValueList"></SortRecordsByField></Step></fmxmlsnippet>
        """
        let expectedText = """
        Sort Records by Field [ Ascending ]
        Sort Records by Field [ Descending ]
        Sort Records by Field [ Associated value list ]
        """
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedConstrainAndOmitMultipleOptionsRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="126" name="Constrain Found Set"><Option state="True"></Option><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore></Step><Step enable="True" id="26" name="Omit Multiple Records"><NoInteract state="False"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed><Calculation><![CDATA[5]]></Calculation></Step></fmxmlsnippet>
        """
        let expectedText = """
        Constrain Found Set [ Find without indexes: On ]
        Omit Multiple Records [ With dialog: On ; Records: 5 ]
        """
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedSortRecordsDialogOptionRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="39" name="Sort Records"><NoInteract state="False"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="False"></Restore></Step></fmxmlsnippet>
        """
        let expectedText = "Sort Records [ With dialog: On ]"
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testCapturedStoredSortListRoundTrip() {
        let capturedXML = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="39" name="Sort Records"><NoInteract state="False"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="True"></Restore><SortList BlanksLast="True" Maintain="False" value="True"><Sort type="Ascending"><PrimaryField><Field table="TEST" id="8" name="test"></Field></PrimaryField></Sort><Sort type="Descending"><PrimaryField><Field table="TEST" id="9" name="number"></Field></PrimaryField></Sort></SortList></Step></fmxmlsnippet>
        """
        let expectedText = "Sort Records [ With dialog: On ; Blanks last: On ; Keep records sorted: Off ; TEST::test Ascending ; TEST::number Descending ]"
        let imported = decompiler.decompile(capturedXML)
        let rebuilt = compiler.compile(expectedText, options: CompilationOptions(convertUnsupportedLinesToComments: false))

        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(imported.text, expectedText)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertTrue(rebuilt.xml.contains("<SortList BlanksLast=\"True\" Maintain=\"False\" value=\"True\">"))
        XCTAssertTrue(rebuilt.xml.contains("<Sort type=\"Descending\">"))
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, expectedText)
    }

    func testUnsupportedStoredSortListRemainsPreserveOnly() {
        let xml = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="39" name="Sort Records"><NoInteract state="True"></NoInteract><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="True"></Restore><SortList BlanksLast="False" Maintain="True" value="True"><Sort type="Custom"><PrimaryField><Field table="TEST" id="8" name="test"></Field></PrimaryField></Sort></SortList></Step></fmxmlsnippet>
        """

        let imported = decompiler.decompile(xml)

        XCTAssertEqual(imported.unsupportedStepCount, 1)
        XCTAssertTrue(imported.text.contains("FileMaker step preserved unchanged: Sort Records"))
    }

    func testReferencedScriptIsNotReportedAsClipboardScriptTitle() {
        let xml = """
        <fmxmlsnippet type="FMObjectList">
          <Step enable="True" id="164" name="Perform Script on Server">
            <WaitForCompletion state="True"></WaitForCompletion>
            <Calculation><![CDATA[$serverParameter]]></Calculation>
            <Script id="1" name="New Script"></Script>
          </Step>
        </fmxmlsnippet>
        """

        let imported = decompiler.decompile(xml)

        XCTAssertTrue(imported.scriptNames.isEmpty)
        XCTAssertFalse(imported.text.contains("# FileMaker Script:"))
        XCTAssertTrue(imported.text.contains("Perform Script on Server [ \"New Script\""))
    }

    func testUnmappedFileOptionsRemainPreserveOnly() {
        let xml = """
        <fmxmlsnippet type="FMObjectList">
          <Step enable="True" id="132" name="Export Field Contents">
            <CreateDirectories state="True"></CreateDirectories>
            <AutoOpen state="True"></AutoOpen>
            <CreateEmail state="False"></CreateEmail>
            <UniversalPathList>$fileName</UniversalPathList>
            <Field table="TEST" id="11" name="container"></Field>
          </Step>
        </fmxmlsnippet>
        """

        let imported = decompiler.decompile(xml)

        XCTAssertEqual(imported.unsupportedStepCount, 1)
        XCTAssertTrue(imported.text.contains("FileMaker step preserved unchanged: Export Field Contents"))
    }

    func testOfficialCatalogueMatchesAuditedClarisReference() {
        XCTAssertEqual(FileMakerScriptStepCatalog.entries.count, 216)
        XCTAssertEqual(FileMakerScriptStepCatalog.categories.count, 14)
        XCTAssertEqual(FileMakerScriptStepCatalog.editableSubsetCount, 92)
        XCTAssertEqual(Set(FileMakerScriptStepCatalog.entries.map(\.id)).count, 216)

        XCTAssertEqual(
            FileMakerScriptStepCatalog.officialStep(matching: "Constrain Found Set [ Restore ]")?.support,
            .editableSubset
        )
        XCTAssertEqual(
            FileMakerScriptStepCatalog.officialStep(matching: "Set Variable [ $x ; Value: 1 ]")?.support,
            .editableSubset
        )
        XCTAssertEqual(
            FileMakerScriptStepCatalog.officialStep(matching: "Go to Record/Request/Page [ First ]")?.support,
            .editableSubset
        )
        XCTAssertEqual(
            FileMakerScriptStepCatalog.officialStep(matching: "New Window [ Style: Document ]")?.support,
            .editableSubset
        )
        XCTAssertEqual(
            FileMakerScriptStepCatalog.officialStep(matching: "Enable Touch Keyboard [ On ]")?.support,
            .editableSubset
        )
    }

    func testPreserveOnlyAIAccountStepBecomesPasteableCompletionTemplate() {
        let result = compiler.compile("Configure AI Account [ Provider: OpenAI ; Account: production ]")

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.warningCount, 1)
        XCTAssertEqual(result.commentFallbackCount, 2)
        XCTAssertTrue(result.xml.contains("FileMaker Script Bridge TODO"))
        XCTAssertTrue(result.xml.contains("Configure AI Account in FileMaker. AI draft:"))
        XCTAssertTrue(result.xml.contains("AI draft: Configure AI Account"))
    }

    func testUnclosedControlBlockBlocksCopy() {
        let result = compiler.compile("""
        If [ $ready ]
        Set Variable [ $status ; Value: "ready" ]
        """)

        XCTAssertEqual(result.errorCount, 1)
        XCTAssertFalse(result.canCopyToFileMaker)
        XCTAssertEqual(result.issues.first?.line, 1)
        XCTAssertTrue(result.issues.first?.message.contains("Missing End If") == true)
    }

    func testUnmatchedEndLoopBlocksCopy() {
        let result = compiler.compile("End Loop")

        XCTAssertEqual(result.errorCount, 1)
        XCTAssertFalse(result.canCopyToFileMaker)
    }

    func testCDATAIsSafelySplit() {
        let result = compiler.compile("Set Variable [ $x ; Value: \"a]]>b\" ]")

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(result.xml.contains("]]]]><![CDATA[>"))
    }

    func testSmartQuotesAreAcceptedForObjectNames() {
        let result = compiler.compile("""
        Go to Layout [ “Order Detail” ]
        Perform Script [ “Refresh Order” ; Parameter: $id ]
        """)

        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(result.xml.contains("name=\"Order Detail\""))
        XCTAssertTrue(result.xml.contains("name=\"Refresh Order\""))
        XCTAssertTrue(result.xml.contains("<![CDATA[$id]]>"))
    }

    func testGeneratedExampleRoundTripsToReadableText() {
        let compiled = compiler.compile(ExampleScript.fileMaker26)
        let decompiled = decompiler.decompile(compiled.xml)

        XCTAssertTrue(decompiled.isSuccessful)
        XCTAssertEqual(decompiled.stepCount, 9)
        XCTAssertEqual(decompiled.unsupportedStepCount, 0)
        XCTAssertTrue(decompiled.text.contains("Set Variable [ $orderTotal ; Value: Sum ( LineItems::amount ) ]"))
        XCTAssertTrue(decompiled.text.contains("    Show Custom Dialog [ Title: \"Order review\" ; Message: $status ; Default Button: \"OK\", Commit: Yes ]"))
        XCTAssertTrue(decompiled.text.contains("Exit Script [ Text Result: $status ]"))
    }

    func testWholeScriptClipboardIncludesScriptName() {
        let xml = """
        <fmxmlsnippet type="FMObjectList">
          <Script id="12" name="Approve Order">
            <Step enable="True" id="93" name="Beep"></Step>
            <Step enable="True" id="103" name="Exit Script"></Step>
          </Script>
        </fmxmlsnippet>
        """

        let result = decompiler.decompile(xml)

        XCTAssertEqual(result.scriptNames, ["Approve Order"])
        XCTAssertEqual(result.stepCount, 2)
        XCTAssertTrue(result.text.hasPrefix("# FileMaker Script: Approve Order"))
        XCTAssertTrue(result.text.contains("Beep\nExit Script"))
    }

    func testUnknownStepUsesStepTextForAIReview() {
        let xml = """
        <fmxmlsnippet type="FMObjectList">
          <Step enable="True" id="63" name="Send Mail">
            <StepText>Send Mail [ Send via E-mail Client ; To: $address ]</StepText>
          </Step>
        </fmxmlsnippet>
        """

        let result = decompiler.decompile(xml)

        XCTAssertEqual(result.stepCount, 1)
        XCTAssertEqual(result.unsupportedStepCount, 1)
        XCTAssertTrue(result.text.contains("FileMaker step preserved unchanged: Send Mail"))
        XCTAssertTrue(result.text.contains("[SCKC-P1-ID63]"))
        XCTAssertEqual(result.preservedSteps.count, 1)
    }

    func testUnknownImportedStepRoundTripsWithOriginalXML() {
        let xml = """
        <fmxmlsnippet type="FMObjectList">
          <Step enable="True" id="126" name="Constrain Found Set">
            <Restore state="True"></Restore>
            <Calculation><![CDATA[parts_db::nav_status = ""]]></Calculation>
          </Step>
        </fmxmlsnippet>
        """

        let imported = decompiler.decompile(xml)
        let rebuilt = compiler.compile(imported.text, preservedSteps: imported.preservedSteps)

        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(rebuilt.preservedStepCount, 1)
        XCTAssertTrue(rebuilt.canCopyToFileMaker)
        XCTAssertTrue(rebuilt.xml.contains("id=\"126\""))
        XCTAssertTrue(rebuilt.xml.contains("name=\"Constrain Found Set\""))
        XCTAssertTrue(rebuilt.xml.contains("parts_db::nav_status = \"\""))
    }

    func testPreservedMarkerWithoutSessionXMLBlocksExport() {
        let result = compiler.compile(
            "# ↔ FileMaker step preserved unchanged: Export Records (ID 36) [SCKC-P1-ID36] — options locked"
        )

        XCTAssertEqual(result.errorCount, 1)
        XCTAssertFalse(result.canCopyToFileMaker)
        XCTAssertTrue(result.issues.first?.message.contains("Re-copy and read") == true)
    }

    func testSuppliedSampleUnsupportedStepFamiliesRoundTripUnchanged() {
        let xml = """
        <fmxmlsnippet type="FMObjectList">
          <Step enable="True" id="126" name="Constrain Found Set"><Restore state="True"></Restore></Step>
          <Step enable="True" id="39" name="Sort Records"><Restore state="True"></Restore></Step>
          <Step enable="True" id="36" name="Export Records"><NoInteract state="True"></NoInteract></Step>
          <Step enable="True" id="36" name="Export Records"><NoInteract state="True"></NoInteract></Step>
          <Step enable="True" id="36" name="Export Records"><NoInteract state="True"></NoInteract></Step>
          <Step enable="True" id="36" name="Export Records"><NoInteract state="True"></NoInteract></Step>
          <Step enable="True" id="122" name="New Window"><Layout id="7" name="template download"></Layout></Step>
          <Step enable="True" id="132" name="Export Field Contents"><Field table="file_download" id="8" name="johnny_approval_template"></Field></Step>
          <Step enable="True" id="121" name="Close Window"></Step>
        </fmxmlsnippet>
        """

        let imported = decompiler.decompile(xml)
        let rebuilt = compiler.compile(imported.text, preservedSteps: imported.preservedSteps)

        XCTAssertEqual(imported.unsupportedStepCount, 8)
        XCTAssertEqual(imported.preservedSteps.count, 8)
        XCTAssertEqual(rebuilt.preservedStepCount, 8)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertTrue(rebuilt.canCopyToFileMaker)
        for id in [126, 39, 36, 122, 132, 121] {
            XCTAssertTrue(rebuilt.xml.contains("id=\"\(id)\""))
        }
        XCTAssertTrue(rebuilt.xml.contains("name=\"template download\""))
        XCTAssertTrue(rebuilt.xml.contains("name=\"johnny_approval_template\""))
    }

    func testMalformedClipboardXMLReturnsWarning() {
        let result = decompiler.decompile("<fmxmlsnippet><Step></fmxmlsnippet>")

        XCTAssertFalse(result.isSuccessful)
        XCTAssertEqual(result.stepCount, 0)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testReviewMarkersRemainDetectableAfterAIClipboardRoundTrip() {
        let source = """
        # ▶︎ Unsupported FileMaker step: Constrain Found Set (ID 126)
        # ▶︎ Unsupported FileMaker step: Sort Records (ID 39)
        # ▶︎ Unsupported FileMaker step: Export Records (ID 36)
        # ▶︎ Unsupported FileMaker step: Export Records (ID 36)
        # ▶︎ Unsupported FileMaker step: Export Records (ID 36)
        # ▶︎ Unsupported FileMaker step: Export Records (ID 36)
        # ▶︎ Unsupported FileMaker step: New Window (ID 122)
        # ▶︎ Unsupported FileMaker step: Export Field Contents (ID 132)
        # ▶︎ Unsupported FileMaker step: Close Window (ID 121)
        Set Variable [ $note ; Value: "▶︎ Unsupported is ordinary text here" ]
        """

        XCTAssertEqual(ReviewMarkerDetector.count(in: source), 9)
    }
}
