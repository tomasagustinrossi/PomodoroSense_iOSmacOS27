//
//  ScrollWheelBackModifier.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 08/10/2026.
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
                    let isUpward = event.scrollingDeltaY > 3
                    let isMostlyVertical = abs(event.scrollingDeltaX) < abs(event.scrollingDeltaY)
                    let isNotInertia = event.momentumPhase != .changed
                    if isUpward && isMostlyVertical && isNotInertia {
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