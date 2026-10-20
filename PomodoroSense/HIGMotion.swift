//
//  HIGMotion.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 17/10/2026.
//


//
//  HIGDesign.swift
//  PomodoroSense
//
//  Tokens compartidos de interfaz (iOS y macOS), alineados con las HIG de Apple.
//  Solo para el target de la APP (el widget no lo necesita).
//
import SwiftUI

// MARK: - Movimiento (todo con física de resorte, nada lineal)

enum HIGMotion {
    /// Navegación entre pantallas.
    static var navigate: Animation { .spring(response: 0.4, dampingFraction: 0.85) }
    /// Cambios de estado visibles (play/pausa, aparición de controles).
    static var state: Animation { .spring(response: 0.35, dampingFraction: 0.82) }
    /// Popups, sheets y scrims.
    static var overlay: Animation { .spring(response: 0.32, dampingFraction: 0.8) }
    /// Respuesta inmediata al toque (escala al presionar).
    static var press: Animation { .spring(response: 0.25, dampingFraction: 0.7) }
    /// Cambio de color de fase (foco ↔ descanso): un resorte sin rebote, lento.
    static var phase: Animation { .smooth(duration: 1.0) }
    /// Avance del aro de progreso (reemplaza al `.linear`).
    static var progress: Animation { .smooth(duration: 0.6) }
    /// Dígitos del reloj.
    static var numeric: Animation { .snappy(duration: 0.3) }
}

// MARK: - Press: escala + opacidad con resorte

/// Estilo de botón para TODA la app: al presionar se hunde levemente y vuelve con resorte.
/// Reemplaza a `.plain` (que no da ninguna respuesta visual al tacto).
struct HIGPressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(HIGMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == HIGPressableButtonStyle {
    /// `.buttonStyle(.pressable)`
    static var pressable: HIGPressableButtonStyle { HIGPressableButtonStyle() }
}

// MARK: - Scrim translúcido

/// Fondo de popups: material + velo oscuro suave. Siempre en oscuro porque los
/// temas de la app son oscuros aunque el sistema esté en modo claro.
struct HIGScrim: View {
    var onTap: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.25)
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Radios (siempre con `style: .continuous`)

enum HIGRadius {
    /// Chips, campos y botones chicos.
    static let control: CGFloat = 10
    /// Tarjetas y filas agrupadas.
    static let card: CGFloat = 16
    /// Popups y sheets.
    static let popup: CGFloat = 24
}

// MARK: - Transiciones

extension AnyTransition {
    /// Entrada/salida estándar de popups: escala suave + fade.
    static var higPopup: AnyTransition {
        .scale(scale: 0.95).combined(with: .opacity)
    }
}
