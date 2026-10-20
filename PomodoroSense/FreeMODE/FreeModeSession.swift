import Foundation

struct FreeModeSession: Codable, Identifiable, Hashable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    var note: String?

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self, forKey: .id)
        startedAt  = try c.decode(Date.self, forKey: .startedAt)
        endedAt    = try c.decode(Date.self, forKey: .endedAt)
        note       = try c.decodeIfPresent(String.self, forKey: .note)
    }

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        note: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
    }
}
