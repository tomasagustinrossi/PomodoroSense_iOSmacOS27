//
//  SessionStore.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 08/10/2026.
//


import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var records: [PomodoroSessionRecord] = []
    @Published private(set) var user: UserProfile = .makeDefault()

    private let recordsKey = "Pomodoro_Session_Records"
    private let userKey    = "Pomodoro_User_Profile"

    private init() { load() }

    // MARK: - Registro

    func recordCompletedSession(
        presetName: String,
        focusMinutes: Int,
        sessionNumber: Int,
        totalSessions: Int
    ) {
        let cal = Calendar.current
        let now = Date()
        let record = PomodoroSessionRecord(
            id: UUID(),
            dayStart: cal.startOfDay(for: now),
            timestamp: now,
            presetName: presetName,
            focusMinutes: focusMinutes,
            sessionNumber: sessionNumber,
            totalSessions: totalSessions
        )
        records.append(record)
        persist()
    }

    // MARK: - Consultas para la UI

    /// Todos los records de un día concreto.
    func records(on day: Date) -> [PomodoroSessionRecord] {
        let cal = Calendar.current
        let target = cal.startOfDay(for: day)
        return records.filter { cal.isDate($0.dayStart, inSameDayAs: target) }
    }

    /// Minutos totales de foco en un día.
    func totalFocusMinutes(on day: Date) -> Int {
        records(on: day).reduce(0) { $0 + $1.focusMinutes }
    }

    /// Score de un día.
    func score(on day: Date) -> Int {
        let dayRecords = records(on: day)
        guard !dayRecords.isEmpty else { return 0 }
        let streak = streakEnding(on: day)
        return ScoreCalculator.dailyScore(records: dayRecords, streakDays: streak)
    }

    /// Chips totales acumulados (todos los días).
    var totalChips: Int {
        // Agrupamos por día y sumamos cada score diario
        let grouped = Dictionary(grouping: records) { $0.dayStart }
        return grouped.reduce(0) { acc, pair in
            let day = pair.key
            let dayRecords = pair.value
            let streak = streakEnding(on: day)
            return acc + ScoreCalculator.dailyScore(records: dayRecords, streakDays: streak)
        }
    }

    /// Días consecutivos hacia atrás con al menos 1 sesión, terminando en `day`.
    func streakEnding(on day: Date) -> Int {
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: day)
        var streak = 0
        let daysWithSessions = Set(records.map { $0.dayStart })

        while daysWithSessions.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Racha actual (terminando hoy).
    var currentStreak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let daysWithSessions = Set(records.map { $0.dayStart })

        // Si hoy no hay sesión, probamos desde ayer (la racha "sigue viva" hasta fin del día).
        if !daysWithSessions.contains(today) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                  daysWithSessions.contains(yesterday) else { return 0 }
            return streakEnding(on: yesterday)
        }
        return streakEnding(on: today)
    }

    /// Etiqueta de combo para un día (WARM UP / COMBO / HOT STREAK / JACKPOT).
    func comboLabel(on day: Date) -> String {
        let dayRecords = records(on: day)
        guard let first = dayRecords.first else { return "" }
        return ScoreCalculator.comboLabel(
            sessionsToday: dayRecords.count,
            totalInPreset: first.totalSessions
        )
    }

    // MARK: - Persistencia

    private func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([PomodoroSessionRecord].self, from: data) {
            records = decoded
        }

        if let data = defaults.data(forKey: userKey),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            user = decoded
        } else {
            user = .makeDefault()
            persistUser()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    private func persistUser() {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    // MARK: - API para tienda futura
    func addTrophy(_ id: String) {
        user.trophiesOwned.append(id)
        persistUser()
    }
}