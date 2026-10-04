import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit

// Define los datos estáticos y dinámicos para la Dynamic Island y Lockscreen
struct PomodoroAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Datos que cambian segundo a segundo
        var isBreak: Bool
        var currentSession: Int
        var totalSessions: Int
        var targetDate: Date // Fundamental: iOS calcula el tiempo visualmente usando la fecha final
    }

    // Datos estáticos (ej: nombre de la configuración)
    var presetName: String
}
#endif