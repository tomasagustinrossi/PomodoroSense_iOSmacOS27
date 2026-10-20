//
//  FlatIconView.swift
//  PomodoroSense
//
//  Versión 2D del item: la MISMA silueta procesada que se extruye en 3D
//  (limpia, con huecos), pintada con el metal de la sección.
//  Para visuals sin silueta 2D (.model3D / .procedural) cae a una vista 3D estática.
//

import SwiftUI

/// Dibuja los contornos normalizados [-1, 1] (y hacia arriba) dentro de un rect.
struct LoopsShape: Shape {
    let loops: [[CGPoint]]
    var padding: CGFloat = 0.92

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 2 * padding
        var path = Path()
        for loop in loops {
            guard let first = loop.first else { continue }
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: rect.midX + p.x * s, y: rect.midY - p.y * s)
            }
            path.move(to: map(first))
            for p in loop.dropFirst() { path.addLine(to: map(p)) }
            path.closeSubpath()
        }
        return path
    }
}

struct FlatIconView: View {
    let visual: ShopItemVisual
    let category: ShopCategory
    var size: CGFloat = 70

    var body: some View {
        Group {
            if let loops = ExtrudedIcon.contours(for: visual), !loops.isEmpty {
                flat(loops)
            } else {
                Model3DView(visual: visual, category: category,
                            size: size, autoRotate: false, interactive: false)
            }
        }
        .frame(width: size, height: size)
    }

    private func flat(_ loops: [[CGPoint]]) -> some View {
        let m = category.metal
        let shape = LoopsShape(loops: loops)
        let eo = FillStyle(eoFill: true)

        return ZStack {
            // Cuerpo metálico: barrido de brillo diagonal
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: m.lightColor, location: 0.0),
                        .init(color: m.baseColor, location: 0.35),
                        .init(color: m.midDarkColor, location: 0.70),
                        .init(color: m.baseColor, location: 0.88),
                        .init(color: m.darkColor, location: 1.0)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                style: eo
            )

            // Bisel interior: canto claro arriba-izquierda, oscuro abajo-derecha
            shape
                .stroke(
                    LinearGradient(
                        colors: [m.shineColor.opacity(0.95), .clear, m.darkColor.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: size * 0.05
                )
                .clipShape(shape, style: eo)
        }
        .shadow(color: .black.opacity(0.45), radius: size * 0.04, x: 0, y: size * 0.03)
    }
}
