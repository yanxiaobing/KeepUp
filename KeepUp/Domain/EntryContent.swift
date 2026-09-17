import Foundation

struct EntryContent: Codable, Equatable, Sendable {
    var text = ""
    var photo: Data?
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil }
    func validated() throws -> Self {
        guard text.count <= 1000, (photo?.count ?? 0) <= 5_000_000 else { throw StoreError.invalidContent }
        var result = self
        result.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

struct EntryContentRecord: Codable, Equatable, Sendable {
    var published: EntryContent?
    var draft: EntryContent?
}

extension LocalSnapshot {
    func publishedContent(for entry: CheckInEntry) -> EntryContent {
        content[entry.id]?.published ?? EntryContent(text: entry.note)
    }
    func editingContent(for entry: CheckInEntry) -> EntryContent {
        content[entry.id]?.draft ?? publishedContent(for: entry)
    }
}
