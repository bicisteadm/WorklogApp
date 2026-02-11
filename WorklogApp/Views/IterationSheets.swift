import SwiftUI
import SwiftData

// MARK: - New Iteration

struct NewIterationView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String = ""
    @State private var type: IterationType = .sprint
    @State private var startDate: Date = Date()
    @State private var dueDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Iteration")
                .font(.title2.weight(.bold))

            FormField("Name") {
                TextField("Iteration name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            FormField("Type") {
                Picker("", selection: $type) {
                    ForEach(IterationType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type == .sprint ? "arrow.clockwise" : "flag").tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            FormField("Start Date") {
                DatePicker("", selection: $startDate, displayedComponents: [.date])
                    .labelsHidden()
            }

            FormField("Due Date") {
                DatePicker("", selection: $dueDate, displayedComponents: [.date])
                    .labelsHidden()
            }

            if dueDate <= startDate {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Due date must be after start date")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { saveIteration() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || dueDate <= startDate)
            }
        }
        .padding()
        .fixedSize()
    }

    private func saveIteration() {
        guard !name.isEmpty, dueDate > startDate else { return }
        let iteration = Iteration(name: name, type: type, startDate: startDate, dueDate: dueDate, project: project)
        modelContext.insert(iteration)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save iteration: \(error)")
        }
    }
}

// MARK: - Edit Iteration

struct EditIterationView: View {
    let iteration: Iteration
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var type: IterationType
    @State private var startDate: Date
    @State private var dueDate: Date

    init(iteration: Iteration) {
        self.iteration = iteration
        _name = State(initialValue: iteration.name)
        _type = State(initialValue: iteration.type)
        _startDate = State(initialValue: iteration.startDate)
        _dueDate = State(initialValue: iteration.dueDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Iteration")
                .font(.title2.weight(.bold))

            FormField("Name") {
                TextField("Iteration name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            FormField("Type") {
                Picker("", selection: $type) {
                    ForEach(IterationType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type == .sprint ? "arrow.clockwise" : "flag").tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            FormField("Start Date") {
                DatePicker("", selection: $startDate, displayedComponents: [.date])
                    .labelsHidden()
            }

            FormField("Due Date") {
                DatePicker("", selection: $dueDate, displayedComponents: [.date])
                    .labelsHidden()
            }

            if dueDate <= startDate {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Due date must be after start date")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveIteration() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || dueDate <= startDate)
            }
        }
        .padding()
        .fixedSize()
    }

    private func saveIteration() {
        guard !name.isEmpty, dueDate > startDate else { return }
        iteration.name = name
        iteration.type = type
        iteration.startDate = startDate
        iteration.dueDate = dueDate
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save iteration: \(error)")
        }
    }
}
