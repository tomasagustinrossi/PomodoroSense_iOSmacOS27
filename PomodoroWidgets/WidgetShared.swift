//
//  WidgetShared.swift
//  PomodoroSense
//
//  Código compartido entre la app y los widgets (iOS + macOS).
//  Contiene el App Group, las claves de UserDefaults compartidos,
//  y helpers de lectura/escritura para que cada widget no conozca
//  los strings mágicos ni la mecánica de persistencia.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Estado del timer compartido

/// Snapshot del timer que la app escribe y los widgets leen.
/// Codable para poder serializarlo como JSON en UserDefaults.
nonisolated struct WidgetTimerState: Codable, Equatable {
    var isRunning: Bool
    var isBreak: Bool
    var currentSession: Int
    var totalSessions: Int
    var targetDate: Date?          // nil si está pausado o idle
    var pausedSeconds: Int?        // nil si corre
    var noiseId: Int
    var presetName: String

    static let idle = WidgetTimerState(
        isRunning: false,
        isBreak: false,
        currentSession: 1,
        totalSessions: 5,
        targetDate: nil,
        pausedSeconds: nil,
        noiseId: 0,
        presetName: "—"
    )
}

/// Snapshot de la economía del usuario.
nonisolated struct WidgetEconomyState: Codable, Equatable {
    var bronze: Int
    var silver: Int
    var gold: Int
    var streak: Int
    var hasRecordsToday: Bool

    static let empty = WidgetEconomyState(
        bronze: 0,
        silver: 0,
        gold: 0,
        streak: 0,
        hasRecordsToday: false
    )
}

// MARK: - Acceso al App Group

nonisolated enum WidgetShared {

    /// App Group compartido entre la app y los widgets.
    /// ⚠️ Debe coincidir EXACTAMENTE con el configurado en
    /// Signing & Capabilities de los 3 targets.
    static let appGroupId = "group.com.tomiirossi.PomodoroSense"

    // MARK: Claves de UserDefaults

    private enum Keys {
        static let timerState   = "widget.timer.state"
        static let economyState = "widget.economy.state"
    }

    // MARK: UserDefaults del App Group


    /// UserDefaults compartido. Si el App Group no está accesible
    /// (target sin App Sandbox, provisioning mal, etc.) cae a `.standard`
    /// PERO loggea el error: el fallback es silencioso por compatibilidad,
    /// pero queremos saber cuándo pasa.
    private static var defaults: UserDefaults {
        if let shared = UserDefaults(suiteName: appGroupId) {
            return shared
        }
        #if DEBUG
        print("⚠️ [WidgetShared] App Group '\(appGroupId)' no accesible. Cayendo a .standard (los widgets NO verán datos reales).")
        #endif
        return .standard
    }

    // MARK: Escritura (llamada desde la app)

    static func writeTimerState(_ state: WidgetTimerState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Keys.timerState)
    }

    static func writeEconomyState(_ state: WidgetEconomyState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Keys.economyState)
    }

    // MARK: Lectura (llamada desde los widgets)

    static func readTimerState() -> WidgetTimerState {
        guard let data = defaults.data(forKey: Keys.timerState),
              let decoded = try? JSONDecoder().decode(WidgetTimerState.self, from: data)
        else { return .idle }
        return decoded
    }

    static func readEconomyState() -> WidgetEconomyState {
        guard let data = defaults.data(forKey: Keys.economyState),
              let decoded = try? JSONDecoder().decode(WidgetEconomyState.self, from: data)
        else { return .empty }
        return decoded
    }

    // MARK: Reload de widgets

    /// Pide a WidgetKit que recargue todas las timelines.
    /// Llamar solo cuando algo relevante cambió (fase, pause, sesión).
    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

