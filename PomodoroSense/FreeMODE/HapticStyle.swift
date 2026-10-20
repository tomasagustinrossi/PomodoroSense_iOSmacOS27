//
//  HapticStyle.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 17/10/2026.
//


//
//  Haptics.swift
//  PomodoroSense
//
//  Wrapper unificado de haptics. No-op en macOS.
//  Usar con intención: cada feedback debe corresponder a un cambio
//  de estado real en la UI (Apple HIG).
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum HapticStyle { case light, medium, heavy, soft, rigid }

enum Haptics {
    #if os(iOS)
    static func impact(_ style: HapticStyle = .light, intensity: CGFloat = 1.0) {
        let s: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light:  s = .light
        case .medium: s = .medium
        case .heavy:  s = .heavy
        case .soft:   s = .soft
        case .rigid:  s = .rigid
        }
        UIImpactFeedbackGenerator(style: s).impactOccurred(intensity: intensity)
    }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning()   { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()     { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    #else
    static func impact(_ style: HapticStyle = .light, intensity: CGFloat = 1.0) {}
    static func selection() {}
    static func success() {}
    static func warning() {}
    static func error() {}
    #endif
}