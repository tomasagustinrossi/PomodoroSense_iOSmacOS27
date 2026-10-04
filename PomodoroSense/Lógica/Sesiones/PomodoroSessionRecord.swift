//
//  PomodoroSessionRecord.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 08/10/2026.
//


import Foundation

// MARK: - Registro de una sesión de foco completada
struct PomodoroSessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let dayStart: Date            // Día normalizado (startOfDay)
    let timestamp: Date           // Hora exacta del completado
    let presetName: String
    let focusMinutes: Int         // Duración de cada sesión
    let sessionNumber: Int        // 1-based
    let totalSessions: Int        // Total del preset (para detectar "todas")
}

// MARK: - Perfil de usuario (invisible, para futuro)
struct UserProfile: Codable, Hashable {
    let id: UUID
    var displayName: String?
    var joinedAt: Date
    var trophiesOwned: [String]   // IDs de trofeos comprados en la tienda

    static func makeDefault() -> UserProfile {
        UserProfile(id: UUID(),
                    displayName: nil,
                    joinedAt: Date(),
                    trophiesOwned: [])
    }
}

// MARK: - Cálculo de puntos estilo casino
enum ScoreCalculator {

    /// Chips base por minutos de foco. Curva con aceleración leve.
    /// 30min → 6, 45min → 10, 60min → 14, 90min → 22
    static func baseChips(forMinutes minutes: Int) -> Int {
        let linear = minutes / 5
        let bonus  = max(0, minutes - 30) / 15
        return linear + bonus
    }

    /// Racha de días consecutivos con al menos 1 sesión. Cap en 3.0x.
    /// 1 día = 1.0x, 2 = 1.2x, 3 = 1.4x, 5 = 1.8x, 10+ = 3.0x
    static func streakMultiplier(consecutiveDays: Int) -> Double {
        let raw = 1.0 + Double(max(0, consecutiveDays - 1)) * 0.2
        return min(raw, 3.0)
    }

    /// Combo del mismo día.
    /// 1 sesión: "WARM UP" +0
    /// 2 sesiones: "COMBO x2" +5
    /// 3+ sesiones: "HOT STREAK" +15
    /// Todas las del preset: "JACKPOT" +50
    static func comboBonus(sessionsToday: Int, totalInPreset: Int) -> Int {
        if sessionsToday <= 1 { return 0 }
        if sessionsToday >= totalInPreset { return 50 }
        if sessionsToday >= 3 { return 15 }
        return 5
    }

    /// Etiqueta simbólica del día (para la UI)
    static func comboLabel(sessionsToday: Int, totalInPreset: Int) -> String {
        if sessionsToday <= 0 { return "" }
        if sessionsToday >= totalInPreset { return "JACKPOT" }
        if sessionsToday >= 3 { return "HOT STREAK" }
        if sessionsToday == 2 { return "COMBO x2" }
        return "WARM UP"
    }

    /// Score total diario dado un conjunto de records del mismo día.
    static func dailyScore(
        records: [PomodoroSessionRecord],
        streakDays: Int
    ) -> Int {
        guard !records.isEmpty else { return 0 }
        let totalMinutes = records.reduce(0) { $0 + $1.focusMinutes }
        let totalInPreset = records.first?.totalSessions ?? 1
        let sessionsToday = records.count

        let base = baseChips(forMinutes: totalMinutes)
        let multiplier = streakMultiplier(consecutiveDays: streakDays)
        let combo = comboBonus(sessionsToday: sessionsToday, totalInPreset: totalInPreset)

        let raw = Double(base) * multiplier + Double(combo)
        return Int(raw.rounded())
    }
}