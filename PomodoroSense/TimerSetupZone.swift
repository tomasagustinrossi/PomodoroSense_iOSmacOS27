//
//  TimerSetupKeyboard.swift
//  PomodoroSense
//
//  Lógica pura de teclado para PomodoroSettingsView.
//  Aislada de SwiftUI/AppKit para testearla.
//

import Foundation

/// Zonas focusables del Timer Setup, en orden de ciclado.
enum TimerSetupZone: Hashable, CaseIterable {
    case name
    case focus
    case breakTime
    case sessions
    case preset
    case sound
    case waves
    case save

    static let cycleOrder: [TimerSetupZone] = [
        .name, .focus, .breakTime, .sessions, .preset, .sound, .waves, .save
    ]

    var isNumeric: Bool {
        switch self {
        case .focus, .breakTime, .sessions: return true
        default: return false
        }
    }

    var isPicker: Bool {
        switch self {
        case .preset, .sound, .waves: return true
        default: return false
        }
    }
}

enum TimerSetupKeyboard {

    /// Ciclo Tab / Shift+Tab.
    static func cycle(from current: TimerSetupZone, forward: Bool) -> TimerSetupZone {
        let order = TimerSetupZone.cycleOrder
        guard let idx = order.firstIndex(of: current) else { return .name }
        let next = forward
            ? (idx + 1) % order.count
            : (idx - 1 + order.count) % order.count
        return order[next]
    }

    /// Wrap para ciclar opciones de un picker con ←/→.
    static func movePickerIndex(current: Int, count: Int, offset: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((current + offset) % count + count) % count
    }

    /// Clamp para incrementar/decrementar un campo numérico.
    static func clampNumeric(value: Int, offset: Int, range: ClosedRange<Int>) -> Int {
        min(max(value + offset, range.lowerBound), range.upperBound)
    }
}