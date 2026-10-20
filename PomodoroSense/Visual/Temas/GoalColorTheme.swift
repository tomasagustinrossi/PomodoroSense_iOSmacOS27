import SwiftUI

// MARK: - Paleta de Colores para Objetivos
struct GoalColorTheme {
    let color: Color
    let glow: Color
}

enum GoalColorPalette {
    // Colores vivos pero no estridentes, para diferenciarse del fondo del calendario.
    static let palette: [GoalColorTheme] = [
        .init(color: Color(red: 0.45, green: 0.65, blue: 0.95), glow: .blue),       // Azul
        .init(color: Color(red: 0.90, green: 0.45, blue: 0.45), glow: .red),        // Rojo
        .init(color: Color(red: 0.50, green: 0.80, blue: 0.50), glow: .green),      // Verde
        .init(color: Color(red: 0.95, green: 0.85, blue: 0.45), glow: .yellow),     // Amarillo
        .init(color: Color(red: 0.75, green: 0.55, blue: 0.85), glow: .purple),     // Púrpura
        .init(color: Color(red: 0.85, green: 0.65, blue: 0.45), glow: .orange),     // Marrón/Naranja
    ]

    static func theme(for goal: DailyGoal) -> GoalColorTheme {
        // Usamos el día del mes para que los colores roten de forma variada y predecible.
        let day = Calendar.current.component(.day, from: goal.dayStart)
        return palette[abs(day) % palette.count]
    }
}

// MARK: - Estrella con animación de tachado
struct StrikethroughStar: View {
    let color: Color
    let isCompleted: Bool
    @State private var trimEnd: CGFloat = 0

    var body: some View {
        ZStack {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isCompleted ? .gray : color)
                .shadow(color: isCompleted ? .clear : color.opacity(0.8), radius: 3)

            if isCompleted {
                Path { path in
                    // Diagonal desde arriba a la izquierda hasta abajo a la derecha
                    path.move(to: CGPoint(x: -6, y: -6))
                    path.addLine(to: CGPoint(x: 6, y: 6))
                }
                .trim(from: 0, to: trimEnd)
                .stroke(Color.gray, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .onAppear {
                    withAnimation(.easeOut(duration: 0.4)) {
                        trimEnd = 1
                    }
                }
            }
        }
        .frame(width: 16, height: 16)
    }
}
