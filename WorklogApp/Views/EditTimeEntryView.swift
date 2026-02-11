import SwiftUI
import SwiftData

struct EditTimeEntryView: View {
    let entry: TimeEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var hours: String
    @State private var minutes: String
    @State private var seconds: String
    @State private var note: String
    @State private var loggedAt: Date

    init(entry: TimeEntry) {
        self.entry = entry
        let totalSeconds = Int(entry.hours * 3600)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        _hours = State(initialValue: String(h))
        _minutes = State(initialValue: String(m))
        _seconds = State(initialValue: String(s))
        _note = State(initialValue: entry.note ?? "")
        _loggedAt = State(initialValue: entry.loggedAt)
    }

    private var isValidTime: Bool {
        guard let h = Int(hours), let m = Int(minutes), let s = Int(seconds) else {
            return false
        }
        return h >= 0 && m >= 0 && m < 60 && s >= 0 && s < 60 && (h > 0 || m > 0 || s > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Time Entry")
                .font(.title2.weight(.bold))

            FormField("Duration") {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        TextField("H", text: $hours)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 55)
                            .multilineTextAlignment(.trailing)
                        Text("hours")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    HStack(spacing: 4) {
                        TextField("M", text: $minutes)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 55)
                            .multilineTextAlignment(.trailing)
                        Text("min")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    HStack(spacing: 4) {
                        TextField("S", text: $seconds)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 55)
                            .multilineTextAlignment(.trailing)
                        Text("sec")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }

            FormField("Note") {
                TextEditor(text: $note)
                    .font(.body)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            FormField("Logged At") {
                DatePicker("", selection: $loggedAt, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveTimeEntry() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidTime)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func saveTimeEntry() {
        guard let h = Int(hours), let m = Int(minutes), let s = Int(seconds) else { return }
        let totalHours = Double(h) + (Double(m) / 60.0) + (Double(s) / 3600.0)
        guard totalHours > 0 else { return }

        entry.hours = totalHours
        entry.note = note.isEmpty ? nil : note
        entry.loggedAt = loggedAt

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save time entry: \(error)")
        }
    }
}
