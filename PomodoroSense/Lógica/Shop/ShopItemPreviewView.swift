//
//  ShopItemPreviewView.swift
//  PomodoroSense
//
//  `flat: true` -> icono 2D con el metal de la sección (grids, listas).
//  `flat: false` -> 3D rotable (popup de detalle, vitrina).
//

import SwiftUI

struct ShopItemPreviewView: View {
    let item: any ShopItem
    var size: CGFloat = 220
    var autoRotate: Bool = true
    var tint: Color = .white        // compatibilidad (el color ahora lo define la sección)
    var depth: CGFloat = 24         // compatibilidad (el grosor va en el visual)
    var interactive: Bool = true
    var flat: Bool = false          // true = versión 2D
    var dimmed: Bool = false        // true = atenuado (p. ej. ya comprado)
    var straight: Bool = false

    var body: some View {
            Group {
                if flat {
                    FlatIconView(visual: item.visual, category: item.category, size: size)
                } else {
                    Model3DView(
                        visual: item.visual,
                        category: item.category,
                        size: size,
                        autoRotate: autoRotate,
                        interactive: interactive,
                        straight: straight // <-- PASAR ACÁ
                    )
                }
            }
        .opacity(dimmed ? 0.5 : 1)
    }
}
