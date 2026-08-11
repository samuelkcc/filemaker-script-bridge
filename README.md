# FileMaker Script Bridge

FileMaker Script Bridge is a free, native macOS utility that converts between readable script text and the structured clipboard format used by FileMaker Pro Script Workspace. It gives developers a safer way to review FileMaker scripts with an AI assistant while keeping the actual FileMaker copy-and-paste workflow under their control.

![FileMaker Script Bridge validating a readable script](Documentation/images/filemaker-script-bridge.png)

[Download the latest macOS release](https://github.com/samuelkcc/filemaker-script-bridge/releases/latest)

## Why it exists

FileMaker Script Workspace does not paste ordinary text as executable script steps. It expects private structured clipboard data. That makes it awkward to move a script into a readable review format and then return reviewed text to FileMaker without rebuilding every step manually.

FileMaker Script Bridge connects those two representations locally:

- FileMaker's native `XMSS` clipboard data for selected script steps;
- FileMaker's native `XMSC` clipboard data for complete scripts; and
- a readable, line-oriented text format suitable for review and careful editing.

The app is deliberately a clipboard bridge, not an automation tool. It never clicks in FileMaker or submits content to an AI service.

## Key features

- Native SwiftUI application for macOS 13 or later.
- Universal Apple Silicon and Intel build (`arm64` + `x86_64`).
- Fully local conversion with no network requests, analytics, or accounts.
- Live syntax colouring, validation, issue highlighting, and XML preview.
- Searchable reference for all 216 official FileMaker Pro 26 script steps.
- 92 tested editable step subsets.
- Lossless same-session preservation for imported steps and options that are not yet editable.
- Blocking validation for AI-authored syntax that cannot be reconstructed safely.

## How it works

### AI text to FileMaker

1. Copy the finished script text from your editor or AI assistant.
2. In FileMaker Script Bridge, choose **AI → FileMaker** and click **Paste AI Text & Create FileMaker Clipboard**.
3. Review the validation result. The app creates native `XMSS` clipboard data only when the script can be rebuilt safely.
4. In FileMaker Script Workspace, choose the insertion point and press `⌘V`.

### FileMaker to readable text

1. In FileMaker Script Workspace, select script steps and press `⌘C`. To copy a complete script, select it in the Scripts pane and copy it.
2. In FileMaker Script Bridge, choose **FileMaker → AI** and click **Read FileMaker Clipboard**.
3. The app reads the structured FileMaker payload and replaces the clipboard with readable text.
4. Paste the readable text into your editor or AI assistant.

The required `⌘C` and `⌘V` actions are intentional: the bridge cannot choose a script, insertion point, or destination on your behalf.

## Compatibility and data safety

The in-app reference covers all 216 script steps in the official 2026 Claris FileMaker Pro Help catalogue. Coverage has two distinct levels:

- **Editable subset:** the documented text form can be parsed and rebuilt as tested native FileMaker clipboard XML. Some steps support only specific, verified option profiles.
- **Preserve only:** the original XML of an imported step is retained in memory and represented by an `SCKC-P…` marker. If that marker remains unchanged, the original step can return to FileMaker unchanged during the same app session.

A preservation marker is not portable by itself. Closing the app discards its associated in-memory XML. If a marker is opened in a new session, export is blocked and the original script must be copied from FileMaker again.

Unrecognized or partially supported AI-authored lines have no original XML to preserve, so the app blocks clipboard creation instead of silently dropping or simplifying the action. See [Supported Syntax](Documentation/SUPPORTED_SYNTAX.md) and the [Claris coverage index](Documentation/CLARIS_SCRIPT_STEP_COVERAGE.md) for the current boundary.

Private FileMaker clipboard structures can change between releases. This version targets English FileMaker Pro 26 script-step names and does not claim compatibility with future private clipboard formats.

## Install

1. Download `FileMaker Script Bridge.app.zip` from the [latest release](https://github.com/samuelkcc/filemaker-script-bridge/releases/latest).
2. Extract the ZIP and move **FileMaker Script Bridge.app** to Applications.
3. Open the app.

The public build is ad-hoc signed and is not notarized with an Apple Developer ID. macOS may therefore require you to Control-click the app, choose **Open**, and confirm the first launch. Review the source and build locally if your organisation does not permit unnotarized applications.

## Privacy and security

All parsing, validation, and clipboard conversion happens on the Mac. The app does not send scripts anywhere. Content leaves the computer only when the user pastes it into another application or service.

Before sharing a script with any external service, remove or review credentials, personal data, confidential prices, internal hostnames, file paths, account names, and schema details. The [AI review workflow](Documentation/AI_REVIEW_WORKFLOW.md) contains a practical checklist.

## Build and test

Xcode Command Line Tools with Swift 6 are required.

```sh
env \
  CLANG_MODULE_CACHE_PATH="$PWD/.build/SCKCModuleCache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/SCKCModuleCache" \
  swift test --disable-sandbox --scratch-path "$PWD/.build/sckc-tests"

./Scripts/package-app.sh release
```

The packaging script builds both architectures, combines them with `lipo`, bundles the application icon, applies an ad-hoc signature, verifies a metadata-free staging copy, and creates:

- `dist/FileMaker Script Bridge.app`
- `dist/FileMaker Script Bridge.app.zip`

For redistribution in a managed environment, sign and notarize the app with your own Apple Developer ID.

## Project status

FileMaker Script Bridge is an independent community project under active development. New editable option families are added only after their native FileMaker XML has been captured, round-trip tested, and accepted by FileMaker Script Workspace. Contributions should preserve that evidence-based safety standard.

## Licence

Copyright © 2026 SCKC.

This project is free software licensed under the [GNU General Public License, version 3 or later](LICENSE). It is provided without warranty; see the licence for the complete terms.

## Trademark notice

This is independent software. It is not made by, affiliated with, endorsed by, or supported by Claris International Inc. FileMaker and FileMaker Pro are trademarks of Claris International Inc.

## Support the project ☕

If FileMaker Script Bridge saves you time, you can support future maintenance and verified script-step coverage:

[![Buy Samuel a coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/samuelchen)
