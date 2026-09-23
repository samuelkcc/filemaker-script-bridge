# FileMaker Script Bridge 2026.09.23

## Highlights

- Adds local Smart Fix review for flagged script lines and missing dialog defaults. Review suggested repairs, edit replacements, keep unresolved items, or explicitly omit a step with a comment preserving the original text.
- Validates replacements as native steps before applying them and requires a separate Update FileMaker Clipboard action after review.
- Recovers the bridge’s exported two-comment TODO drafts for review and repair.
- Improves Show Custom Dialog parsing and validation, including positional title/message forms, ordered button definitions, and rejection of unsupported or duplicate options. Missing default-button suggestions use `Default Button: "OK", Commit: No` and require review.
- Expands coverage since the first release from 92 to 97 editable subsets across the 216-step reference. Adds native data-file operations and Insert from URL, improves wrapped record/find options, and fixes Go to Record exit-option XML.
- Provides completion-template comments for the remaining 119 official steps, with optional strict native-only export.
- Improves universal app packaging with optional SDK and build-system overrides.

## Validation

The universal release build completed for Apple Silicon and Intel, and its ad-hoc signature and bundle version were verified. Automated tests could not run on the release machine: Command Line Tools lacks XCTest, and the installed Xcode requires license acceptance.

## Download and requirements

Download **FileMaker Script Bridge.app.zip**, extract it, and move the app to Applications.

- macOS 13 or later; universal Apple Silicon and Intel build.
- FileMaker Pro 26 for the documented script-step catalogue.
- Fully local operation; no accounts, analytics, or network requests.
- Ad-hoc signed and not Apple-notarized. macOS may require Control-clicking the app and choosing **Open** on first launch.
- Preservation markers retain their original XML only during the same app session. Complete unresolved TODO steps in FileMaker before using the script.

Released under GPL-3.0-or-later. This independent project is not affiliated with or endorsed by Claris International Inc.

---

# FileMaker Script Bridge 2026.08.11

This is the first public release of FileMaker Script Bridge, a native offline macOS clipboard bridge for FileMaker Pro Script Workspace and readable script text.

## Highlights

- Converts selected FileMaker steps (`XMSS`) and complete scripts (`XMSC`) into readable text.
- Validates readable text and creates native FileMaker clipboard data for paste-back.
- Covers all 216 official FileMaker Pro 26 steps in the in-app reference.
- Provides 92 tested editable subsets and lossless same-session preservation for other imported steps.
- Includes syntax colouring, issue navigation, review/XML views, and strict blocking of lossy AI-authored exports.
- Ships as a universal macOS application for Apple Silicon and Intel.
- Runs fully offline with no accounts, analytics, or network requests.

## Requirements

- macOS 13 or later
- FileMaker Pro 26 for the documented and tested script-step catalogue

## Installation note

The downloadable build is ad-hoc signed and is not Apple-notarized. macOS may require Control-clicking the app and choosing **Open** on first launch.

## Licence and independence

Released under GPL-3.0-or-later. This independent community project is not affiliated with or endorsed by Claris International Inc.
