import Foundation

// 1. El Contrato (Inversión de Control)
protocol PomodoroRepositoryProtocol {
    func loadConfigs() -> [PomodoroConfigDTO]
    func saveConfigs(_ configs: [PomodoroConfigDTO])
}

// 2. La Implementación Concreta (Infraestructura)
class UserDefaultsPomodoroRepository: PomodoroRepositoryProtocol {
    private let storageKey = "Pomodoro_Saved_Presets"
    
    // Si queremos cambiar a SwiftData mañana, solo creamos una clase nueva que firme el protocolo
    // y el resto de la app ni se entera.
    
    func loadConfigs() -> [PomodoroConfigDTO] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PomodoroConfigDTO].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveConfigs(_ configs: [PomodoroConfigDTO]) {
        if let encoded = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}