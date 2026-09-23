import FileMakerBridgeCore
import SwiftUI

struct SmartFixView: View {
    @ObservedObject var model: BridgeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var review: SmartFixReview
    @State private var errorMessage: String?

    init(model: BridgeViewModel) {
        self.model = model
        _review = State(initialValue: SmartFixReview(source: model.sourceText, preservedSteps: model.preservedSteps))
    }

    private var selectedCount: Int { review.items.filter { $0.action != .keep }.count }
    private var invalidCount: Int {
        review.items.filter { $0.action == .replace && !SmartFixReview.isNativeReplacement($0.replacement) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Smart Fix · Bulk Review").font(.title2.bold())
            Text("Review missing parameters and TODOs before exporting. Suggested defaults need your approval. You can edit a replacement, keep a step for later, or explicitly omit it.")
                .foregroundStyle(.secondary)
            HStack {
                Text("\(review.items.count) items · \(selectedCount) selected")
                Spacer()
                Button("Select Suggested Fixes") {
                    for index in review.items.indices where review.items[index].suggestion != nil {
                        review.items[index].action = .replace
                    }
                }
                Button("Keep All") {
                    for index in review.items.indices { review.items[index].action = .keep }
                }
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if review.items.isEmpty {
                        Text("No TODOs or missing dialog defaults found.").padding()
                    }
                    ForEach($review.items) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Line \(item.line)").font(.headline)
                            Text(item.original).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text(item.reason).font(.callout).foregroundStyle(.secondary)
                            if item.suggestion == nil {
                                Text("No automatic fix is available. Supply the intended parameters below, or keep this item for later.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Picker("Action", selection: $item.action) {
                                ForEach(SmartFixAction.allCases, id: \.self) { action in
                                    Text(action.rawValue).tag(action)
                                }
                            }.pickerStyle(.segmented)
                            if item.action == .replace {
                                TextEditor(text: $item.replacement)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 85)
                                    .border(Color.secondary.opacity(0.3))
                                    .accessibilityLabel("Replacement for line \(item.line)")
                                if !SmartFixReview.isNativeReplacement(item.replacement) {
                                    Text("Replacement must compile as native steps. Missing parameters or unsupported options remain.")
                                        .font(.caption).foregroundStyle(.red)
                                }
                            } else if item.action == .omit {
                                Text("This step will not run. Its original text will remain as an omission comment.")
                                    .font(.caption).foregroundStyle(.orange)
                            } else if let suggestion = item.suggestion {
                                Text("Suggested: " + suggestion).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                    }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            Divider()
            HStack {
                Text("Changes apply to the editor. Update the FileMaker clipboard afterward.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply \(selectedCount) Changes") {
                    do {
                        try model.applySmartFix(review)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0 || invalidCount > 0)
            }
        }
        .padding(20)
        .frame(width: 780, height: 640)
    }
}
