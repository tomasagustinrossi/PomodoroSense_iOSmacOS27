//
//  VectorWalletView.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 19/10/2026.
//

import SwiftUI

// MARK: - Vector Wallet View

/// Billetera de cuero dibujada con vectores, sin dependencias externas.
struct VectorWalletView: View {
    // Paleta de marrones
    private let leatherDark = Color(red: 0.35, green: 0.18, blue: 0.10)
    private let leatherBase = Color(red: 0.50, green: 0.30, blue: 0.18)
    private let leatherLight = Color(red: 0.65, green: 0.45, blue: 0.30)
    private let stitchColor = Color(red: 0.80, green: 0.65, blue: 0.50)

    var body: some View {
        ZStack {
            // 1. Tarjeta asomando por arriba
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.85))
                .frame(width: 16, height: 8)
                .offset(y: -6)

            // 2. Cuerpo principal de la billetera
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [leatherBase, leatherDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 20)
                .offset(y: 2)

            // 3. Costuras (borde punteado)
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(
                    stitchColor,
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )
                .frame(width: 28, height: 16)
                .offset(y: 2)

            // 4. Solapa / Cierre en el lado derecho
            RoundedRectangle(cornerRadius: 3)
                .fill(leatherLight)
                .frame(width: 12, height: 14)
                .offset(x: 10, y: 2)
                .shadow(color: .black.opacity(0.3), radius: 1, x: -1, y: 0)

            // 5. Botón de presión (snap) en la solapa
            Circle()
                .fill(leatherDark)
                .frame(width: 4, height: 4)
                .offset(x: 10, y: 2)
        }
    }
}
