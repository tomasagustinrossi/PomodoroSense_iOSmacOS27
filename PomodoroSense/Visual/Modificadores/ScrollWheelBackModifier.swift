//
//  ScrollWheelBackModifier.swift
//  PomodoroSense
//

import SwiftUI
#if os(macOS)
import AppKit

struct ScrollWheelBackModifier: ViewModifier {
    let action: () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    // Cualquier scroll vertical con magnitud dispara la acción.
                    // En SavedPresets la lista es horizontal (macOS), así que el
                    // scroll vertical no tiene otro significado.
                    // Funciona con natural scrolling ON u OFF porque usa abs().
                    let isVertical   = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
                    let hasMagnitude = abs(event.scrollingDeltaY) > 3
                    let isNotInertia = event.momentumPhase != .changed
                    if isVertical && hasMagnitude && isNotInertia {
                        action()
                    }
                    return event
                }
            }
            .onDisappear {
                if let m = monitor { NSEvent.removeMonitor(m) }
                monitor = nil
            }
    }
}

extension View {
    func scrollWheelBack(_ action: @escaping () -> Void) -> some View {
        modifier(ScrollWheelBackModifier(action: action))
    }
}
#endif
