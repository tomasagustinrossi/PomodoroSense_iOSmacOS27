//
//  LiveActivityFilter.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 20/10/2026.
//


//
//  LiveActivityFilter.swift
//  PomodoroSense
//
//  Predicados puros para filtrar Live Activities.
//  Separados de ActivityKit para que sean testeables sin runtime.
//

import Foundation

/// Decide qué Live Activities debe tocar cada operación.
///
/// Se mantiene fuera de `Activity<PomodoroAttributes>` a propósito:
/// los predicados son funciones puras (Bool → Bool) y se testean sin
/// necesitar un device iOS con permisos de Live Activity.
enum LiveActivityFilter {

    // MARK: - Reutilizar isla de Pomodoro

    /// `startLiveActivity` usa esta regla para decidir si puede actualizar
    /// una actividad existente o si debe crear una nueva.
    ///
    /// Reglas:
    /// - Activa o stale (no dismissed/ended): reutilizable.
    /// - Cualquier estado de Free Mode: **nunca** reutilizable por Pomodoro
    ///   (y viceversa).
    ///
    /// Antes del fix, solo `.active` era reutilizable. La isla del reward
    /// pasa a `.stale` a los 15 s (`staleDate`), y en la siguiente fase se
    /// creaba una nueva isla, dejando la vieja huérfana (bug A1).
    static func isReusablePomodoro(
        isActive: Bool,
        isStale: Bool,
        isFreeMode: Bool
    ) -> Bool {
        let isLive = isActive || isStale
        return isLive && !isFreeMode
    }

    // MARK: - Cerrar Live Activities

    /// `endAll(freeMode:)` usa esta regla para decidir si una actividad
    /// debe cerrarse.
    ///
    /// - `filter == nil`:     todas (Pomodoro + Free Mode)
    /// - `filter == false`:   solo Pomodoro (Free Mode intacta) → bug A2
    /// - `filter == true`:    solo Free Mode (Pomodoro intacta)
    static func shouldEndAll(isFreeMode: Bool, filter: Bool?) -> Bool {
        guard let filter else { return true }
        return isFreeMode == filter
    }
}