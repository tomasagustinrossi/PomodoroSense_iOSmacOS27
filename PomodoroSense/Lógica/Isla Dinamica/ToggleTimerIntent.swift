import AppIntents
import Foundation

// MARK: - Puente de Comunicación Inter-Procesos
// Usamos UserDefaults para que el Widget y la App puedan hablar. 
// Nota: Si usas un App Group, cambia "standard" por UserDefaults(suiteName: "group.tu.app")
let sharedDefaults = UserDefaults.standard

struct ToggleTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    
    func perform() async throws -> some IntentResult {
        // Guardamos la orden y lanzamos una notificación que el ViewModel escuchará
        sharedDefaults.set("TOGGLE", forKey: "WidgetCommand")
        NotificationCenter.default.post(name: NSNotification.Name("WidgetCommandReceived"), object: nil)
        return .result()
    }
}

struct SkipTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Session"
    
    func perform() async throws -> some IntentResult {
        sharedDefaults.set("SKIP", forKey: "WidgetCommand")
        NotificationCenter.default.post(name: NSNotification.Name("WidgetCommandReceived"), object: nil)
        return .result()
    }
}

struct StopTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    
    func perform() async throws -> some IntentResult {
        sharedDefaults.set("STOP", forKey: "WidgetCommand")
        NotificationCenter.default.post(name: NSNotification.Name("WidgetCommandReceived"), object: nil)
        return .result()
    }
}