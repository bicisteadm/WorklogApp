import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TimeEntry.loggedAt, order: .reverse) private var allEntries: [TimeEntry]
    @Query(sort: \Project.name) private var projects: [Project]
    @Query private var iterations: [Iteration]

    @State private var selectedProject: Project?
    @State private var selectedIteration: Iteration?
    @State private var searchText = ""
    @State private var groupingMode: GroupingMode = .individual

    enum GroupingMode: String, CaseIterable, Identifiable {
        case individual = "Individual"
        case byTicket = "By Ticket"
        case byIteration = "By Iteration"
        case byProject = "By Project"

        var id: String { rawValue }
    }

    struct GroupedData: Identifiable {
        let id = UUID()
        let name: String
        let subtitle: String?
        let hours: Double
        let entries: [TimeEntry]
    }

    private var availableIterations: [Iteration] {
        guard let project = selectedProject else { return [] }
        return iterations.filter { $0.project?.id == project.id }
    }

    private var filteredEntries: [TimeEntry] {
        var result = allEntries

        if let project = selectedProject {
            result = result.filter { $0.ticket?.project?.id == project.id }
        }

        if let iteration = selectedIteration {
            result = result.filter { $0.ticket?.iteration?.id == iteration.id }
        }

        if !searchText.isEmpty {
            result = result.filter { entry in
                entry.ticket?.name.localizedCaseInsensitiveContains(searchText) == true ||
                entry.ticket?.ticketId.localizedCaseInsensitiveContains(searchText) == true ||
                (entry.note?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    private var totalHours: Double {
        filteredEntries.reduce(0) { $0 + $1.hours }
    }

    private var groupedData: [GroupedData] {
        switch groupingMode {
        case .individual:
            return filteredEntries.map { entry in
                GroupedData(
                    name: entry.ticket?.name ?? "Unknown",
                    subtitle: entry.ticket?.ticketId,
                    hours: entry.hours,
                    entries: [entry]
                )
            }

        case .byTicket:
            let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
                entry.ticket?.id.hashValue.description ?? "unknown"
            }
            return grouped.map { _, entries in
                let ticket = entries.first?.ticket
                return GroupedData(
                    name: ticket?.name ?? "Unknown",
                    subtitle: ticket?.ticketId,
                    hours: entries.reduce(0) { $0 + $1.hours },
                    entries: entries
                )
            }.sorted { $0.hours > $1.hours }

        case .byIteration:
            let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
                entry.ticket?.iteration?.name ?? "No Iteration"
            }
            return grouped.map { name, entries in
                GroupedData(
                    name: name,
                    subtitle: entries.first?.ticket?.iteration?.project?.name,
                    hours: entries.reduce(0) { $0 + $1.hours },
                    entries: entries
                )
            }.sorted { $0.hours > $1.hours }

        case .byProject:
            let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
                entry.ticket?.project?.name ?? "No Project"
            }
            return grouped.map { name, entries in
                GroupedData(
                    name: name,
                    subtitle: "\(entries.count) tickets",
                    hours: entries.reduce(0) { $0 + $1.hours },
                    entries: entries
                )
            }.sorted { $0.hours > $1.hours }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Time Reports")
                    .font(.title.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Filters
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Group by", selection: $groupingMode) {
                        ForEach(GroupingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)

                    Spacer()

                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: 250)
                }

                HStack(spacing: 12) {
                    Picker("Project", selection: $selectedProject) {
                        Text("All Projects").tag(nil as Project?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project as Project?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 180)
                    .onChange(of: selectedProject) { _, _ in
                        if let iteration = selectedIteration,
                           !availableIterations.contains(where: { $0.id == iteration.id }) {
                            selectedIteration = nil
                        }
                    }

                    Picker("Iteration", selection: $selectedIteration) {
                        Text("All Iterations").tag(nil as Iteration?)
                        ForEach(availableIterations) { iteration in
                            HStack {
                                Image(systemName: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                                Text(iteration.name)
                            }
                            .tag(iteration as Iteration?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 180)
                    .disabled(selectedProject == nil)

                    Spacer()

                    Button {
                        selectedProject = nil
                        selectedIteration = nil
                        searchText = ""
                    } label: {
                        Label("Clear Filters", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
                    .disabled(selectedProject == nil && selectedIteration == nil && searchText.isEmpty)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Stats bar
            HStack {
                Text(groupingMode == .individual ? "\(filteredEntries.count) time entries" : "\(groupedData.count) groups")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .textSelection(.enabled)
                Spacer()
                Text("Total: \(formatDuration(totalHours * 3600))")
                    .font(.headline)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.05))

            Divider()

            // Table
            if groupingMode == .individual {
                Table(filteredEntries) {
                    TableColumn("Date") { entry in
                        Text(entry.loggedAt.formatted(date: .abbreviated, time: .omitted))
                            .textSelection(.enabled)
                    }
                    .width(min: 100, max: 120)

                    TableColumn("Ticket") { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.ticket?.name ?? "Unknown")
                                .font(.headline)
                                .textSelection(.enabled)
                            if let ticketId = entry.ticket?.ticketId, !ticketId.isEmpty {
                                Text(ticketId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .width(min: 150, ideal: 200)

                    TableColumn("Project") { entry in
                        Text(entry.ticket?.project?.name ?? "No project")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .width(min: 120, ideal: 150)

                    TableColumn("Iteration") { entry in
                        if let iteration = entry.ticket?.iteration {
                            HStack(spacing: 4) {
                                Image(systemName: iteration.type == .sprint ? "arrow.clockwise" : "flag")
                                    .font(.caption)
                                Text(iteration.name)
                                    .textSelection(.enabled)
                            }
                            .font(.caption)
                        } else {
                            Text("—")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 100, ideal: 130)

                    TableColumn("Note") { entry in
                        Text(entry.note ?? "")
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .width(min: 150)

                    TableColumn("Duration") { entry in
                        Text(formatDuration(entry.hours * 3600))
                            .monospacedDigit()
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: 120, max: 150)
                }
            } else {
                Table(groupedData) {
                    TableColumn("Name") { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.headline)
                                .textSelection(.enabled)
                            if let subtitle = group.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .width(min: 200, ideal: 300)

                    TableColumn("Entries") { group in
                        Text("\(group.entries.count)")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .width(min: 100, max: 140)

                    TableColumn("Total Duration") { group in
                        Text(formatDuration(group.hours * 3600))
                            .monospacedDigit()
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                    }
                    .width(min: 140, max: 160)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
