//
//  MetalStyle.swift
//  PomodoroSense
//
//  Un "estilo de metal" por sección (bronze / silver / gold).
//  Agregar una sección nueva = agregar un case en ShopCategory + un MetalStyle acá.
//

import SceneKit
import CoreGraphics
import SwiftUI

struct MetalStyle: Hashable {
    let r: Double, g: Double, b: Double
    var roughness: Double
    var metalness: Double = 1.0

    // Ajustá estos valores para cambiar el acabado de toda una sección.
    // roughness bajo = espejo brillante · alto = satinado/mate (como la foto 2).
    static let bronze = MetalStyle(r: 0.80, g: 0.48, b: 0.28, roughness: 0.42)
    static let silver = MetalStyle(r: 0.82, g: 0.84, b: 0.88, roughness: 0.32)
    static let gold   = MetalStyle(r: 0.85, g: 0.64, b: 0.27, roughness: 0.38)

    func makeMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = CGColor(red: r, green: g, blue: b, alpha: 1)
        m.metalness.contents = metalness
        m.roughness.contents = roughness
        m.isDoubleSided = false
        return m
    }
}

// Colores 2D derivados del mismo metal (para la vista plana de la tienda)
extension MetalStyle {
    var baseColor: Color  { Color(red: r, green: g, blue: b) }
    var shineColor: Color { Color(red: r + (1 - r) * 0.75, green: g + (1 - g) * 0.75, blue: b + (1 - b) * 0.75) }
    var lightColor: Color { Color(red: r + (1 - r) * 0.40, green: g + (1 - g) * 0.40, blue: b + (1 - b) * 0.40) }
    var midDarkColor: Color { Color(red: r * 0.72, green: g * 0.72, blue: b * 0.72) }
    var darkColor: Color  { Color(red: r * 0.40, green: g * 0.40, blue: b * 0.40) }
}

extension ShopCategory {
    var metal: MetalStyle {
        switch self {
        case .bronze: return .bronze
        case .silver: return .silver
        case .gold:   return .gold
        }
    }
}

// MARK: - Origen visual de un item

enum ExtrusionDefaults {
    /// Grosor relativo (el icono mide ~1.9 de ancho). 0.34 ≈ pieza gruesa tipo foto 2.
    static let depth: Double = 0.34
}

enum ProceduralShape: String, Codable, CaseIterable {
    case hexCube
}

/// De dónde sale el 3D de cada item.
/// ⚠️ Reemplaza la definición anterior de `ShopItemVisual` (borrala del proyecto).
enum ShopItemVisual: Codable, Hashable {
    /// SF Symbol → se rasteriza y se extruye (todos distintos sin assets).
    case icon(systemName: String)
    /// PNG/JPG (asset catalog o archivo del bundle) → silueta extruida con el metal de la sección.
    case image(name: String, depth: Double = ExtrusionDefaults.depth)
    /// .usdz / .scn / .dae propio. `recolor: true` le aplica el metal de la sección.
    case model3D(name: String, recolor: Bool = false)
    /// Geometría hecha en código.
    case procedural(ProceduralShape)
}
