#!/usr/bin/env python3
"""Refresh the factual FileMaker script-step catalogue from official Claris Help.

The crawler reads every category and individual step page, but deliberately stores
only factual titles, categories, and links. Claris owns the prose, examples, and
other documentation content; the generated catalogue links back to that source.
"""

from __future__ import annotations

import concurrent.futures
import datetime as dt
import html
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
import urllib.request


BASE_URL = "https://help.claris.com/en/pro-help/content/"
CATEGORY_PAGES = [
    "control-script-steps.html",
    "navigation-script-steps.html",
    "editing-script-steps.html",
    "fields-script-steps.html",
    "records-script-steps.html",
    "found-sets-script-steps.html",
    "windows-script-steps.html",
    "files-script-steps.html",
    "accounts-script-steps.html",
    "artificial-intelligence-script-steps.html",
    "spelling-script-steps.html",
    "pdf-files-script-steps.html",
    "open-menu-item-script-steps.html",
    "miscellaneous-script-steps.html",
]

# These names reflect the compiler's actual authored-text capability. "Editable"
# means the documented subset in SUPPORTED_SYNTAX.md, not every option Claris offers.
EDITABLE_SUBSET = {
    "# (Comment)",
    "Allow User Abort",
    "Allow Formatting Bar",
    "Beep",
    "Commit Records/Requests",
    "Else",
    "Else If",
    "End If",
    "End Loop",
    "Enter Find Mode",
    "Enable Touch Keyboard",
    "Export Field Contents",
    "Exit Loop If",
    "Exit Script",
    "Exit Application",
    "Freeze Window",
    "Flush Cache to Disk",
    "Flush Web Viewer Cookies",
    "Go to Layout",
    "Go to Record/Request/Page",
    "Halt Script",
    "If",
    "Insert File",
    "Loop",
    "New Record/Request",
    "New Window",
    "Open Edit Saved Finds",
    "Open Favorites",
    "Open File Options",
    "Open Find/Replace",
    "Open Help",
    "Open Hosts",
    "Open Manage Containers",
    "Open Manage Data Sources",
    "Open Manage Database",
    "Open Manage Layouts",
    "Open Manage Themes",
    "Open Manage Value Lists",
    "Open Settings",
    "Open Script Workspace",
    "Open Sharing",
    "Open Upload To Host",
    "Perform Script",
    "Perform Script On Server",
    "Perform Find",
    "Refresh Window",
    "Refresh Object",
    "Revert Record/Request",
    "Delete Record/Request",
    "Delete All Records",
    "Close Window",
    "Select Window",
    "Set Error Capture",
    "Set Field",
    "Set Field By Name",
    "Set Variable",
    "Set Use System Formats",
    "Send Mail",
    "Show All Records",
    "Show Custom Dialog",
    "Adjust Window",
    "Arrange All Windows",
    "Constrain Found Set",
    "Copy All Records/Requests",
    "Copy Record/Request",
    "Delete Portal Row",
    "Duplicate Record/Request",
    "Export Records",
    "Extend Found Set",
    "Find Matching Records",
    "Import Records",
    "Modify Last Find",
    "Move/Resize Window",
    "Omit Multiple Records",
    "Omit Record",
    "Open Record/Request",
    "Perform Quick Find",
    "Save Records as Excel",
    "Save Records as JSONL",
    "Save Records as Snapshot Link",
    "Scroll Window",
    "Set Window Title",
    "Set Zoom Level",
    "Show Omitted Only",
    "Show/Hide Menubar",
    "Show/Hide Text Ruler",
    "Show/Hide Toolbars",
    "Sort Records",
    "Sort Records by Field",
    "Truncate Table",
    "Unsort Records",
    "View As",
}


class MainParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.in_main = False
        self.main_div_depth = 0
        self.in_h1 = False
        self.h1_parts: list[str] = []
        self.current_link: str | None = None
        self.current_link_parts: list[str] = []
        self.links: list[tuple[str, str]] = []
        self.visible_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag == "div" and attributes.get("id") == "mc-main-content":
            self.in_main = True
            self.main_div_depth = 1
            return
        if not self.in_main:
            return
        if tag == "div":
            self.main_div_depth += 1
        if tag == "h1":
            self.in_h1 = True
        if tag == "a" and attributes.get("href"):
            self.current_link = attributes["href"]
            self.current_link_parts = []

    def handle_endtag(self, tag: str) -> None:
        if not self.in_main:
            return
        if tag == "h1":
            self.in_h1 = False
        if tag == "a" and self.current_link is not None:
            title = clean_text(" ".join(self.current_link_parts))
            if title:
                self.links.append((self.current_link, title))
            self.current_link = None
            self.current_link_parts = []
        if tag == "div":
            self.main_div_depth -= 1
            if self.main_div_depth == 0:
                self.in_main = False

    def handle_data(self, data: str) -> None:
        if not self.in_main:
            return
        value = clean_text(data)
        if not value:
            return
        self.visible_parts.append(value)
        if self.in_h1:
            self.h1_parts.append(value)
        if self.current_link is not None:
            self.current_link_parts.append(value)

    @property
    def title(self) -> str:
        return clean_text(" ".join(self.h1_parts))

    @property
    def visible_text(self) -> str:
        return clean_text(" ".join(self.visible_parts))


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(value)).strip()


def fetch(slug: str) -> str:
    request = urllib.request.Request(
        BASE_URL + slug,
        headers={"User-Agent": "FileMaker-Script-Bridge-reference-audit/2026.08.04"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def parse(slug: str) -> MainParser:
    parser = MainParser()
    parser.feed(fetch(slug))
    if not parser.title or len(parser.visible_text) < 40:
        raise RuntimeError(f"Official page did not contain readable main content: {slug}")
    return parser


def swift_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    categories: list[tuple[str, str, list[tuple[str, str]]]] = []
    seen_slugs: set[str] = set()

    for category_slug in CATEGORY_PAGES:
        parsed = parse(category_slug)
        step_links: list[tuple[str, str]] = []
        for slug, title in parsed.links:
            if not slug.endswith(".html") or slug in seen_slugs:
                continue
            if slug in CATEGORY_PAGES or slug == "script-steps-reference.html":
                continue
            seen_slugs.add(slug)
            step_links.append((slug, title))
        if not step_links:
            raise RuntimeError(f"No script steps found in category: {category_slug}")
        categories.append((parsed.title, category_slug, step_links))

    all_steps = [item for _, _, links in categories for item in links]
    page_results: dict[str, MainParser] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = {executor.submit(parse, slug): (slug, title) for slug, title in all_steps}
        for future in concurrent.futures.as_completed(futures):
            slug, expected_title = futures[future]
            parsed = future.result()
            if parsed.title != expected_title:
                raise RuntimeError(
                    f"Title mismatch for {slug}: category says {expected_title!r}, page says {parsed.title!r}"
                )
            page_results[slug] = parsed

    missing_editable = sorted(EDITABLE_SUBSET - {title for _, title in all_steps})
    if missing_editable:
        raise RuntimeError(f"Editable names missing from official catalogue: {missing_editable}")

    generated_at = dt.date.today().isoformat()
    swift_lines = [
        "// Generated by Scripts/update-claris-step-reference.py.",
        f"// Official Claris FileMaker Pro Help catalogue read {generated_at}.",
        "// Do not copy Claris documentation prose into this file; link to the source.",
        "",
        "import Foundation",
        "",
        "public enum ScriptStepSupportLevel: String, Sendable, Hashable, CaseIterable {",
        "    case editableSubset",
        "    case preserveOnly",
        "}",
        "",
        "public struct FileMakerScriptStepReference: Identifiable, Sendable, Hashable {",
        "    public let name: String",
        "    public let category: String",
        "    public let documentationURL: URL",
        "    public let support: ScriptStepSupportLevel",
        "    public var id: String { category + \"/\" + name }",
        "}",
        "",
        "public enum FileMakerScriptStepCatalog {",
        f"    public static let sourceReadDate = \"{generated_at}\"",
        "    public static let sourceURL = URL(string: \"https://help.claris.com/en/pro-help/content/script-steps-reference.html\")!",
        "    public static let entries: [FileMakerScriptStepReference] = [",
    ]
    for category, _, links in categories:
        for slug, title in links:
            support = "editableSubset" if title in EDITABLE_SUBSET else "preserveOnly"
            swift_lines.append(
                "        .init(name: \"{}\", category: \"{}\", documentationURL: URL(string: \"{}{}\")!, support: .{}),".format(
                    swift_string(title), swift_string(category), BASE_URL, slug, support
                )
            )
    swift_lines += [
        "    ]",
        "",
        "    public static let categories: [String] = {",
        "        var seen = Set<String>()",
        "        return entries.compactMap { seen.insert($0.category).inserted ? $0.category : nil }",
        "    }()",
        "",
        "    public static var editableSubsetCount: Int {",
        "        entries.filter { $0.support == .editableSubset }.count",
        "    }",
        "",
        "    public static func officialStep(matching line: String) -> FileMakerScriptStepReference? {",
        "        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)",
        "        return entries",
        "            .sorted { $0.name.count > $1.name.count }",
        "            .first { entry in",
        "                guard value.range(of: entry.name, options: [.caseInsensitive, .anchored]) != nil else { return false }",
        "                guard value.count > entry.name.count else { return true }",
        "                let boundary = value.index(value.startIndex, offsetBy: entry.name.count)",
        "                return value[boundary].isWhitespace || value[boundary] == \"[\"",
        "            }",
        "    }",
        "}",
        "",
    ]
    (root / "Sources/FileMakerBridgeCore/FileMakerScriptStepCatalog.generated.swift").write_text(
        "\n".join(swift_lines), encoding="utf-8"
    )

    markdown = [
        "# Claris FileMaker Pro script-step coverage",
        "",
        f"> Official catalogue audited on `{generated_at}`: **{len(all_steps)} steps across {len(categories)} categories**. ",
        "> Source: [Claris FileMaker Pro Help](https://help.claris.com/en/pro-help/content/script-steps-reference.html).",
        "",
        "This is a coverage index, not a copy of Claris documentation. Follow each step link for its official purpose, options, compatibility, version origin, notes, and examples.",
        "",
        "- **Editable subset**: the bridge can create a tested native clipboard representation from the documented readable-text subset. This does not imply that every FileMaker option is editable.",
        "- **Preserve only**: when copied from FileMaker, the original XML is retained and can round-trip unchanged in the same session. AI-authored text for the step is blocked because the app has no original XML.",
        "",
    ]
    for category, category_slug, links in categories:
        markdown += [
            f"## [{category}]({BASE_URL}{category_slug})",
            "",
            "| Script step | Bridge support |",
            "|---|---|",
        ]
        for slug, title in links:
            support = "Editable subset" if title in EDITABLE_SUBSET else "Preserve only"
            markdown.append(f"| [{title}]({BASE_URL}{slug}) | {support} |")
        markdown.append("")
    (root / "Documentation/CLARIS_SCRIPT_STEP_COVERAGE.md").write_text(
        "\n".join(markdown), encoding="utf-8"
    )

    print(
        f"Read {len(page_results)} individual step pages and {len(categories)} category pages; "
        f"generated {len(all_steps)} entries ({len(EDITABLE_SUBSET)} editable subsets)."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise
