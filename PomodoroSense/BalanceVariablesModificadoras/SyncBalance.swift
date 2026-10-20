//
//  SyncBalance.swift
//  PomodoroSense
//
//  ⚠️ SOLO consumir desde: PomodoroWidgetBridge.
//     La UI NUNCA accede directo.
//
//  Parámetros del sistema de sync.
//

import Foundation

nonisolated enum SyncBalance {

    /// Vida útil de un comando del widget desde que se emitió hasta que
    /// la app lo lee. Comandos más viejos se descartan.
    /// Ej: toqué PAUSE en el widget y no abrí la app por 20s → se ignora.
    static let widgetCommandTTL: TimeInterval = 15
}
