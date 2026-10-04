//
//  FreeModeSession.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 17/10/2026.
//


//
//  FreeModeSession.swift
//  PomodoroSense
//

import Foundation

/// Una sesión de estudio guardada en Free Mode.
struct FreeModeSession: Codable, Identifiable, Hashable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let musicTitle: String?

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        musicTitle: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.musicTitle = musicTitle
    }
}