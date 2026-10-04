import SwiftUI

/// Panel de JACKPOT para el widget (Lock Screen + Dynamic Island).
/// Diseño estático con múltiples chips radiales, texto grande y glow.
/// La animación real vive en la app (SessionRewardPopup).
struct JackpotPanel: View {
    let reward: SessionRewardPayload
    let theme: PomodoroTheme

    var body: some View {
        ZStack {
            // ─── Capa de chips flotantes (radial) ───
            chipBurst

            // ─── Contenido central ───
            VStack(spacing: 6) {
                Text("JACKPOT")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .tracking(6)
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.9), radius: 12)
                    .shadow(color: .yellow.opacity(0.5), radius: 24)

                HStack(spacing: 8) {
                    Text("+\(reward.chipsEarned)")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)

                    Text("CHIPS")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.75))
                }

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)
                    Text("\(reward.newStreak) DAY STREAK")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
        .background(
            // Fondo con degradado dorado sutil
            LinearGradient(
                colors: [
                    Color.yellow.opacity(0.08),
                    Color.clear,
                    Color.yellow.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Chips radiales (efecto burst)

    /// Posiciones predeterminadas: crean un "burst" estático que rodea al texto.
    /// Cada chip tiene offset, rotación y opacidad propios para dar sensación de
    /// profundidad y movimiento.
    private var chipBurst: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let chips: [(x: CGFloat, y: CGFloat, size: CGFloat, rotation: Double, opacity: Double)] = [
                // Fila superior
                (0.08, 0.18, 18, -25, 0.9),
                (0.22, 0.06, 14,  35, 0.7),
                (0.50, 0.02, 22, -15, 0.95),
                (0.78, 0.06, 14,  40, 0.7),
                (0.92, 0.18, 18,  25, 0.9),
                // Laterales
                (0.04, 0.55, 16, -60, 0.8),
                (0.96, 0.55, 16,  60, 0.8),
                // Fila inferior
                (0.12, 0.85, 15,  15, 0.6),
                (0.32, 0.95, 20, -30, 0.85),
                (0.68, 0.95, 20,  30, 0.85),
                (0.88, 0.85, 15, -15, 0.6),
                // Extra (chips chicos)
                (0.42, 0.30, 10,  50, 0.35),
                (0.58, 0.30, 10, -50, 0.35),
            ]

            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                MiniChipShape(size: chip.size)
                    .rotationEffect(.degrees(chip.rotation))
                    .opacity(chip.opacity)
                    .position(x: w * chip.x, y: h * chip.y)
            }
        }
    }
}

/// Chip minimalista vectorial para el burst. Solo el contorno y las muescas
/// esenciales, para que se vea limpio a tamaños chicos.
struct MiniChipShape: View {
    var size: CGFloat
    var tint: Color = .yellow

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(0.95),
                            tint.opacity(0.6)
                        ],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: size * 0.08)

            // 6 muescas en vez de 8: más limpio a tamaño chico
            ForEach(0..<6, id: \.self) { i in
                RoundedRectangle(cornerRadius: size * 0.02)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: size * 0.10, height: size * 0.18)
                    .offset(y: -size * 0.38)
                    .rotationEffect(.degrees(Double(i) * 60))
            }

            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: size * 0.35, height: size * 0.35)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.7), lineWidth: size * 0.04)
                )
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.7), radius: size * 0.15)
    }
}