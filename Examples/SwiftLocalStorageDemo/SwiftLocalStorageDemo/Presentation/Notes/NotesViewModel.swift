import Foundation
import Observation

@MainActor @Observable
final class NotesViewModel {
    private(set) var notes: [Note] = []
    var editing: Note?
    var errorMessage: String?

    private let useCase: ManageNotesUseCase

    init(useCase: ManageNotesUseCase) {
        self.useCase = useCase
    }

    /// Keeps `notes` current for as long as the calling task runs (use it from `.task`).
    func observe() async {
        do {
            for try await batch in useCase.observe() {
                notes = ManageNotesUseCase.sorted(batch)
            }
        } catch {
            if !Task.isCancelled { errorMessage = describe(error) }
        }
    }

    func startNewNote() { editing = Note() }

    func save(_ note: Note) async {
        await perform { try await useCase.save(note) }
    }

    func togglePin(_ note: Note) async {
        await perform { try await useCase.togglePin(note) }
    }

    func delete(at offsets: IndexSet) async {
        let doomed = offsets.map { notes[$0] }
        await perform { try await useCase.delete(doomed) }
    }

    private func perform(_ body: () async throws -> Void) async {
        do { try await body() } catch { errorMessage = describe(error) }
    }
}
