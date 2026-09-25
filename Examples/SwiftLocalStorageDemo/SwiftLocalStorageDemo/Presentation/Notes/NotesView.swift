import SwiftUI

/// User-created data: create, edit, pin, delete. Stored with no expiration.
struct NotesView: View {
    @Bindable var viewModel: NotesViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.notes) { note in
                    Button { viewModel.editing = note } label: { NoteRow(note: note) }
                        .tint(.primary)
                        .swipeActions(edge: .leading) {
                            Button(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin") {
                                Task { await viewModel.togglePin(note) }
                            }
                            .tint(.orange)
                        }
                }
                .onDelete { offsets in Task { await viewModel.delete(at: offsets) } }
            }
            .overlay {
                if viewModel.notes.isEmpty {
                    ContentUnavailableView(
                        "No notes", systemImage: "note.text",
                        description: Text("Notes are stored locally and survive relaunches.")
                    )
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New note", systemImage: "square.and.pencil") { viewModel.startNewNote() }
                }
            }
            .sheet(item: $viewModel.editing) { note in
                NoteEditor(note: note) { saved in Task { await viewModel.save(saved) } }
            }
            .errorAlert($viewModel.errorMessage)
            // Live query: saves, pins and deletes show up here without any manual reload.
            .task { await viewModel.observe() }
        }
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if note.isPinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                Text(note.title).font(.headline)
                Spacer()
                PriorityBadge(priority: note.priority)
            }
            if !note.body.isEmpty {
                Text(note.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Text(note.createdAt, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct PriorityBadge: View {
    let priority: Note.Priority

    var body: some View {
        Text(priority.rawValue.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
            .accessibilityLabel("\(priority.rawValue) priority")
    }

    private var color: Color {
        switch priority {
        case .low: .secondary
        case .normal: .blue
        case .high: .red
        }
    }
}

private struct NoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var note: Note
    let onSave: (Note) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $note.title)
                TextField("Body", text: $note.body, axis: .vertical).lineLimit(4...10)
                Picker("Priority", selection: $note.priority) {
                    ForEach(Note.Priority.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("Pinned", isOn: $note.isPinned)
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(note)
                        dismiss()
                    }
                    .disabled(note.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    NotesView(viewModel: container.notes)
}
