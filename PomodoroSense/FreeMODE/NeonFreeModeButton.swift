//
//  NeonFreeModeButton.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 17/10/2026.
//


//
//  NeonFreeModeButton.swift
//  PomodoroSense
//
//  Botón "free mode" con efecto neón rojo.
//  - Glow doble (difuso + nítido) alrededor del círculo.
//  - Flicker aleatorio cada 2.5–6s: baja el glow, vuelve, repite 2–3 veces.
//  - Spark: flash blanco + pulso del ícono al final del flicker.
//  - Loop infinito, cancelable.
//

import SwiftUI

struct NeonFreeModeButton: View {
    var size: CGFloat = 48
    var action: () -> Void

    @State private var glowOpacity: Double = 1.0
    @State private var iconScale: CGFloat = 1.0
    @State private var sparkOpacity: Double = 0.0
    @State private var flickerTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            ZStack {
                // Glow externo (difuso, amplio)
                Circle()
                    .fill(Color.red)
                    .frame(width: size * 1.6, height: size * 1.6)
                    .blur(radius: size * 0.45)
                    .opacity(glowOpacity * 0.45)

                // Glow interno (nítido, pegado al borde)
                Circle()
                    .fill(Color.red)
                    .frame(width: size * 1.08, height: size * 1.08)
                    .blur(radius: size * 0.14)
                    .opacity(glowOpacity * 0.8)

                // Cuerpo del botón
                Circle()
                    .fill(Color.black)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().stroke(Color.red, lineWidth: 1.5)
                    )
                    .overlay(
                        Image(systemName: "infinity")
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundColor(.red)
                            .shadow(color: .red.opacity(0.9), radius: 6)
                            .scaleEffect(iconScale)
                    )

                // Flash de chispa (blanco brillante sobre todo)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.85, height: size * 0.85)
                    .blur(radius: size * 0.35)
                    .opacity(sparkOpacity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Free mode")
        .onAppear { startFlickerLoop() }
        .onDisappear { flickerTask?.cancel(); flickerTask = nil }
    }

    // MARK: - Loop de flicker + spark

    private func startFlickerLoop() {
        flickerTask?.cancel()
        flickerTask = Task { @MainActor in
            while !Task.isCancelled {
                // Intervalo aleatorio entre chispazos.
                let interval = Double.random(in: 2.5...6.0)
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }

                // Flicker: 2–3 dips rápidos del glow.
                let dips = Int.random(in: 2...3)
                for _ in 0..<dips {
                    withAnimation(.easeOut(duration: 0.04)) {
                        glowOpacity = 0.15
                    }
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeIn(duration: 0.04)) {
                        glowOpacity = 1.0
                    }
                    try? await Task.sleep(for: .milliseconds(70))
                    guard !Task.isCancelled else { break }
                }

                guard !Task.isCancelled else { break }

                // Spark: flash blanco + pulso del ícono.
                withAnimation(.easeOut(duration: 0.1)) {
                    sparkOpacity = 0.85
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    iconScale = 1.35
                }
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { break }

                withAnimation(.easeOut(duration: 0.35)) {
                    sparkOpacity = 0.0
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    iconScale = 1.0
                }
            }
        }
    }
}