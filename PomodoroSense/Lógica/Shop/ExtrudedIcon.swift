//
//  ExtrudedIcon.swift
//  PomodoroSense
//
//  Contornos -> malla extruida (ExtrudedMesh) con material metálico.
//  Incluye: carga de imágenes/modelos del bundle, rasterizado de SF Symbols
//  y el logo hexágono-cubo procedural.
//  (Ya no usa SCNShape ni BezierPath.)
//

import SceneKit
import CoreGraphics
#if os(iOS)
import UIKit
#else
import AppKit
#endif

func vec3(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
    SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z))
}

// MARK: - Extrusión desde imagen

enum ExtrudedIcon {
    static let span: Double = 1.9

    private final class LoopsBox {
        let loops: [[CGPoint]]
        init(_ l: [[CGPoint]]) { loops = l }
    }
    private static let cache = NSCache<NSString, LoopsBox>()

    /// Contornos normalizados [-1, 1] (y hacia arriba), cacheados. Los usan la vista 3D y la 2D.
    static func contours(cacheKey: String, image: () -> CGImage?) -> [[CGPoint]]? {
        if let hit = cache.object(forKey: cacheKey as NSString) { return hit.loops }
        guard let img = image() else { return nil }
        let loops = ImageExtruder.contours(from: img)
        cache.setObject(LoopsBox(loops), forKey: cacheKey as NSString)
        return loops
    }

    /// Solo para visuals basados en imagen o símbolo (los modelos 3D y procedurales no tienen silueta 2D).
    static func contours(for visual: ShopItemVisual) -> [[CGPoint]]? {
        switch visual {
        case .icon(let symbol):
            return contours(cacheKey: "sf:\(symbol)") { SymbolRasterizer.cgImage(systemName: symbol) }
        case .image(let name, _):
            return contours(cacheKey: "img:\(name)") { AssetImageLoader.load(name) }
        default:
            return nil
        }
    }

    /// `cacheKey` identifica la imagen: los contornos (lo caro) se calculan una sola vez.
    static func node(cacheKey: String, metal: MetalStyle, depth: Double,
                     image: () -> CGImage?) -> SCNNode? {
        guard let loops = contours(cacheKey: cacheKey, image: image) else { return nil }
        guard !loops.isEmpty else {
            print("⚠️ '\(cacheKey)': no se detectó ninguna silueta (¿PNG sin transparencia o muy claro?)")
            return nil
        }

        let half = span / 2
        let scaled = loops.map { $0.map { CGPoint(x: Double($0.x) * half, y: Double($0.y) * half) } }
        return ExtrudedMesh.node(
            loops: scaled,
            params: .init(depth: depth, bevel: min(0.03, depth * 0.12)),
            material: metal.makeMaterial()
        )
    }
}

// MARK: - Carga de assets

enum AssetImageLoader {
    /// Acepta: nombre de asset catalog, "archivo", "archivo.png" o "Carpeta/sub/archivo.png".
    /// Busca: asset catalog -> ruta exacta -> raíz del bundle -> búsqueda recursiva (sin distinguir mayúsculas).
    static func load(_ name: String) -> CGImage? {
        let base = ((name as NSString).lastPathComponent as NSString).deletingPathExtension
        for key in [name, base] {
            if let cg = catalogImage(key) { return cg }
        }
        guard let url = BundleLookup.url(name, exts: ["png", "jpg", "jpeg", "webp", "heic"]) else {
            print("⚠️ Imagen '\(name)' NO encontrada en el bundle. ¿Está en el target? ¿ShopItems es carpeta azul?")
            return nil
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            print("⚠️ Imagen '\(url.lastPathComponent)' encontrada pero no se pudo decodificar")
            return nil
        }
        return img
    }

    private static func catalogImage(_ key: String) -> CGImage? {
        #if os(iOS)
        return UIImage(named: key)?.cgImage
        #else
        guard let img = NSImage(named: key) else { return nil }
        var r = CGRect(origin: .zero, size: img.size)
        return img.cgImage(forProposedRect: &r, context: nil, hints: nil)
        #endif
    }
}

enum BundleLookup {
    private static var cache: [String: URL] = [:]
    private static let lock = NSLock()

    static func url(_ name: String, exts: [String]) -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[name] { return hit }

        let ns = name as NSString
        let dir = ns.deletingLastPathComponent
        let file = ns.lastPathComponent as NSString
        let base = file.deletingPathExtension
        let given = file.pathExtension
        let candidates = given.isEmpty ? exts : [given]

        var found: URL?
        // 1) ruta exacta (carpeta azul / folder reference)
        for e in candidates where found == nil {
            found = Bundle.main.url(forResource: base, withExtension: e,
                                    subdirectory: dir.isEmpty ? nil : dir)
        }
        // 2) archivo suelto en la raíz del bundle (carpeta agregada como grupo amarillo)
        for e in candidates where found == nil {
            found = Bundle.main.url(forResource: base, withExtension: e)
        }
        // 3) búsqueda recursiva por nombre, sin distinguir mayúsculas
        if found == nil { found = recursiveFind(base: base, exts: candidates) }

        if let f = found { cache[name] = f }
        return found
    }

    private static func recursiveFind(base: String, exts: [String]) -> URL? {
        guard let root = Bundle.main.resourceURL,
              let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        let wanted = exts.map { $0.lowercased() }
        for case let u as URL in en {
            if u.deletingPathExtension().lastPathComponent.lowercased() == base.lowercased(),
               wanted.contains(u.pathExtension.lowercased()) { return u }
        }
        return nil
    }
}

/// SF Symbol -> CGImage (solo importa el alpha; la extrusión usa la silueta).
enum SymbolRasterizer {
    static func cgImage(systemName: String) -> CGImage? {
        #if os(iOS)
        let cfg = UIImage.SymbolConfiguration(pointSize: 320, weight: .bold)
        guard let sym = UIImage(systemName: systemName, withConfiguration: cfg) else { return nil }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: sym.size, format: fmt).image { _ in
            sym.withTintColor(.white, renderingMode: .alwaysOriginal).draw(at: .zero)
        }
        return img.cgImage
        #else
        guard let base = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else { return nil }
        let cfg = NSImage.SymbolConfiguration(pointSize: 320, weight: .bold)
        let sym = base.withSymbolConfiguration(cfg) ?? base
        var r = CGRect(origin: .zero, size: sym.size)
        return sym.cgImage(forProposedRect: &r, context: nil, hints: nil)
        #endif
    }
}

// MARK: - Logo procedural (hexágono-cubo)

enum ProceduralShapes {
    static func node(_ shape: ProceduralShape, metal: MetalStyle) -> SCNNode {
        switch shape {
        case .hexCube: return hexCube(metal)
        }
    }

    private static func hexCube(_ metal: MetalStyle) -> SCNNode {
        let root = SCNNode()
        let mat = metal.makeMaterial()
        let ringDepth = 0.46
        let barDepth: CGFloat = 0.40
        let innerR = 0.80

        // Anillo: exterior redondeado + hueco hexagonal (malla propia: normales correctas)
        let outer = hexLoop(radius: 1.0, corner: 0.10)
        let inner = hexLoop(radius: innerR, corner: 0.0)
        if let ring = ExtrudedMesh.node(loops: [outer, inner],
                                        params: .init(depth: ringDepth, bevel: 0.03),
                                        material: mat) {
            root.addChildNode(ring)
        }

        // 3 barras que cruzan el centro = 6 radios
        for k in 0..<3 {
            let bar = SCNBox(width: 0.13, height: CGFloat(innerR * 2 + 0.05),
                             length: barDepth, chamferRadius: 0.02)
            bar.materials = [mat]
            let n = SCNNode(geometry: bar)
            n.eulerAngles = vec3(0, 0, Double(k) * .pi / 3)
            root.addChildNode(n)
        }

        // Cubitos sobre los radios
        for deg in [90.0, 210.0, 330.0] {
            let a = deg * .pi / 180
            let cube = SCNBox(width: 0.21, height: 0.21, length: 0.56, chamferRadius: 0.025)
            cube.materials = [mat]
            let n = SCNNode(geometry: cube)
            n.position = vec3(cos(a) * 0.52, sin(a) * 0.52, 0)
            n.eulerAngles = vec3(0, 0, a - .pi / 2)
            root.addChildNode(n)
        }
        return root
    }

    /// Hexágono con vértice arriba. `corner` = fracción del lado que se redondea.
    private static func hexLoop(radius: Double, corner t: Double) -> [CGPoint] {
        let base: [CGPoint] = (0..<6).map { i in
            let a = (90.0 + Double(i) * 60.0) * .pi / 180
            return CGPoint(x: cos(a) * radius, y: sin(a) * radius)
        }
        guard t > 0 else { return base }

        func lerp(_ a: CGPoint, _ b: CGPoint, _ f: Double) -> CGPoint {
            CGPoint(x: Double(a.x) + (Double(b.x) - Double(a.x)) * f,
                    y: Double(a.y) + (Double(b.y) - Double(a.y)) * f)
        }
        var out: [CGPoint] = []
        for i in 0..<6 {
            let prev = base[(i + 5) % 6], cur = base[i], next = base[(i + 1) % 6]
            let a = lerp(cur, prev, t), b = lerp(cur, next, t)
            for s in 0...6 {                              // bézier cúbica a, cur, cur, b
                let u = Double(s) / 6, w = 1 - u
                let x = w*w*w*Double(a.x) + 3*w*w*u*Double(cur.x) + 3*w*u*u*Double(cur.x) + u*u*u*Double(b.x)
                let y = w*w*w*Double(a.y) + 3*w*w*u*Double(cur.y) + 3*w*u*u*Double(cur.y) + u*u*u*Double(b.y)
                out.append(CGPoint(x: x, y: y))
            }
        }
        return out
    }
}
