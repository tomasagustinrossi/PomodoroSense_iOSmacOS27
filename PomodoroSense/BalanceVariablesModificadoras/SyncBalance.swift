//
//  SyncBalance.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 12/10/2026.
//


//
//  SyncBalance.swift
//  PomodoroSense
//
//  ⚠️ SOLO consumir desde: SyncManager, PomodoroWidgetBridge.
//     La UI NUNCA accede directo.
//
//  Parámetros de tolerancia, TTLs y cleanup del sistema de sync.
//

import Foundation

nonisolated enum SyncBalance {

    // MARK: - Timestamps y ventanas

    /// Ventana de validez de un envelope. Si el delta entre el timestamp
    /// del mensaje y `Date()` supera esto, se descarta.
    /// Ej: reloj desfasado 60s → se acepta (dentro de 90s).
    static let envelopeToleranceSeconds: TimeInterval = 90

    /// Vida útil de un nonce en el cache anti-replay.
    /// Ej: nonce visto hace 60s → sigue bloqueado. A los 120s → se olvida.
    static let nonceLifetimeSeconds: TimeInterval = 120

    /// Intervalo de limpieza del cache de nonces.
    /// Ej: cada 60s se barren los nonces viejos.
    static let nonceCleanupIntervalSeconds: TimeInterval = 60

    // MARK: - Comandos del widget

    /// Vida útil de un comando del widget desde que se emitió hasta que
    /// la app lo lee. Comandos más viejos se descartan.
    /// Ej: toqué PAUSE en el widget y no abrí la app por 20s → se ignora.
    static let widgetCommandTTL: TimeInterval = 15

    // MARK: - Buffer de recepción

    /// Tamaño mínimo del length prefix del framing TCP.
    /// Ej: los mensajes empiezan con 4 bytes de longitud big-endian.
    static let frameLengthPrefixBytes = 4

    /// Tamaño máximo del buffer de recepción antes de abortar.
    /// Ej: si supera 1 MB sin poder parsear, hay corrupción → cortamos.
    static let maxReceiveBufferBytes = 1_048_576

    // MARK: - Red

    /// Máximo tamaño de un chunk de recepción TCP.
    /// Ej: 64 KB por chunk es un balance razonable.
    static let maxReceiveChunkBytes = 65_536
}