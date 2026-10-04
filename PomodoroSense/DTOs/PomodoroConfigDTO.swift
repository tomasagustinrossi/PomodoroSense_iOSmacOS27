import Foundation

// Único contrato para la base de datos local y la memoria de la UI
struct PomodoroConfigDTO: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var focus: Int
    var breakTime: Int
    var sessions: Int
    var audio: AudioConfigDTO

    enum CodingKeys: String, CodingKey {
        case id, name, focus
        case breakTime = "break"
        case sessions, audio
    }
}

struct AudioConfigDTO: Codable, Equatable {
    var presetId: Int
    var noiseId: Int
    var freqId: Int
}