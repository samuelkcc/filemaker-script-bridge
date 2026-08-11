import FileMakerBridgeCore
import SwiftUI

struct StepReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filter: SupportFilter = .all

    private var entries: [FileMakerScriptStepReference] {
        FileMakerScriptStepCatalog.entries.filter { entry in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .editableSubset:
                matchesFilter = entry.support == .editableSubset
            case .preserveOnly:
                matchesFilter = entry.support == .preserveOnly
            }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || entry.name.localizedCaseInsensitiveContains(query)
                || entry.category.localizedCaseInsensitiveContains(query)
            return matchesFilter && matchesSearch
        }
    }

    private var visibleCategories: [String] {
        FileMakerScriptStepCatalog.categories.filter { category in
            entries.contains { $0.category == category }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            referenceList
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 620)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("FileMaker Pro Script-Step Reference")
                    .font(.title2.weight(.semibold))
                Text("Official 2026 catalogue · audited (FileMakerScriptStepCatalog.sourceReadDate)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                metric(
                    value: FileMakerScriptStepCatalog.entries.count,
                    label: "Official steps",
                    color: .blue
                )
                metric(
                    value: FileMakerScriptStepCatalog.editableSubsetCount,
                    label: "Editable subsets",
                    color: .green
                )
                metric(
                    value: FileMakerScriptStepCatalog.entries.count - FileMakerScriptStepCatalog.editableSubsetCount,
                    label: "Completion templates",
                    color: .orange
                )
                metric(
                    value: FileMakerScriptStepCatalog.categories.count,
                    label: "Categories",
                    color: .secondary
                )
            }

            HStack(spacing: 12) {
                TextField("Search script step or category", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Support", selection: $filter) {
                    ForEach(SupportFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 360)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var referenceList: some View {
        List {
            ForEach(visibleCategories, id: \.self) { category in
                Section(category) {
                    ForEach(entries.filter { $0.category == category }) { entry in
                        HStack(spacing: 12) {
                            Text(entry.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            supportBadge(entry.support)
                            Link(destination: entry.documentationURL) {
                                Label("Claris Help", systemImage: "arrow.up.right.square")
                                    .labelStyle(.iconOnly)
                            }
                            .help("Open the official Claris page for \(entry.name)")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if entries.isEmpty {
                Text("No script steps match this search and filter.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text("Editable subset means the bridge can create a tested native FileMaker clipboard form. Completion template means AI text pastes as a visible TODO comment for completion in FileMaker; copied original XML still round-trips unchanged during the current session.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Link("Complete official reference", destination: FileMakerScriptStepCatalog.sourceURL)
                .font(.caption)
        }
        .padding(14)
    }

    private func metric(value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.08)))
    }

    private func supportBadge(_ support: ScriptStepSupportLevel) -> some View {
        let editable = support == .editableSubset
        return Text(editable ? "EDITABLE SUBSET" : "COMPLETION TEMPLATE")
            .font(.caption2.weight(.bold))
            .foregroundStyle(editable ? Color.green : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill((editable ? Color.green : Color.orange).opacity(0.12)))
    }
}

private enum SupportFilter: String, CaseIterable, Identifiable {
    case all
    case editableSubset
    case preserveOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .editableSubset: return "Editable"
        case .preserveOnly: return "Templates"
        }
    }
}
