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
            }
            if !note.body.isEmpty {
                Text(note.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Text(note.createdAt, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(.tertiary)
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
    NotesView(viewModel: container.notes).task { await container.notes.load() }
}
