import SwiftUI

struct GoalColorTheme {
    let color: Color
    let glow: Color
    let name: String
}

enum GoalColorPalette {
    static let palette: [GoalColorTheme] = [
        .init(color: Color(red: 0.45, green: 0.65, blue: 0.95), glow: .blue, name: "Blue"),
        .init(color: Color(red: 0.90, green: 0.45, blue: 0.45), glow: .red, name: "Red"),
        .init(color: Color(red: 0.50, green: 0.80, blue: 0.50), glow: .green, name: "Green"),
        .init(color: Color(red: 0.95, green: 0.85, blue: 0.45), glow: .yellow, name: "Yellow"),
        .init(color: Color(red: 0.75, green: 0.55, blue: 0.85), glow: .purple, name: "Purple"),
        .init(color: Color(red: 0.85, green: 0.65, blue: 0.45), glow: .orange, name: "Brown"),
    ]

    static func color(for index: Int) -> GoalColorTheme {
        palette[index % palette.count]
    }
}