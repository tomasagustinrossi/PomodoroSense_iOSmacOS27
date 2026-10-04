//
//  SavedPresetsKeyboard.swift
//  PomodoroSense
//
//  Lógica pura de teclado para SavedPresetsView.
//  Aislada de SwiftUI/AppKit para poder testearla.
//

import Foundation

/// Zonas focusables de SavedPresetsView.
enum SavedPresetsFocus: Hashable, CaseIterable {
    case presetList
    case navSearch
    case navStats
    case navSync
    case navPlus

    /// Orden de ciclado con Tab.
    static let cycleOrder: [SavedPresetsFocus] = [
        .presetList, .navSearch, .navStats, .navSync, .navPlus
    ]
}

/// Qué hacer cuando el usuario aprieta Enter en cada zona.
enum SavedPresetsEnterAction: Equatable {
    case toggleSearch
    case showStats
    case showSync
    case newPreset
    case startSelectedPreset
}

/// Qué hacer cuando el usuario aprieta Space.
enum SavedPresetsSpaceAction: Equatable {
    case toggleTimer       // hay timer corriendo → pausar/reanudar
    case startSelectedPreset
    case none
}

enum SavedPresetsKeyboard {

    // MARK: - Tab / Shift+Tab

    /// Devuelve la zona siguiente (o anterior si `forward == false`).
    /// Si `current` es `nil`, arranca desde el primero (o el último).
    static func cycle(
        from current: SavedPresetsFocus?,
        forward: Bool
    ) -> SavedPresetsFocus {
        let order = SavedPresetsFocus.cycleOrder
        guard let current, let idx = order.firstIndex(of: current) else {
            return forward ? order.first! : order.last!
        }
        let next = forward
            ? (idx + 1) % order.count
            : (idx - 1 + order.count) % order.count
        return order[next]
    }

    // MARK: - Enter

    static func enterAction(for zone: SavedPresetsFocus?) -> SavedPresetsEnterAction {
        switch zone {
        case .navSearch:        return .toggleSearch
        case .navStats:         return .showStats
        case .navSync:          return .showSync
        case .navPlus:          return .newPreset
        case .presetList, .none: return .startSelectedPreset
        }
    }

    // MARK: - Space

    static func spaceAction(
        isTimerActive: Bool,
        focusedZone: SavedPresetsFocus?
    ) -> SavedPresetsSpaceAction {
        // Regla: si hay timer corriendo, Space siempre togglea el timer.
        if isTimerActive { return .toggleTimer }
        // Sin timer: Space arranca el preset si el foco está en la lista.
        if focusedZone == .presetList { return .startSelectedPreset }
        return .none
    }

    // MARK: - Flechas ← / →

    /// Devuelve el nuevo índice dado el actual, el total y un offset.
    /// Wrap-around: de 0 con -1 va al último; del último con +1 va al primero.
    /// Si `currentIndex == nil`, +1 → 0, -1 → count-1.
    static func movePresetIndex(
        currentIndex: Int?,
        count: Int,
        offset: Int
    ) -> Int? {
        guard count > 0 else { return nil }
        let base: Int
        if let currentIndex, currentIndex >= 0, currentIndex < count {
            base = currentIndex
        } else {
            // Ningún preset seleccionado: si vamos hacia la derecha
            // empezamos por el primero; hacia la izquierda, por el último.
            base = offset > 0 ? -1 : count
        }
        return ((base + offset) % count + count) % count
    }
}