import SwiftUI

struct NeonFreeModeButton: View {
    
    enum ArrowDirection {
        case right, down
        
        var systemName: String {
            switch self {
            case .right: return "arrow.right"
            case .down:  return "arrow.down"
            }
        }
    }

    var direction: ArrowDirection = {
        #if os(iOS)
        return .down
        #else
        return .right
        #endif
    }()

    var action: () -> Void

    // Mismo color que usa la app para los títulos (un toque más visible)
    private let textColor = Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.5)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("FREE MODE")
                    // Misma tipografía que el título "SAVED PRESETS"
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .tracking(2.5)
                    .foregroundColor(textColor)
                
                Image(systemName: direction.systemName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(textColor)
                    .frame(width: 30, height: 30) // Hit area invisible
                    .contentShape(Rectangle())    // Fuerza el área táctil
            }
            // Padding invisible: le da el tamaño al botón para que sea fácil de tocar
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            // Fuerza a que TODO ese rectángulo invisible reciba el toque
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
