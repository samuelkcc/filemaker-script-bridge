# Supported syntax

Version `2026.08.11` targets English FileMaker Pro 26 script-step names. Matching is case-insensitive, but calculations, object names, and text values are preserved exactly.

The [complete Claris coverage index](CLARIS_SCRIPT_STEP_COVERAGE.md) was generated after reading and validating all 216 individual official step pages across 14 categories. The app's searchable **Step Reference** uses the same catalogue and links every entry to Claris Help.

## FileMaker → readable AI text

The importer accepts:

- Selected script steps copied from Script Workspace (`XMSS`).
- Complete scripts copied from the Scripts pane (`XMSC`).
- UTF-8 or UTF-16 FileMaker clipboard XML.

The listed supported steps are reconstructed into the same readable syntax accepted by the text compiler. A copied complete script also receives a `# FileMaker Script: Name` heading.

For a step not yet fully supported, the importer retains its original XML in memory and emits a visible `# ↔ FileMaker step preserved unchanged` marker with an `SCKC-P…` token. The original XML also remains available in the app's **XML** view.

These markers are shown as amber warnings. Keep them unchanged and return the text during the same app session: **Paste AI Text & Create FileMaker Clipboard** will insert the original step XML unchanged. The marker's step options are locked rather than text-editable. If its in-memory XML is unavailable, export is blocked and the original script must be read from FileMaker again.

## AI draft templates for setup-dependent steps

AI-authored lines for every official step can be pasted into FileMaker. When the bridge does not yet have a native XMSS mapping, it creates a visible FileMaker comment rather than inventing XML:

```text
# -----------------  FileMaker Script Bridge TODO -----------------
# Configure AI Account in FileMaker. AI draft: Configure AI Account [ Provider: OpenAI ; Account: production ]
```

This is the default **Template comments enabled** mode. Use it for AI accounts, server settings, hardware features, or any option family that must be configured in the target FileMaker file. The two-line comment block preserves the AI intent but does not perform the action; replace it with the real FileMaker step before release. Search Script Workspace for `FileMaker Script Bridge TODO` to find every required completion. **Strict native-only mode** remains available when a clipboard must contain only tested native steps.

## Variables and fields

```text
Set Variable [ $name ; Value: calculation ]
Set Variable [ $$globalName ; Value: calculation ; Repetition: calculation ]
Set Field [ TableOccurrence::Field ; calculation ]
Set Field By Name [ target-name calculation ; result calculation ]
```

Field and table IDs are emitted as `0` so FileMaker can resolve the supplied names in the destination file. Missing names remain unresolved and must be corrected in FileMaker.

## Control flow

```text
If [ calculation ]
Else If [ calculation ]
Else
End If

Loop
Loop [ Flush: Always ]
Loop [ Flush: Minimum ]
Loop [ Flush: Never ]
Exit Loop If [ calculation ]
End Loop

Allow User Abort [ On ]
Allow User Abort [ Off ]
Set Error Capture [ On ]
Set Error Capture [ Off ]
Allow Formatting Bar [ On ]
Allow Formatting Bar [ Off ]
Exit Script
Exit Script [ Text Result: calculation ]
Halt Script
```

`If`/`End If` and `Loop`/`End Loop` nesting is validated before copy.

## Navigation and scripts

```text
Go to Layout [ "Layout Name" ]
Go to Record/Request/Page [ First ]
Go to Record/Request/Page [ Last ]
Go to Record/Request/Page [ Previous ]
Go to Record/Request/Page [ Previous ; Exit after last ]
Go to Record/Request/Page [ Next ]
Go to Record/Request/Page [ Next ; Exit after last ]
Go to Record/Request/Page [ By calculation: calculation ]
Enter Find Mode [ Pause: Off ]
Perform Find [ ]
Perform Script [ "Script Name" ]
Perform Script [ "Script Name" ; Parameter: calculation ]
Perform Script on Server [ "Script Name" ; Parameter: calculation ; Wait for completion: On ]
```

Straight or smart quotes are accepted around layout and script names. A copied FileMaker context suffix such as `(table occurrence)` is removed from the object name. References are resolved by the destination FileMaker file when pasted.

## Dialogs

```text
Show Custom Dialog [ Message: calculation ]
Show Custom Dialog [ Title: calculation ; Message: calculation ]
Show Custom Dialog [ Title: calculation ; Message: calculation ; Default Button: “Cancel”, Commit: “No” ; Button 2: “Create”, Commit: “Yes” ]
Show Custom Dialog [ Title: calculation ; Message: calculation ; Default Button: “Cancel” ; Commit: “No” ; Button 2: “Create” ; Commit: “Yes” ]
```

When buttons are omitted, the generated dialog has a default **OK** button. Up to three custom buttons and their commit settings are supported. A button's `Commit:` setting may follow after either a comma or a semicolon. Input fields are not implemented yet.

## Records, find, and windows

```text
Delete Record/Request [ With dialog: Off ]
Delete All Records [ With dialog: Off ]
Revert Record/Request [ With dialog: Off ]
Delete All Records [ No dialog ]
Revert Record/Request [ No dialog ]

Close Window [ Current Window ]
Close Window [ Name: calculation ; Current file ]
Select Window [ Current Window ]
Select Window [ Name: calculation ; Current file ]

New Window [ Style: Document ; Name: calculation ; Using layout: “Layout Name” (context) ; Close: Yes ; Minimize: No ; Maximize: Yes ; Resize: Yes ; Menu Bar: Yes ; Dim parent window: No ; Toolbars: Yes ]
```

`Perform Find [ ]` means no stored find requests. Stored-request XML remains preserve-only.

`Sort Records` supports native field-based stored sort lists when every sort is an ascending or descending primary field sort:

```text
Sort Records [ With dialog: On ; Blanks last: On ; Keep records sorted: Off ; TEST::test Ascending ; TEST::number Descending ]
```

Custom sort modes, summary reordering, value-list sorts, language overrides, and other unrepresented `SortList` XML remain preserve-only.

## Files, containers, and layout objects

```text
Set Use System Formats [ On ]
Set Use System Formats [ Off ]
Export Field Contents [ TableOccurrence::ContainerField ; "$fileName" ; Create folders: Yes ]
Insert File [ Target: TableOccurrence::ContainerField ; "$filePath" ]
Refresh Object [ Object Name: "object_name" ; Repetition: 1 ]
```

These editable subsets cover the variable-path, named-field, and named-object forms used by the supplied FileMaker scripts.

The following Export Records and Send Mail workflow is native-captured and editable. It writes an XLSX file to a FileMaker temporary path, keeps automatic opening off, uses the listed field order, then attaches the same file through the E-Mail Client. The explicit `Format: XLSX` and `Character set: Unicode` values are required; other export profiles, automatic opening, create-email exports, recipients, messages, SMTP, OAuth, or additional mail settings remain preserve-only.

```text
Export Records [ With dialog: Off ; Create folders: On ; File: "file:temp/SCKC-Export.xlsx" ; Format: XLSX ; Character set: Unicode ; Use field names: Off ; Field order: TEST::test, TEST::number ]
Send Mail [ Send via: E-Mail Client ; With dialog: Off ; Attachment: "file:temp/SCKC-Export.xlsx" ]
```

The following Import Records profile is native-captured and editable. It imports from an XLSX file with an empty worksheet selection and no stored import order. Selected worksheets, field mappings/import order, auto-enter choices, SSL verification changes, alternative sources, and other profile options remain preserve-only.

```text
Import Records [ With dialog: Off ; File: "file:temp/SCKC-Import.xlsx" ; Format: XLSX ]
```

The following Save Records as Excel profile is native-captured and editable. It creates an XLSX file with automatic opening and email creation off. Other output profiles, custom field mapping, automatic opening, and email settings remain preserve-only.

```text
Save Records as Excel [ With dialog: Off ; File: "file:temp/SCKC-Records.xlsx" ; Records being browsed ; Create folders: On ; Use field names: Off ]
Save Records as Excel [ With dialog: On ; File: "file:temp/Current.xlsx" ; Current record ; Create folders: Off ; Use field names: On ]
```

## Common no-option steps

```text
New Record/Request
Show All Records
Commit Records/Requests
Freeze Window
Refresh Window
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
Open Script Workspace
Open Sharing
Open Upload to Host
Beep
Exit Application
Flush Cache to Disk
Flush Web Viewer Cookies
Enable Touch Keyboard [ On ]
Enable Touch Keyboard [ Off ]
```

## Captured priority defaults

The following Records, Found Sets, and Windows lines rebuild the native default configuration captured from FileMaker Pro. Use FileMaker for a non-default option until that particular option variant is listed separately here.

```text
Copy All Records/Requests
Copy Record/Request
Delete Portal Row
Duplicate Record/Request
Open Record/Request
Save Records as Excel
Save Records as JSONL
Save Records as Snapshot Link
Truncate Table
Constrain Found Set [ Find without indexes: Off ]
Constrain Found Set [ Find without indexes: On ]
Extend Found Set
Find Matching Records [ Replace ]
Find Matching Records [ Replace ; Target: Table::Field ]
Find Matching Records [ Constrain ]
Find Matching Records [ Extend ]
Modify Last Find
Omit Multiple Records [ With dialog: Off ]
Omit Multiple Records [ With dialog: On ; Records: 5 ]
Omit Record
Perform Quick Find
Perform Quick Find [ $query ]
Show Omitted Only
Sort Records [ With dialog: Off ]
Sort Records [ With dialog: On ]
Sort Records [ With dialog: On ; Blanks last: On ; Keep records sorted: Off ; TEST::test Ascending ; TEST::number Descending ]
Sort Records by Field [ Ascending ]
Sort Records by Field [ Descending ; Target: Table::Field ]
Sort Records by Field [ Associated value list ]
Unsort Records
Adjust Window [ Resize to Fit ]
Adjust Window [ Maximize ]
Adjust Window [ Minimize ]
Adjust Window [ Restore ]
Adjust Window [ Hide ]
Arrange All Windows [ Tile Horizontally ]
Arrange All Windows [ Tile Vertically ]
Arrange All Windows [ Cascade ]
Arrange All Windows [ Bring All to Front ]
Move/Resize Window [ Current Window ]
Move/Resize Window [ Name: $windowName ; Current file ; Height: 600 ; Width: 800 ; Top: 40 ; Left: 50 ]
Scroll Window [ Home ]
Scroll Window [ End ]
Scroll Window [ Page Up ]
Scroll Window [ Page Down ]
Scroll Window [ To Selection ]
Set Window Title [ Current Window ]
Set Window Title [ Name: $windowName ; Current file ; New title: $title ]
Set Zoom Level [ 25% ; Lock: On ]
Set Zoom Level [ Zoom In ; Lock: Off ]
Set Zoom Level [ Zoom Out ; Lock: Off ]
Set Zoom Level [ Custom: 125 ; Lock: Off ]
Show/Hide Menubar [ Show ; Lock: Off ]
Show/Hide Menubar [ Hide ; Lock: On ]
Show/Hide Text Ruler [ Show ]
Show/Hide Text Ruler [ Hide ]
Show/Hide Text Ruler [ Toggle ]
Show/Hide Toolbars [ Show ; Lock: Off ; Include Edit Record Toolbar: On ]
Show/Hide Toolbars [ Hide ; Lock: On ; Include Edit Record Toolbar: Off ]
Show/Hide Toolbars [ Toggle ; Lock: Off ; Include Edit Record Toolbar: On ]
View As [ Form ]
View As [ List ]
View As [ Table ]
View As [ Cycle ]
```

Unlisted options on these steps remain preserve-only. Use the validation preview and inspect the step after pasting.

## Comments

```text
# comment text
// comment text
Comment [ "comment text" ]
```

Unsupported or malformed lines become comments beginning with `▶︎` when fallback mode is enabled.

FileMaker has no spacing-only script step, so blank readable lines are omitted from the generated FileMaker clipboard.

## Multi-line input

Long steps may wrap across lines. The compiler joins lines until the step's outer square brackets close. It ignores square brackets inside straight or smart quoted strings.

```text
Set Variable [
    $payload ;
    Value: JSONSetElement (
        "{}" ;
        [ "name" ; "Sam" ; JSONString ]
    )
]
```

## Current boundaries

- FileMaker Pro 26 English step names only.
- Only the listed subset of FileMaker's script-step catalogue is text-editable.
- Official-but-unimplemented AI steps receive a named **preserve-only** error with instructions to copy the original step from FileMaker; they are not mislabeled as unknown text.
- Step-name matching enforces a real name boundary, so `Perform Script On Server` is compiled as its own step rather than the shorter `Perform Script` step.
- Unrecognized imported steps can round-trip unchanged during the same app session, but their options cannot be edited as readable text.
- AI-authored unsupported steps have no original XML to preserve and therefore block clipboard creation by default.
- All current or future FileMaker steps are not guaranteed: `XMSS` and `XMSC` are private, version-dependent clipboard formats.
- Object references are name-based and must exist in the destination file.
- The compiler checks structural syntax, not the full FileMaker calculation grammar.
- Direct Accessibility-based automatic pasting is intentionally excluded. The user chooses the target script and presses `⌘V`, preventing insertion into the wrong database or script.
- The app is ad-hoc signed for local validation, not Developer ID signed or notarized for public distribution.
- Copying for AI only places plain text on the local clipboard. The user controls whether that text is transmitted to an external AI service.
