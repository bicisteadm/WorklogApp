import SwiftUI

// MARK: - Duration Formatting

/// Formats a time interval in seconds to "Xh Ymin Zs" format
func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    return "\(hours)h \(minutes)min \(secs)s"
}

// MARK: - Sheet Types

enum SheetType: Identifiable {
    case newTicket
    case bulkTickets
    case newProject
    case newIteration
    case projectDetail(Project)
    case editProject(Project)
    case editTicket(Ticket)
    case editTimeEntry(TimeEntry)

    var id: String {
        switch self {
        case .newTicket: return "newTicket"
        case .bulkTickets: return "bulkTickets"
        case .newProject: return "newProject"
        case .newIteration: return "newIteration"
        case .projectDetail(let project): return "projectDetail-\(project.id)"
        case .editProject(let project): return "editProject-\(project.id)"
        case .editTicket(let ticket): return "editTicket-\(ticket.id)"
        case .editTimeEntry(let entry): return "editTimeEntry-\(entry.id)"
        }
    }
}

// MARK: - Badge View

struct CountBadge: View {
    let count: Int
    var color: Color = .primary

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Form Field

struct FormField<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content
        }
    }
}
