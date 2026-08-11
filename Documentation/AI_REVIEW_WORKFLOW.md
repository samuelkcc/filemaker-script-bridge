# AI review workflow

## Copy from FileMaker

In Script Workspace, select the steps to review and press `⌘C`. To review a complete script, select it in the Scripts pane and copy it.

FileMaker places structured XML on the clipboard under its private `XMSS` or `XMSC` type. Ordinary text editors cannot read this representation directly.

## Import into the bridge

Click **Read FileMaker Clipboard**. The bridge:

1. Finds the FileMaker clipboard representation.
2. Decodes its XML locally.
3. Reconstructs supported steps as concise readable text.
4. Restores indentation for `If`, `Else If`, `Else`, and `Loop` blocks.
5. Preserves unrecognized step XML in memory and inserts explicit SCKC markers.
6. Retains the original XML in the **XML** view.
7. Automatically copies the readable text, ready to paste into the AI tool.

If unrecognized steps are found, the bridge shows an amber preservation result. This is a successful read. Keep every `SCKC-P…` marker unchanged and complete the return trip before closing the app. The original step XML can then be placed back on the FileMaker clipboard unchanged, although its options are not editable as text.

## Readable text is copied automatically

There is no separate **Copy Readable Text** action. A successful FileMaker read replaces the structured clipboard with ordinary UTF-8 text and shows a blue confirmation badge.

After reviewing the AI result, copy it as plain text and click **Paste AI Text & Create FileMaker Clipboard**. A successful validation immediately creates the native FileMaker clipboard and shows a green confirmation badge. Finally return to FileMaker Script Workspace and press `⌘V`; the bridge does not control FileMaker automatically.

A useful review request is:

```text
Review this FileMaker Pro 26 script. Identify logic errors, missing error handling,
unsafe global-variable usage, invalid references, and opportunities to simplify it.
Do not change its behaviour. Return the revised script one step per line.
```

## Privacy boundary

FileMaker-to-text conversion is local and offline. The script leaves the Mac only when the user pastes it into an external service. Before doing that, check for:

- Passwords, API keys, tokens, or connection strings.
- Customer, employee, supplier, or other personal data.
- Confidential pricing and commercial rules.
- Internal hostnames, file paths, account names, and schema details.

The bridge does not automatically open, sign in to, or submit content to an AI provider.
