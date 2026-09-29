# Native export and read verification — 2026-09-29

Native clipboard XML was inspected through the bridge's XML view using FileMaker
Pro's Script Workspace. Regression fixtures are in `ExportAndReadStepTests.swift`.

- Captured the existing XLSX export with its output variable, `WorkSheet` calculation,
  two ordered fields, and UseFieldNames off.
- Captured variable-target reads: DataSourceType 3 = Bytes and 2 = UTF-8.
- Pasted a generated XLSX export with UseFieldNames on and `"DK UNIT PRICE"`, two
  binary reads, a UTF-8 variable read, and a UTF-16 field read into an empty test script.
- Copied those five steps back. FileMaker resolved field IDs and omitted the
  variable-only `Text` node for the field target. The read compiler now emits that
  native field shape. DataSourceType 1 = UTF-16.
- Repeated the paste/copy check using the final packaged build: all five steps
  imported as editable with zero warnings and zero errors. Undid the verification
  paste, leaving the empty test script unchanged.
- Tested the Smart Fix question form and replacement generation in the application.
  Applied the multiline export suggestion to the user's bridge draft; the complete
  draft validated as 487 steps, zero warnings, zero errors, and was restored to the
  editor and native clipboard after the checks.
- All 96 automated tests passed with Xcode's developer directory and SwiftPM's native
  build system. The release package contains arm64 and x86_64 and passes codesign verification.

No export/read/email script was executed. Runtime behavior and database business
logic are outside this clipboard verification.

## Read amount limitation

In the native capture, a Read from Data File step displaying `Amount (bytes):
64 * 1024` still copied XML without an amount node. The supported authored subset
therefore requires blank/omitted Amount. Non-empty amounts remain explicit manual
setup items and Smart Fix never changes them into whole-file reads. Preservation
can retain only the XML FileMaker actually supplies, not an omitted parameter.
