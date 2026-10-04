//
//  ImageExtruder.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 18/10/2026.
//


//
//  ImageExtruder.swift
//  PomodoroSense
//
//  PNG/JPG -> contornos vectoriales (marching squares con interpolación lineal).
//  - PNG con transparencia: usa el canal alpha como silueta.
//  - JPG / PNG opaco: detecta el color de fondo desde las esquinas.
//  Los huecos del dibujo salen como lazos con giro opuesto (SCNShape los respeta).
//

import CoreGraphics
import Foundation

enum ImageExtruder {

    struct Options {
        var maxResolution = 256       // resolución de trabajo (px del lado mayor)
        var threshold: Float = 0.5    // nivel de corte de la silueta
        var simplify = 0.6            // tolerancia Douglas-Peucker (px)
        var minLoopArea = 12.0        // descarta ruido (px²)
    }

    /// Lazos cerrados normalizados a [-1, 1] (y hacia arriba).
    static func contours(from image: CGImage, options: Options = Options()) -> [[CGPoint]] {
        guard let field = makeField(from: image, maxResolution: options.maxResolution) else { return [] }
        let w = field.w, h = field.h

        let loops = trace(field.values, w: w, h: h, level: options.threshold)
            .filter { abs(area($0)) >= options.minLoopArea }
            .map { simplify($0, eps: options.simplify) }
            .filter { $0.count >= 3 }

        let s = Double(field.longest) / 2
        let cx = Double(w) / 2, cy = Double(h) / 2
        return loops.map { loop in
            loop.map { CGPoint(x: (Double($0.x) - cx) / s, y: (cy - Double($0.y)) / s) }
        }
    }

    // MARK: - Campo escalar (0...1) a partir de la imagen

    private static func makeField(from image: CGImage, maxResolution: Int)
        -> (values: [Float], w: Int, h: Int, longest: Int)? {

        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let scale = Double(maxResolution) / Double(longest)
        let iw = max(2, Int((Double(image.width) * scale).rounded()))
        let ih = max(2, Int((Double(image.height) * scale).rounded()))
        let pad = 3
        let w = iw + pad * 2, h = ih + pad * 2

        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: pad, y: pad, width: iw, height: ih))
            return true
        }
        guard drawn else { return nil }

        // ¿Tiene transparencia real?
        var transparent = 0
        for y in pad..<(pad + ih) {
            for x in pad..<(pad + iw) where px[(y * w + x) * 4 + 3] < 200 { transparent += 1 }
        }
        let hasAlpha = Double(transparent) > Double(iw * ih) * 0.002

        // Color de fondo = promedio de las 4 esquinas (para imágenes opacas)
        var bg = (0.0, 0.0, 0.0)
        if !hasAlpha {
            let pts = [(pad, pad), (pad + iw - 1, pad), (pad, pad + ih - 1), (pad + iw - 1, pad + ih - 1)]
            for (x, y) in pts {
                let i = (y * w + x) * 4
                bg.0 += Double(px[i]) / 255 / 4
                bg.1 += Double(px[i + 1]) / 255 / 4
                bg.2 += Double(px[i + 2]) / 255 / 4
            }
        }

        var field = [Float](repeating: 0, count: w * h)
        for y in pad..<(pad + ih) {
            for x in pad..<(pad + iw) {
                let i = (y * w + x) * 4
                if hasAlpha {
                    field[y * w + x] = Float(px[i + 3]) / 255
                } else {
                    let dr = Double(px[i]) / 255 - bg.0
                    let dg = Double(px[i + 1]) / 255 - bg.1
                    let db = Double(px[i + 2]) / 255 - bg.2
                    field[y * w + x] = Float(smoothstep(0.10, 0.35, (dr * dr + dg * dg + db * db).squareRoot()))
                }
            }
        }

        // Blur 3x3 para suavizar el contorno
        var out = field
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                var s: Float = 0
                for dy in -1...1 { for dx in -1...1 { s += field[(y + dy) * w + x + dx] } }
                out[y * w + x] = s / 9
            }
        }
        return (out, w, h, max(iw, ih))
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: - Marching squares

    private struct EdgeKey: Hashable { let x: Int; let y: Int; let vertical: Bool }

    private static func trace(_ f: [Float], w: Int, h: Int, level: Float) -> [[CGPoint]] {
        func val(_ x: Int, _ y: Int) -> Float { f[y * w + x] }

        func point(_ e: EdgeKey) -> CGPoint {
            if e.vertical {
                let a = val(e.x, e.y), b = val(e.x, e.y + 1)
                return CGPoint(x: Double(e.x), y: Double(e.y) + Double((level - a) / (b - a)))
            } else {
                let a = val(e.x, e.y), b = val(e.x + 1, e.y)
                return CGPoint(x: Double(e.x) + Double((level - a) / (b - a)), y: Double(e.y))
            }
        }

        // Segmentos dirigidos (interior a la derecha) -> lazos exteriores e interiores quedan con giro opuesto.
        var next: [EdgeKey: EdgeKey] = [:]
        for j in 0..<(h - 1) {
            for i in 0..<(w - 1) {
                var c = 0
                if val(i, j) >= level { c |= 1 }          // tl
                if val(i + 1, j) >= level { c |= 2 }      // tr
                if val(i + 1, j + 1) >= level { c |= 4 }  // br
                if val(i, j + 1) >= level { c |= 8 }      // bl
                if c == 0 || c == 15 { continue }

                let T = EdgeKey(x: i, y: j, vertical: false)
                let B = EdgeKey(x: i, y: j + 1, vertical: false)
                let L = EdgeKey(x: i, y: j, vertical: true)
                let R = EdgeKey(x: i + 1, y: j, vertical: true)

                switch c {
                case 1:  next[T] = L
                case 2:  next[R] = T
                case 3:  next[R] = L
                case 4:  next[B] = R
                case 5:  next[T] = L; next[B] = R
                case 6:  next[B] = T
                case 7:  next[B] = L
                case 8:  next[L] = B
                case 9:  next[T] = B
                case 10: next[R] = T; next[L] = B
                case 11: next[R] = B
                case 12: next[L] = R
                case 13: next[T] = R
                case 14: next[L] = T
                default: break
                }
            }
        }

        var loops: [[CGPoint]] = []
        var visited = Set<EdgeKey>()
        for start in next.keys where !visited.contains(start) {
            var loop: [CGPoint] = []
            var cur = start
            while !visited.contains(cur) {
                visited.insert(cur)
                loop.append(point(cur))
                guard let n = next[cur] else { break }
                cur = n
            }
            loops.append(loop)
        }
        return loops
    }

    // MARK: - Geometría 2D

    private static func area(_ p: [CGPoint]) -> Double {
        var s = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            s += Double(a.x * b.y - b.x * a.y)
        }
        return s / 2
    }

    private static func simplify(_ pts: [CGPoint], eps: Double) -> [CGPoint] {
        guard pts.count > 8 else { return pts }
        var far = 0
        var best = 0.0
        for (i, p) in pts.enumerated() {
            let d = Double(hypot(p.x - pts[0].x, p.y - pts[0].y))
            if d > best { best = d; far = i }
        }
        guard far > 0 else { return pts }
        let a = Array(pts[0...far])
        let b = Array(pts[far...]) + [pts[0]]
        return Array(douglasPeucker(a, eps).dropLast()) + Array(douglasPeucker(b, eps).dropLast())
    }

    private static func douglasPeucker(_ pts: [CGPoint], _ eps: Double) -> [CGPoint] {
        guard pts.count > 2, let a = pts.first, let b = pts.last else { return pts }
        var idx = 0
        var dmax = 0.0
        for i in 1..<(pts.count - 1) {
            let d = distance(pts[i], a, b)
            if d > dmax { dmax = d; idx = i }
        }
        if dmax > eps {
            let l = douglasPeucker(Array(pts[0...idx]), eps)
            let r = douglasPeucker(Array(pts[idx...]), eps)
            return Array(l.dropLast()) + r
        }
        return [a, b]
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return Double(hypot(p.x - a.x, p.y - a.y)) }
        return abs(dy * Double(p.x - a.x) - dx * Double(p.y - a.y)) / len2.squareRoot()
    }
}