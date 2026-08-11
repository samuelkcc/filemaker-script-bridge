import FileMakerBridgeCore
import SwiftUI

private enum WorkflowMode: String, CaseIterable, Identifiable {
    case aiToFileMaker = "AI → FileMaker"
    case fileMakerToAI = "FileMaker → AI"

    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var model = BridgeViewModel()
    @AppStorage("appearance.isDark") private var isDarkTheme = false
    @State private var showingAbout = false
    @State private var showingStepReference = false
    @State private var workflowMode: WorkflowMode = .aiToFileMaker

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                editorPane
                    .frame(minWidth: 500)
                reviewPane
                    .frame(minWidth: 330, idealWidth: 390, maxWidth: 470)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(isDarkTheme ? .dark : .light)
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingStepReference) {
            StepReferenceView()
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    Image(systemName: "arrow.left.arrow.right.square.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("FileMaker Script Bridge")
                        .font(.title2.weight(.semibold))
                    Text("Local FileMaker Pro ↔ readable AI script workflow")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("About") {
                    showingAbout = true
                }
                .buttonStyle(.bordered)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDarkTheme.toggle()
                    }
                } label: {
                    Label(
                        isDarkTheme ? "Use Light Theme" : "Use Dark Theme",
                        systemImage: isDarkTheme ? "sun.max.fill" : "moon.stars.fill"
                    )
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help(isDarkTheme ? "Switch to light theme" : "Switch to dark theme")
                .accessibilityLabel(isDarkTheme ? "Use Light Theme" : "Use Dark Theme")
            }

            workflowCard
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var workflowCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 14) {
                Picker("Workflow", selection: $workflowMode) {
                    ForEach(WorkflowMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)

                Text(workflowMode == .aiToFileMaker
                     ? "Primary workflow · used for AI-reviewed or AI-authored script text"
                     : "Secondary workflow · use when sending existing FileMaker steps to AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workflowMode == .aiToFileMaker
                         ? "1. Copy the finished AI script as plain text"
                         : "1. Select steps in FileMaker Script Workspace and press ⌘C")
                        .font(.subheadline.weight(.medium))
                    Text(workflowMode == .aiToFileMaker
                         ? "The bridge validates it and creates the native FileMaker clipboard."
                         : "The bridge converts copied XMSS/XMSC data to readable text and copies it automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)

                if workflowMode == .aiToFileMaker {
                    Button(action: model.pasteAITextAndCreateClipboard) {
                        Label("Paste AI Text & Create FileMaker Clipboard", systemImage: "doc.on.clipboard.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [.command])
                } else {
                    Button(action: model.importFromFileMaker) {
                        Label("Read FileMaker Clipboard", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            if workflowMode == .aiToFileMaker, model.clipboardNotice == .fileMakerReady {
                notificationBadge(
                    "Ready — choose the insertion point in FileMaker and press ⌘V",
                    systemImage: "checkmark.circle.fill",
                    color: .green
                )
            } else if workflowMode == .fileMakerToAI, model.clipboardNotice == .readableTextReady {
                notificationBadge(
                    "Readable text copied automatically — paste it into AI",
                    systemImage: "doc.on.doc.fill",
                    color: .blue
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(workflowMode == .aiToFileMaker ? 0.08 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.24))
        )
    }

    private func notificationBadge(
        _ text: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("READABLE SCRIPT TEXT", systemImage: "text.alignleft")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear", action: model.clearEditor)
                    .buttonStyle(.bordered)
                    .disabled(model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(action: model.copyForFileMaker) {
                    Label("Update FileMaker Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canCopyForFileMaker)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScriptTextEditor(
                text: $model.sourceText,
                issues: model.result.issues,
                requestedLine: model.requestedEditorLine,
                navigationRevision: model.editorNavigationRevision
            )
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                Label("RGB syntax colours · issue lines are highlighted", systemImage: "paintpalette.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("One step per line; wrapped […] steps are joined automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var reviewPane: some View {
        VStack(spacing: 0) {
            HStack {
                Label("VALIDATION", systemImage: "checklist")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingStepReference = true
                } label: {
                    Label("Step Reference", systemImage: "books.vertical.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
                Picker("View", selection: $model.showXML) {
                    Text("Review").tag(false)
                    Text("XML").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if model.showXML {
                xmlView
            } else {
                validationView
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var validationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    metricCard(
                        title: "Steps",
                        value: "\(model.result.steps.count)",
                        color: .blue
                    )
                    metricCard(
                        title: "Warnings",
                        value: "\(model.displayWarningCount)",
                        color: model.displayWarningCount == 0 ? .green : .orange
                    )
                    metricCard(
                        title: "Errors",
                        value: "\(model.result.errorCount)",
                        color: model.result.errorCount == 0 ? .green : .red
                    )
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI DRAFT TEMPLATES")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(model.convertUnsupportedToComments
                             ? "Paste as visible TODO comments for completion in FileMaker"
                             : "Block non-native AI lines")
                            .font(.caption)
                            .foregroundStyle(model.convertUnsupportedToComments ? .orange : .secondary)
                    }
                    Spacer()
                    Button {
                        model.convertUnsupportedToComments.toggle()
                    } label: {
                        Label(
                            model.convertUnsupportedToComments ? "Template comments enabled" : "Strict native-only mode",
                            systemImage: model.convertUnsupportedToComments
                                ? "text.bubble.fill"
                                : "shield.checkered"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(model.convertUnsupportedToComments ? .orange : .blue)
                    .help("Template comments keep an AI draft visible and pasteable when FileMaker setup, an account, or hardware is still required.")
                }
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.08))
                )

                if model.result.preservedStepCount > 0 {
                    VStack(spacing: 12) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.orange)
                        Text("Preserved for a safe round trip")
                            .font(.headline)
                        Text("Every imported step remains pasteable back to FileMaker during this session. \(model.result.preservedStepCount) step\(model.result.preservedStepCount == 1 ? " has" : "s have") locked options and will return unchanged. Keep each SCKC marker intact and complete the return trip before closing the app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.08))
                    )
                } else if !model.templateIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("TODO templates to complete in FileMaker", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("\(model.templateIssues.count) AI line\(model.templateIssues.count == 1 ? " needs" : "s need") manual setup. Each pastes as a two-line FileMaker comment block headed “FileMaker Script Bridge TODO”, so search Script Workspace for that heading to find them.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(model.templateIssues) { issue in
                            issueRow(issue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.12))
                    )
                } else if model.result.issues.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.green)
                        Text("Ready to paste")
                            .font(.headline)
                        Text("The script is structurally valid and every line can be rebuilt as a native FileMaker clipboard step.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }

                if !model.result.issues.isEmpty && model.templateIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Issues")
                            .font(.headline)
                        ForEach(model.result.issues) { issue in
                            issueRow(issue)
                        }
                    }
                }

                supportedSyntax
            }
            .padding(16)
        }
    }

    private var xmlView: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                Text(model.displayedXML)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            Divider()
            HStack {
                Text(model.isShowingImportedXML
                     ? "Original XML copied from FileMaker — retained for lossless inspection."
                     : "Generated XML — FileMaker receives this as XMSS, not plain text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Raw XML", action: model.copyXML)
            }
            .padding(10)
        }
    }

    private var supportedSyntax: some View {
        DisclosureGroup("Claris reference · \(FileMakerScriptStepCatalog.editableSubsetCount) editable subsets of \(FileMakerScriptStepCatalog.entries.count) official steps") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The remaining \(FileMakerScriptStepCatalog.entries.count - FileMakerScriptStepCatalog.editableSubsetCount) official steps paste as two-line completion template comments when generated by AI. Search for `FileMaker Script Bridge TODO` to find them; copied originals still round-trip unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Complete Step Reference") {
                    showingStepReference = true
                }
                .buttonStyle(.link)
            }
            .padding(.top, 7)
        }
        .font(.subheadline.weight(.medium))
    }

    private func metricCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    private func issueRow(_ issue: CompilationIssue) -> some View {
        Button {
            model.focusEditor(on: issue)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.severity == .error ? .red : .orange)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Line \(issue.line): \(issue.message)")
                        .font(.subheadline.weight(.medium))
                    Text(issue.source)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((issue.severity == .error ? Color.red : Color.orange).opacity(0.08))
        )
        .help("Select and scroll to line \(issue.line) in the script editor")
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(2)
            Spacer()
            Button("Inspect Clipboard", action: model.inspectClipboard)
                .buttonStyle(.borderless)
            Text("⌘⇧C updates FileMaker clipboard · GPL-3.0-or-later · Independent software")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var statusIcon: String {
        switch model.statusTone {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.statusTone {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
