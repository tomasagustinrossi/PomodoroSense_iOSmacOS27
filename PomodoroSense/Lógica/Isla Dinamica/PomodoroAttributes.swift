//
//  PomodoroAttributes.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 06/10/2026.
//


import Foundation
import SwiftUI
#if os(iOS)
import ActivityKit

// Define los datos estáticos y dinámicos para la Dynamic Island y Lockscreen
struct PomodoroAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Datos que cambian segundo a segundo
        var isBreak: Bool
        var currentSession: Int
        var totalSessions: Int
        var targetDate: Date // Fundamental: iOS calcula el tiempo visualmente usando la fecha final
        var noiseId: Int // NUEVO: Llave para que el widget instancie su propia paleta
    }

    // Datos estáticos (ej: nombre de la configuración)
    var presetName: String
}
#endif
