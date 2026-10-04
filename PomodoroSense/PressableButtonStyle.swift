//
//  UIStyles.swift
//  PomodoroSense
//
//  Estilos reutilizables de botones y componentes UI.
//

import SwiftUI

/// Estilo de botón que da feedback táctil al presionar:
/// escala leve hacia abajo + opacidad reducida, con animación spring corta.
/// Se usa en popups y cards para todo el look "premium" consistente.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var pressedOpacity: Double = 0.85

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}