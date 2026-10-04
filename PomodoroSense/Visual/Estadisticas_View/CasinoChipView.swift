//
//  CasinoChipView.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 08/10/2026.
//


// MARK: - Ficha de casino (ícono vectorial)

struct CasinoChipView: View {
    var size: CGFloat = 20
    var tint: Color = .orange

    var body: some View {
        ZStack {
            // Cuerpo con gradiente radial (da efecto de relieve)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(0.98),
                            tint.opacity(0.72)
                        ],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )

            // Borde blanco fino
            Circle()
                .stroke(Color.white.opacity(0.55), lineWidth: size * 0.055)

            // 8 muescas perimetrales (como las fichas reales)
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: size * 0.02)
                    .fill(Color.white.opacity(0.88))
                    .frame(width: size * 0.075, height: size * 0.14)
                    .offset(y: -size * 0.385)
                    .rotationEffect(.degrees(Double(i) * 45))
            }

            // Anillo interior con dashes (patrón clásico de ficha)
            Circle()
                .stroke(
                    Color.white.opacity(0.6),
                    style: StrokeStyle(
                        lineWidth: size * 0.045,
                        dash: [size * 0.05, size * 0.045]
                    )
                )
                .padding(size * 0.19)

            // Disco central
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: size * 0.30, height: size * 0.30)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.75), lineWidth: size * 0.028)
                )

            // Punto interior mínimo (da el "toque" final)
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: size * 0.07, height: size * 0.07)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1.5)
        .shadow(color: tint.opacity(0.35), radius: 5, x: 0, y: 0)
    }
}