import XCTest
@testable import FileMakerBridgeCore

final class DataAndURLStepTests: XCTestCase {
    private let compiler = FileMakerXMLCompiler()
    private let decompiler = FileMakerXMLDecompiler()

    // Captured from FileMaker Pro's TEST script on 2026-09-14.
    private let native = """
    <fmxmlsnippet type="FMObjectList"><Step enable="True" id="191" name="Open Data File"><DisableStepCollapsed state="False"></DisableStepCollapsed><UniversalPathList>$tempPath</UniversalPathList><Text></Text><Field>$fileID</Field></Step><Step enable="True" id="192" name="Write to Data File"><AppendLineFeed state="True"></AppendLineFeed><DisableStepCollapsed state="False"></DisableStepCollapsed><DataSourceType value="2"></DataSourceType><Calculation><![CDATA[$fileID]]></Calculation><Text></Text><Field>$csvText</Field></Step><Step enable="True" id="196" name="Close Data File"><DisableStepCollapsed state="False"></DisableStepCollapsed><Calculation><![CDATA[$fileID]]></Calculation></Step><Step enable="True" id="190" name="Create Data File"><CreateDirectories state="True"></CreateDirectories><DisableStepCollapsed state="False"></DisableStepCollapsed><UniversalPathList>$tempPath</UniversalPathList></Step><Step enable="True" id="160" name="Insert from URL"><NoInteract state="True"></NoInteract><DontEncodeURL state="False"></DontEncodeURL><SelectAll state="True"></SelectAll><DisableStepCollapsed state="False"></DisableStepCollapsed><VerifySSLCertificates state="False"></VerifySSLCertificates><CURLOptions><Calculation><![CDATA[$curl]]></Calculation></CURLOptions><Calculation><![CDATA[$url]]></Calculation><Text></Text><Field>$response</Field></Step></fmxmlsnippet>
    """

    func testNativeVariableCaptureBecomesEditableAndRebuilds() {
        let imported = decompiler.decompile(native)
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertTrue(imported.text.contains("Write as: UTF-8 ; Append line feed: On"))
        let rebuilt = compiler.compile(imported.text)
        XCTAssertEqual(rebuilt.warningCount, 0)
        XCTAssertEqual(rebuilt.errorCount, 0)
        XCTAssertEqual(rebuilt.steps.count, 5)
        XCTAssertEqual(decompiler.decompile(rebuilt.xml).text, imported.text)
        // Compare against the native capture, independently of the decompiler.
        XCTAssertEqual(rebuilt.xml.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression), native)
    }

    func testNativeFieldAndAlternateFlagCaptureBecomesEditable() {
        // Second native capture used TEST::PrimaryKey (id 1), UTF-16,
        // line-feed off, SSL verification on, selection/encoding off.
        var xml = native
        for variable in ["$fileID", "$csvText", "$response"] {
            xml = xml.replacingOccurrences(of: "<Field>\(variable)</Field>", with: "<Field table=\"TEST\" id=\"1\" name=\"PrimaryKey\"></Field>")
        }
        xml = xml.replacingOccurrences(of: "<DataSourceType value=\"2\"", with: "<DataSourceType value=\"1\"")
            .replacingOccurrences(of: "<AppendLineFeed state=\"True\"", with: "<AppendLineFeed state=\"False\"")
            .replacingOccurrences(of: "<DontEncodeURL state=\"False\"", with: "<DontEncodeURL state=\"True\"")
            .replacingOccurrences(of: "<SelectAll state=\"True\"", with: "<SelectAll state=\"False\"")
            .replacingOccurrences(of: "<VerifySSLCertificates state=\"False\"", with: "<VerifySSLCertificates state=\"True\"")
        let imported = decompiler.decompile(xml)
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertTrue(imported.text.contains("Target: TEST::PrimaryKey"))
        XCTAssertTrue(imported.text.contains("Write as: UTF-16 ; Append line feed: Off"))
        let rebuilt = compiler.compile(imported.text)
        XCTAssertEqual(rebuilt.warningCount, 0)
        XCTAssertEqual(rebuilt.xml.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression), xml.replacingOccurrences(of: "id=\"1\"", with: "id=\"0\""))
    }

    func testUserWrappedDataFileAndPositionalURLSyntax() {
        let result = compiler.compile("""
        Create Data File [ “$tempPath” ; Create folders: On ]
        Open Data File [ “$tempPath” ; Target: $fileID ]
        Write to Data File [ File ID: $fileID ; Data source: $csvText ; Write as: UTF-8 ; Append line feed: On ]
        Close Data File [ File ID: $fileID ]
        Insert from URL [
            $tokenResponse ; $tokenURL ; cURL options: $tokenCurl
        ]
        [ Select ; No dialog ]
        """)
        XCTAssertEqual(result.warningCount, 0)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.steps, [
            .createDataFile(path: "$tempPath", createDirectories: true),
            .openDataFile(path: "$tempPath", target: .variable("$fileID")),
            .writeDataFile(fileID: "$fileID", source: .variable("$csvText"), utf8: true, appendLineFeed: true),
            .closeDataFile(fileID: "$fileID"),
            .insertFromURL(target: .variable("$tokenResponse"), url: "$tokenURL", curl: "$tokenCurl", selectAll: true, withDialog: false, verifySSL: false, encodeURL: true)
        ])
    }

    func testURLCalculationsAndFlagsPreserveSemicolonsAndEscaping() {
        let result = compiler.compile("""
        Insert from URL [ Select: Off ; With dialog: On ; Target: $$result ; URL: "https://example.com/?a=1&b=2" ; Verify SSL Certificates ; cURL options: Case ( $x ; "--request POST" ; "--request GET" ) ; Do not automatically encode URL ]
        Create Data File [ "file:folder/A&B.csv" ; Create folders: Off ]
        Close Data File [ File ID: GetAsNumber ( $fileID ) ]
        """)
        XCTAssertEqual(result.warningCount, 0)
        XCTAssertTrue(result.xml.contains("file:folder/A&amp;B.csv"))
        XCTAssertTrue(result.xml.contains("Case ( $x ; \"--request POST\" ; \"--request GET\" )"))
        let imported = decompiler.decompile(result.xml)
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(compiler.compile(imported.text).steps, result.steps)
    }

    func testURLWithoutCURLOptionsAndDataDefaults() {
        let result = compiler.compile("""
        Insert from URL [ Target: TEST::PrimaryKey ; URL: "https://example.com/" ; Verify SSL Certificates ]
        Create Data File [ File: "$path" ]
        Write to Data File [ File ID: $id ; Data source: $text ]
        """)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.warningCount, 0)
        XCTAssertFalse(result.xml.contains("<CURLOptions>"))
        XCTAssertEqual(result.steps[0], .insertFromURL(target: .field(table: "TEST", name: "PrimaryKey"), url: "\"https://example.com/\"", curl: nil, selectAll: false, withDialog: false, verifySSL: true, encodeURL: true))
        XCTAssertEqual(result.steps[1], .createDataFile(path: "$path", createDirectories: true))
        XCTAssertEqual(result.steps[2], .writeDataFile(fileID: "$id", source: .variable("$text"), utf8: false, appendLineFeed: false))
        let imported = decompiler.decompile(result.xml)
        XCTAssertEqual(imported.unsupportedStepCount, 0)
        XCTAssertEqual(compiler.compile(imported.text).steps, result.steps)
    }

    func testInvalidOrUnknownOptionsDoNotBecomeExecutableSteps() {
        for text in [
            "Open Data File [ $path ]",
            "Open Data File [ $path ; Target: $id + 1 ]",
            "Write to Data File [ File ID: $id ; Data source: Get ( CurrentTimestamp ) ]",
            "Open Data File [ $path ; Target: $id ; Target: $other ]",
            "Create Data File [ $path ; Create folders: Maybe ]",
            "Write to Data File [ File ID: $id ; Data source: $text ; Write as: ASCII ]",
            "Write to Data File [ File ID: $id ; Data source: $text ; Append line feed: Maybe ]",
            "Write to Data File [ File ID: $id ; Data source: $text ; Unknown: On ]",
            "Close Data File [ File ID: ]",
            "Insert from URL [ Target: $response ; URL: $url ; With dialog: Maybe ]",
            "Insert from URL [ Target: $response ; URL: $url ; Unknown: On ]",
            "Insert from URL [ Target: $response ; URL: $url ; cURL options: ]"
        ] {
            let result = compiler.compile(text, options: CompilationOptions(convertUnsupportedLinesToComments: false))
            XCTAssertGreaterThan(result.errorCount, 0, text)
            XCTAssertEqual(result.supportedStepCount, 0, text)
        }
    }

    func testUnknownNativeSettingsAndDisabledStepsStayPreserved() {
        for xml in [
            native.replacingOccurrences(of: "<Field>$fileID</Field>", with: "<Field>$fileID</Field><Repetition><Calculation>2</Calculation></Repetition>"),
            native.replacingOccurrences(of: "id=\"191\"", with: "id=\"191\" futureOption=\"True\""),
            native.replacingOccurrences(of: "enable=\"True\"", with: "enable=\"False\""),
            native.replacingOccurrences(of: "<DataSourceType value=\"2\"", with: "<DataSourceType value=\"9\"")
        ] {
            let imported = decompiler.decompile(xml)
            XCTAssertGreaterThan(imported.unsupportedStepCount, 0)
            let rebuilt = compiler.compile(imported.text, preservedSteps: imported.preservedSteps)
            XCTAssertEqual(rebuilt.errorCount, 0)
            XCTAssertEqual(rebuilt.preservedStepCount, imported.unsupportedStepCount)
        }
    }
}
