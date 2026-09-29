import XCTest
@testable import FileMakerBridgeCore

final class ExportAndReadStepTests: XCTestCase {
    let compiler = FileMakerXMLCompiler()
    let decompiler = FileMakerXMLDecompiler()

    // Captured from FileMaker Pro on 2026-09-29. No scripts were executed.
    let exportCapture = """
    <fmxmlsnippet type="FMObjectList"><Step enable="True" id="36" name="Export Records"><NoInteract state="True"></NoInteract><CreateDirectories state="True"></CreateDirectories><DisableStepCollapsed state="False"></DisableStepCollapsed><Restore state="True"></Restore><AutoOpen state="False"></AutoOpen><CreateEmail state="False"></CreateEmail><Profile FieldDelimiter="&#09;" IsPredefined="-1" FieldNameRow="-1" DataType="XLXE"></Profile><UniversalPathList>$dkUnitPriceFilePath</UniversalPathList><WorkSheet><Calculation><![CDATA["DK UNIT PRICE"]]></Calculation></WorkSheet><UseFieldNames state="False"></UseFieldNames><ExportOptions FormatUsingCurrentLayout="False" CharacterSet="Unicode"></ExportOptions><ExportEntries><ExportEntry><Field table="dk_approval_db_price" id="11" name="Veste Part"></Field></ExportEntry><ExportEntry><Field table="dk_approval_db_price" id="16" name="DK Bible Price"></Field></ExportEntry></ExportEntries></Step></fmxmlsnippet>
    """
    let readCapture = """
    <fmxmlsnippet type="FMObjectList"><Step enable="True" id="193" name="Read from Data File"><DisableStepCollapsed state="False"></DisableStepCollapsed><DataSourceType value="3"></DataSourceType><Calculation><![CDATA[$fileID]]></Calculation><Text></Text><Field>$data</Field></Step></fmxmlsnippet>
    """

    func compact(_ xml: String) -> String {
        xml.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
    }

    func testNativeWorksheetExportRebuildsEverySetting() {
        let imported = decompiler.decompile(exportCapture)
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertTrue(imported.text.contains("Worksheet: \"DK UNIT PRICE\""))
        XCTAssertTrue(imported.text.contains("Use field names: Off"))
        let rebuilt = compiler.compile(imported.text)
        XCTAssertEqual(rebuilt.warningCount, 0)
        XCTAssertEqual(compact(rebuilt.xml), exportCapture.replacingOccurrences(of: "id=\"11\"", with: "id=\"0\"").replacingOccurrences(of: "id=\"16\"", with: "id=\"0\""))
    }

    func testCapturedWholeFileRead() {
        for (value, name) in [("3", "Bytes"), ("2", "UTF-8")] {
            let native = readCapture.replacingOccurrences(of: "value=\"3\"", with: "value=\"\(value)\"")
            let imported = decompiler.decompile(native)
            XCTAssertEqual(imported.unsupportedStepCount, 0)
            XCTAssertTrue(imported.text.contains("Read as: \(name)"))
            XCTAssertEqual(compact(compiler.compile(imported.text).xml), native)
        }
    }

    func testNativeUTF16FieldTargetAfterPasteBack() {
        // FileMaker removes the variable-only Text node when resolving a field target.
        let native = """
        <fmxmlsnippet type="FMObjectList"><Step enable="True" id="193" name="Read from Data File"><DisableStepCollapsed state="False"></DisableStepCollapsed><DataSourceType value="1"></DataSourceType><Calculation><![CDATA[$fileID]]></Calculation><Field table="dk_approval_db_price" id="11" name="Veste Part"></Field></Step></fmxmlsnippet>
        """
        let imported = decompiler.decompile(native)
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertTrue(imported.text.contains("Read as: UTF-16"))
        XCTAssertTrue(imported.text.contains("Target: dk_approval_db_price::Veste Part"))
        XCTAssertEqual(compact(compiler.compile(imported.text).xml), native.replacingOccurrences(of: "id=\"11\"", with: "id=\"0\""))
    }

    func testUserBinaryReadStepsCompileWithoutWarnings() {
        let result = compiler.compile("""
        Read from Data File [
            File ID: $dkFileID ;
            Amount (bytes): ;
            Target: $dkFileData ;
            Read as: Bytes
        ]
        Read from Data File [ File ID: $navFileID ; Target: $navFileData ; Read as: Bytes ]
        """)
        XCTAssertEqual(result.warningCount, 0)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.steps, [
            .readDataFile(fileID: "$dkFileID", target: .variable("$dkFileData"), encoding: .bytes),
            .readDataFile(fileID: "$navFileID", target: .variable("$navFileData"), encoding: .bytes)
        ])
    }

    func testExplicitAmountUnknownOptionsAndDuplicatesAreNeverDropped() {
        let export = decompiler.decompile(exportCapture).text
        for text in [
            export.replacingOccurrences(of: " ; Field order:", with: " ; Unknown: On ; Field order:"),
            export.replacingOccurrences(of: " ; Field order:", with: " ; File Name: $other ; Field order:"),
            export.replacingOccurrences(of: "Veste Part,", with: "Veste Part"),
            "Read from Data File [ File ID: $id ; Amount (bytes): 100 ; Target: $data ; Read as: Bytes ]",
            "Read from Data File [ File ID: $id ; Amount: ; Amount (bytes): ; Target: $data ; Read as: Bytes ]",
            "Read from Data File [ File ID: $id ; Target: $data ; Read as: Bytes ; Unknown: On ]",
            "Read from Data File [ File ID: $id ; Target: $data + 1 ; Read as: Bytes ]"
        ] {
            let compiled = compiler.compile(text, options: .init(convertUnsupportedLinesToComments: false))
            XCTAssertGreaterThan(compiled.errorCount, 0, text)
            XCTAssertFalse(compiled.canCopyToFileMaker, text)
        }
    }

    func testNativeSettingsOutsideCapturedShapeRemainPreserved() {
        for xml in [
            readCapture.replacingOccurrences(of: "<Text>", with: "<Amount><Calculation>100</Calculation></Amount><Text>"),
            readCapture.replacingOccurrences(of: "enable=\"True\"", with: "enable=\"False\""),
            exportCapture.replacingOccurrences(of: "<WorkSheet>", with: "<WorkSheet future=\"yes\">"),
            exportCapture.replacingOccurrences(of: "<UseFieldNames state=\"False\">", with: "<UseFieldNames state=\"False\" future=\"yes\">")
        ] {
            let imported = decompiler.decompile(xml)
            XCTAssertEqual(imported.unsupportedStepCount, 1)
            XCTAssertEqual(compiler.compile(imported.text, preservedSteps: imported.preservedSteps).preservedStepCount, 1)
        }
    }

    func testSmartFixRepairsUserMultilineExportAndRetainsWorksheetAndHeadings() throws {
        let source = """
        # before
        Export Records [
            File Name: “$dkUnitPriceFilePath” ;
            Use field names as column names ;
            Worksheet: "DK UNIT PRICE" ;
            Create folders: Yes ;
            Character Set: “Unicode (UTF-16)” ;
            Field Order:
                dk_approval_db_price::Veste Part
                dk_approval_db_price::DK Bible Price
        ]
        [ No dialog ]
        # after
        """
        var review = SmartFixReview(source: source)
        XCTAssertEqual(review.items.count, 1)
        XCTAssertNotNil(review.items[0].suggestion)
        XCTAssertTrue(review.items[0].questions.isEmpty)
        review.items[0].action = .replace
        let fixed = try review.applying(to: source)
        XCTAssertTrue(fixed.hasPrefix("# before\n"))
        XCTAssertTrue(fixed.hasSuffix("\n# after"))
        let compiled = compiler.compile(fixed)
        XCTAssertEqual(compiled.warningCount, 0)
        XCTAssertTrue(compiled.xml.contains("<WorkSheet><Calculation><![CDATA[\"DK UNIT PRICE\"]]>"))
        XCTAssertTrue(compiled.xml.contains("<UseFieldNames state=\"True\">"))
        XCTAssertTrue(compiled.xml.contains("name=\"DK Bible Price\""))
    }

    func testQuestionsRequireAnswersAndDoNotGuessPathFieldsOrEncoding() throws {
        let source = "Export Records [ ]\nRead from Data File [ ]"
        var review = SmartFixReview(source: source)
        XCTAssertEqual(review.items.count, 2)
        XCTAssertNil(review.items[0].suggestion)
        XCTAssertNil(review.items[1].suggestion)
        XCTAssertFalse(review.items[0].useAnswers())
        XCTAssertFalse(review.items[1].useAnswers())
        XCTAssertEqual(Set(review.items[0].questions.map(\.key)), Set(["File:", "Format:", "Use field names:", "Field order:"]))
        XCTAssertEqual(Set(review.items[1].questions.map(\.key)), Set(["File ID:", "Target:", "Read as:"]))
        let answers = ["File:": "$path", "Format:": "XLSX", "Use field names:": "On", "Field order:": "TEST::A, TEST::B", "File ID:": "$id", "Target:": "$data", "Read as:": "Bytes"]
        for i in review.items.indices {
            for j in review.items[i].questions.indices { review.items[i].questions[j].answer = answers[review.items[i].questions[j].key]! }
            XCTAssertTrue(review.items[i].useAnswers())
        }
        let fixed = try review.applying(to: source)
        XCTAssertEqual(compiler.compile(fixed).warningCount, 0)
        XCTAssertEqual(compiler.compile(fixed).steps.count, 2)
    }

    func testSmartFixDoesNotRemoveBoundedAmountOrUnknownOptions() {
        for source in [
            "Read from Data File [ File ID: $id ; Amount (bytes): 512 ; Target: $data ; Read as: Bytes ]",
            "Export Records [ File: $path ; Unknown: On ]",
            "Export Records [ File: $path ; File Name: $other ]"
        ] {
            let item = SmartFixReview(source: source).items[0]
            XCTAssertNil(item.suggestion)
            XCTAssertTrue(item.questions.isEmpty)
        }
    }

    func testExportedTODOQuestionsAndReadRecovery() throws {
        let source = """
        # ----------------- FileMaker Script Bridge TODO -----------------
        # Export Records in FileMaker. AI draft: Export Records [ File: $path ; Worksheet: "Sheet1" ]
        # ----------------- FileMaker Script Bridge TODO -----------------
        # Read from Data File in FileMaker. AI draft: Read from Data File [ File ID: $id ; Amount (bytes): ; Target: $data ; Read as: Bytes ]
        """
        var review = SmartFixReview(source: source)
        XCTAssertEqual(review.items.count, 2)
        XCTAssertEqual(Set(review.items[0].questions.map(\.key)), Set(["Use field names:", "Field order:"]))
        XCTAssertNotNil(review.items[1].suggestion)
        review.items[1].action = .replace
        XCTAssertTrue(try review.applying(to: source).contains("\nRead from Data File ["))
    }
}
