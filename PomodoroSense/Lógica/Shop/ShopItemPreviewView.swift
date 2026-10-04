//
//  ShopItemPreviewView.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 18/10/2026.
//


//
//  ShopItemPreviewView.swift
//  PomodoroSense
//
//  Misma firma que antes: ShopView y OwnedItemsView no necesitan cambios.
//

import SwiftUI

struct ShopItemPreviewView: View {
    let item: any ShopItem
    var size: CGFloat = 220
    var autoRotate: Bool = true
    var tint: Color = .white        // compatibilidad (el color ahora lo define la sección)
    var depth: CGFloat = 24         // compatibilidad (el grosor va en el visual)
    var interactive: Bool = true

    var body: some View {
        Model3DView(
            visual: item.visual,
            category: item.category,
            size: size,
            autoRotate: autoRotate,
            interactive: interactive
        )
    }
}