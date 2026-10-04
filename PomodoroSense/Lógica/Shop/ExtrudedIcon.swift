//
//  ExtrudedIcon.swift
//  PomodoroSense
//
//  Contornos -> SCNShape extruido con bisel y material metálico.
//  Incluye: carga de imágenes/modelos del bundle, rasterizado de SF Symbols
//  y el logo hexágono-cubo procedural.
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

// MARK: - BezierPath multiplataforma

#if os(iOS)
typealias BezierPath = UIBezierPath
extension UIBezierPath {
    func mv(_ p: CGPoint) { move(to: p) }
    func ln(_ p: CGPoint) { addLine(to: p) }
    func cubic(to p: CGPoint, c1: CGPoint, c2: CGPoint) {
        addCurve(to: p, controlPoint1: c1, controlPoint2: c2)
    }
}
#else
typealias BezierPath = NSBezierPath
extension NSBezierPath {
    func mv(_ p: CGPoint) { move(to: p) }
    func ln(_ p: CGPoint) { line(to: p) }
    func cubic(to p: CGPoint, c1: CGPoint, c2: CGPoint) {
        curve(to: p, controlPoint1: c1, controlPoint2: c2)
    }
}
#endif

// MARK: - Extrusión

enum ExtrudedIcon {
    static let span: CGFloat = 1.9

    private final class LoopsBox {
        let loops: [[CGPoint]]
        init(_ l: [[CGPoint]]) { loops = l }
    }
    private static let cache = NSCache<NSString, LoopsBox>()

    /// `cacheKey` identifica la imagen: los contornos (lo caro) se calculan una sola vez.
    static func node(cacheKey: String, metal: MetalStyle, depth: Double,
                     image: () -> CGImage?) -> SCNNode? {
        let loops: [[CGPoint]]
        if let hit = cache.object(forKey: cacheKey as NSString) {
            loops = hit.loops
        } else {
            guard let img = image() else { return nil }
            loops = ImageExtruder.contours(from: img)
            cache.setObject(LoopsBox(loops), forKey: cacheKey as NSString)
        }
        guard !loops.isEmpty else { return nil }

        let half = span / 2
        let path = BezierPath()
        for loop in loops {
            // reversed(): exterior en sentido antihorario, huecos en horario.
            let pts = loop.reversed().map { CGPoint(x: $0.x * half, y: $0.y * half) }
            guard let first = pts.first else { continue }
            path.mv(first)
            for p in pts.dropFirst() { path.ln(p) }
            path.close()
        }
        path.flatness = 0.005

        let shape = SCNShape(path: path, extrusionDepth: CGFloat(depth))
        shape.chamferRadius = CGFloat(min(0.03, depth * 0.12))
        shape.chamferMode = .both
        shape.materials = [metal.makeMaterial()]

        let n = SCNNode(geometry: shape)
        n.position = vec3(0, 0, -depth / 2)     // SCNShape extruye de z=0 a z=depth
        let wrapper = SCNNode()
        wrapper.addChildNode(n)
        return wrapper
    }
}

// MARK: - Carga de assets

enum AssetImageLoader {
    /// Acepta: nombre de asset catalog, "archivo", "archivo.png" o "Carpeta/sub/archivo.png".
    static func load(_ name: String) -> CGImage? {
        #if os(iOS)
        if let cg = UIImage(named: name)?.cgImage { return cg }
        #else
        if let img = NSImage(named: name) {
            var r = CGRect(origin: .zero, size: img.size)
            if let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil) { return cg }
        }
        #endif
        guard let url = BundleLookup.url(name, exts: ["png", "jpg", "jpeg", "webp", "heic"]),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

enum BundleLookup {
    static func url(_ name: String, exts: [String]) -> URL? {
        let ns = name as NSString
        let dir = ns.deletingLastPathComponent
        let file = ns.lastPathComponent as NSString
        let base = file.deletingPathExtension
        let given = file.pathExtension
        for e in (given.isEmpty ? exts : [given]) {
            if let u = Bundle.main.url(forResource: base, withExtension: e,
                                       subdirectory: dir.isEmpty ? nil : dir) { return u }
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

// MARK: - Logo procedural (hexágono-cubo), ahora más grueso y con el metal de la sección

enum ProceduralShapes {
    static func node(_ shape: ProceduralShape, metal: MetalStyle) -> SCNNode {
        switch shape {
        case .hexCube: return hexCube(metal)
        }
    }

    private static func hexCube(_ metal: MetalStyle) -> SCNNode {
        let root = SCNNode()
        let mat = metal.makeMaterial()
        let ringDepth: CGFloat = 0.46
        let barDepth: CGFloat = 0.34
        let outerR = 1.0, innerR = 0.80

        let path = BezierPath()
        appendHexagon(to: path, radius: outerR, corner: 0.10, reversed: false)
        appendHexagon(to: path, radius: innerR, corner: 0.0, reversed: true)
        path.flatness = 0.004

        let ring = SCNShape(path: path, extrusionDepth: ringDepth)
        ring.chamferRadius = 0.03
        ring.chamferMode = .both
        ring.materials = [mat]
        let ringNode = SCNNode(geometry: ring)
        ringNode.position = vec3(0, 0, -Double(ringDepth) / 2)
        root.addChildNode(ringNode)

        for k in 0..<3 {
            let bar = SCNBox(width: 0.13, height: CGFloat(innerR * 2 + 0.05),
                             length: barDepth, chamferRadius: 0.02)
            bar.materials = [mat]
            let n = SCNNode(geometry: bar)
            n.eulerAngles = vec3(0, 0, Double(k) * .pi / 3)
            root.addChildNode(n)
        }

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

    private static func appendHexagon(to path: BezierPath, radius: Double,
                                      corner t: Double, reversed: Bool) {
        var pts: [CGPoint] = (0..<6).map { i in
            let a = (90.0 + Double(i) * 60.0) * .pi / 180
            return CGPoint(x: cos(a) * radius, y: sin(a) * radius)
        }
        if reversed { pts.reverse() }

        func lerp(_ a: CGPoint, _ b: CGPoint, _ f: Double) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
        }
        let n = pts.count
        for i in 0..<n {
            let prev = pts[(i + n - 1) % n], cur = pts[i], next = pts[(i + 1) % n]
            if t > 0 {
                let a = lerp(cur, prev, t), b = lerp(cur, next, t)
                if i == 0 { path.mv(a) } else { path.ln(a) }
                path.cubic(to: b, c1: cur, c2: cur)
            } else {
                if i == 0 { path.mv(cur) } else { path.ln(cur) }
            }
        }
        path.close()
    }
}