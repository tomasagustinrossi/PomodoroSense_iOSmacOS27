//
//  SavedPresetsFocus.swift
//  PomodoroSense
//

import Foundation

enum SavedPresetsFocus: Hashable, CaseIterable {
    case presetList
    case navSearch
    case navStats
    case navSync
    case navFreeMode
    case navShop
    case navPlus

    static let cycleOrder: [SavedPresetsFocus] = [
        .presetList, .navSearch, .navStats, .navSync, .navFreeMode, .navShop, .navPlus
    ]
}

enum SavedPresetsEnterAction: Equatable {
    case toggleSearch
    case showStats
    case showSync
    case showShop          // ← NUEVO
    case startFreeMode
    case newPreset
    case startSelectedPreset
}

enum SavedPresetsSpaceAction: Equatable {
    case toggleTimer
    case startSelectedPreset
    case none
}

enum SavedPresetsKeyboard {

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

    static func enterAction(for zone: SavedPresetsFocus?) -> SavedPresetsEnterAction {
        switch zone {
        case .navSearch:         return .toggleSearch
        case .navStats:          return .showStats
        case .navSync:           return .showSync
        case .navShop:           return .showShop     // ← NUEVO
        case .navFreeMode:       return .startFreeMode
        case .navPlus:           return .newPreset
        case .presetList, .none: return .startSelectedPreset
        }
    }

    static func spaceAction(
        isTimerActive: Bool,
        focusedZone: SavedPresetsFocus?
    ) -> SavedPresetsSpaceAction {
        if isTimerActive { return .toggleTimer }
        if focusedZone == .presetList { return .startSelectedPreset }
        return .none
    }

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
            base = offset > 0 ? -1 : count
        }
        return ((base + offset) % count + count) % count
    }
}
