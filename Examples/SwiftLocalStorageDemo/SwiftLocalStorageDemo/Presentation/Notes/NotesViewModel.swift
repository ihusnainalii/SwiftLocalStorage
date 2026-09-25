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

    func load() async {
        await perform { notes = try await useCase.list() }
    }

    func startNewNote() { editing = Note() }

    func save(_ note: Note) async {
        await perform { try await useCase.save(note) }
        await load()
    }

    func togglePin(_ note: Note) async {
        await perform { try await useCase.togglePin(note) }
        await load()
    }

    func delete(at offsets: IndexSet) async {
        let doomed = offsets.map { notes[$0] }
        await perform { try await useCase.delete(doomed) }
        await load()
    }

    private func perform(_ body: () async throws -> Void) async {
        do { try await body() } catch { errorMessage = describe(error) }
    }
}
