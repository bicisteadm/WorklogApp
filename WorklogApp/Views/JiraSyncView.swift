import SwiftUI
import SwiftData

/// Sheet that runs `JiraImporter.sync(project:in:)` and reports progress.
/// Auto-starts on appear; user can dismiss when finished or on error.
struct JiraSyncView: View {
    let project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bridge: JiraBridge
    @StateObject private var importer: JiraImporter
    @State private var didStart = false

    init(project: Project, importer: JiraImporter) {
        self.project = project
        _importer = StateObject(wrappedValue: importer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sync from Jira")
                    .font(.title2.weight(.bold))
                Spacer()
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                Text(project.jiraJQL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }

            Divider()

            phaseView

            Divider()

            HStack {
                Spacer()
                if isFinishedOrFailed {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(true)  // can't really abort mid-flight cleanly
                }
            }
        }
        .padding()
        .frame(width: 540)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            Task { await importer.sync(project: project, in: modelContext) }
        }
    }

    private var isFinishedOrFailed: Bool {
        switch importer.phase {
        case .finished, .failed: return true
        default: return false
        }
    }

    @ViewBuilder
    private var phaseView: some View {
        switch importer.phase {
        case .idle:
            ProgressView()
                .controlSize(.small)

        case .discoveringSprintField:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Discovering sprint custom field…")
                    .font(.subheadline)
            }

        case .fetching(let page, let totalSoFar, let total):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching issues — page \(page)\(total.map { " of \(($0 / 100) + 1)" } ?? "")")
                        .font(.subheadline)
                }
                if let total {
                    ProgressView(value: Double(totalSoFar), total: Double(total))
                }
                Text("\(totalSoFar) issue(s) so far")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .applying(let processed, let total):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Applying changes — \(processed) / \(total)")
                        .font(.subheadline)
                }
                ProgressView(value: Double(processed), total: Double(total))
            }

        case .finished(let summary):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Done — \(summary.fetched) issue(s) fetched")
                        .font(.headline)
                }
                summaryLine("Tickets created", summary.ticketsCreated, color: .green)
                summaryLine("Tickets updated", summary.ticketsUpdated, color: .blue)
                summaryLine("Tickets deleted", summary.ticketsDeleted, color: .red)
                summaryLine("Tickets orphaned (kept — has time entries)", summary.ticketsOrphaned, color: .orange)
                summaryLine("Sprints created", summary.sprintsCreated, color: .green)
                summaryLine("Sprints updated", summary.sprintsUpdated, color: .blue)
                if !summary.errors.isEmpty {
                    Divider()
                    Text("Notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(summary.errors.enumerated()), id: \.offset) { _, err in
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(err)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

        case .failed(let msg):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Sync failed")
                        .font(.headline)
                        .foregroundStyle(.red)
                }
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func summaryLine(_ label: String, _ count: Int, color: Color) -> some View {
        if count > 0 {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(color)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count)")
                    .font(.subheadline.weight(.medium))
            }
        }
    }
}
