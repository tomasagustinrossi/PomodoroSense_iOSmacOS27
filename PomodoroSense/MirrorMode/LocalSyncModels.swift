//
//  LocalSyncModels.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 15/10/2026.
//

import Foundation

// MARK: - Roles

enum LocalSyncRole: String, Codable, Sendable {
    case master
    case mirror
}

// MARK: - Mensaje que viaja por TCP

struct HelloMessage: Codable, Sendable, Equatable {
    let deviceName: String
    let peerId: UUID
    let preferredRole: LocalSyncRole
}

/// Cada caso es un tipo de mensaje. Al ser un enum con valores asociados, `Codable` se genera
/// solo y el contenido se codifica una única vez (antes iba JSON dentro de JSON en base64).
enum SyncMessage: Codable, Sendable {
    case masterState(MasterTimerState)
    case mirrorCommand(MirrorCommand)
    case roleSwap
    case hello(HelloMessage)
    /// El emisor se desvincula a propósito: el receptor NO debe reconectar solo.
    case unlink
}

// MARK: - Estado del timer (Master -> Mirror)

/// La fuente de la verdad que envía el Master al conectar y en cada cambio.
struct MasterTimerState: Codable, Sendable, Equatable {
    let isRunning: Bool
    let isBreak: Bool
    let currentSession: Int
    let totalSessions: Int

    /// Cuándo termina el timer. Solo tiene sentido si `isRunning` es true.
    let targetDate: Date?

    /// Segundos restantes cuando el timer está en pausa (sin `targetDate` el Mirror no sabría qué mostrar).
    var pausedSeconds: Int? = nil

    // Configuración actual
    let presetName: String
    let noiseId: Int
    let freqId: Int
}

// MARK: - Comandos del Mirror (Mirror -> Master)

/// Acciones que el usuario presiona en el dispositivo Mirror.
enum MirrorCommand: String, Codable, Sendable {
    case toggleTimer
    case skipNext
    case skipPrevious
    case stop
}
