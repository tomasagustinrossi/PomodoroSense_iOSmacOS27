//
//  DailyGoal.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 17/10/2026.
//


import Foundation

struct DailyGoal: Codable, Identifiable, Hashable {
    let id: UUID
    let dayStart: Date
    var text: String
    var completed: Bool
    let createdAt: Date

    init(id: UUID = UUID(), dayStart: Date, text: String,
         completed: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.dayStart = dayStart
        self.text = text
        self.completed = completed
        self.createdAt = createdAt
    }
}