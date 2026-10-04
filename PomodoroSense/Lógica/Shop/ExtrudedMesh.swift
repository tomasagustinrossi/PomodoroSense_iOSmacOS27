//
//  ExtrudedMesh.swift
//  PomodoroSense
//
//  Extrusión propia (sin SCNShape): tapas trianguladas con huecos, paredes con
//  normales calculadas a mano y bisel redondeado. Garantiza que las paredes de
//  los huecos miren hacia el vacío (nada "se exterioriza"), para cualquier icono.
//

import SceneKit
import CoreGraphics

enum ExtrudedMesh {

    struct Params {
        var depth: Double
        var bevel: Double
        var steps = 3               // segmentos del bisel redondeado
        var smoothAngle = 35.0      // grados: por debajo se suaviza, por encima queda arista
    }

    fileprivate typealias P = SIMD2<Double>

    private struct Loop {
        var pts: [P]
        var isHole: Bool
        var parent: Int?
    }

    private struct Ring {
        let inset: Double   // cuánto entra hacia el interior del sólido
        let z: Double
        let nOut: Double    // componente horizontal de la normal
        let nZ: Double
    }

    // MARK: - API

    static func node(loops raw: [[CGPoint]], params: Params, material: SCNMaterial) -> SCNNode? {
        let loops = classify(raw)
        guard !loops.isEmpty else { return nil }

        let h = params.depth / 2
        let b = max(0, min(params.bevel, h * 0.9))
        let rings = makeRings(h: h, b: b, steps: params.steps)
        let cosSmooth = cos(params.smoothAngle * .pi / 180)

        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var idx: [Int32] = []
        var capPts: [P] = []
        var capRanges: [Range<Int>] = []

        for loop in loops {
            let pts = loop.pts
            let m = pts.count

            // Normal saliente de cada arista: derecha de la dirección de recorrido.
            // (exterior antihorario -> hacia afuera; hueco horario -> hacia el vacío)
            var en: [P] = []
            for i in 0..<m {
                let d = pts[(i + 1) % m] - pts[i]
                en.append(norm2(P(d.y, -d.x)))
            }

            var vn: [P] = [], smooth: [Bool] = [], miter: [P] = []
            for i in 0..<m {
                let a = en[(i + m - 1) % m], c = en[i]
                let d = dot2(a, c)
                smooth.append(d > cosSmooth)
                vn.append(norm2(a + c))
                var mv = d > -0.9 ? (a + c) / (1 + d) : c
                let l = (mv.x * mv.x + mv.y * mv.y).squareRoot()
                if l > 3 { mv = mv * (3 / l) }
                miter.append(mv)
            }

            // Paredes: cada arista es una tira de bandas (bisel trasero, pared, bisel delantero)
            for i in 0..<m {
                let j = (i + 1) % m
                let nStart = smooth[i] ? vn[i] : en[i]
                let nEnd = smooth[j] ? vn[j] : en[i]

                func add(_ vi: Int, _ r: Ring, _ n: P) {
                    let p = pts[vi] - miter[vi] * r.inset
                    verts.append(vec3(p.x, p.y, r.z))
                    norms.append(vec3(n.x * r.nOut, n.y * r.nOut, r.nZ))
                }

                for r in 0..<(rings.count - 1) {
                    let lo = rings[r], hi = rings[r + 1]
                    let base = Int32(verts.count)
                    add(i, hi, nStart)   // A
                    add(j, hi, nEnd)     // B
                    add(j, lo, nEnd)     // C
                    add(i, lo, nStart)   // D
                    idx += [base, base + 3, base + 2, base, base + 2, base + 1]
                }
            }

            let start = capPts.count
            for i in 0..<m { capPts.append(pts[i] - miter[i] * rings[0].inset) }
            capRanges.append(start..<capPts.count)
        }

        // Tapas (delantera +z, trasera -z)
        let topBase = verts.count
        for p in capPts { verts.append(vec3(p.x, p.y, h)); norms.append(vec3(0, 0, 1)) }
        let botBase = verts.count
        for p in capPts { verts.append(vec3(p.x, p.y, -h)); norms.append(vec3(0, 0, -1)) }

        for (li, loop) in loops.enumerated() where !loop.isHole {
            let outer = Array(capRanges[li])
            let holes = loops.indices
                .filter { loops[$0].isHole && loops[$0].parent == li }
                .map { Array(capRanges[$0]) }
            let tris = Triangulator.triangulate(outer: outer, holes: holes, pts: capPts)
            var t = 0
            while t + 2 < tris.count {
                let a = tris[t], b2 = tris[t + 1], c = tris[t + 2]
                idx += [Int32(topBase + a), Int32(topBase + b2), Int32(topBase + c)]
                idx += [Int32(botBase + a), Int32(botBase + c), Int32(botBase + b2)]
                t += 3
            }
        }

        let geo = SCNGeometry(
            sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)]
        )
        geo.materials = [material]
        return SCNNode(geometry: geo)
    }

    // MARK: - Perfil (bisel redondeado de cuarto de círculo)

    private static func makeRings(h: Double, b: Double, steps: Int) -> [Ring] {
        guard b > 1e-6, steps > 0 else {
            return [Ring(inset: 0, z: -h, nOut: 1, nZ: 0), Ring(inset: 0, z: h, nOut: 1, nZ: 0)]
        }
        var r: [Ring] = []
        for k in stride(from: steps, through: 0, by: -1) {
            let t = Double(k) / Double(steps) * .pi / 2
            r.append(Ring(inset: b * (1 - cos(t)), z: -(h - b + b * sin(t)), nOut: cos(t), nZ: -sin(t)))
        }
        for k in 0...steps {
            let t = Double(k) / Double(steps) * .pi / 2
            r.append(Ring(inset: b * (1 - cos(t)), z: h - b + b * sin(t), nOut: cos(t), nZ: sin(t)))
        }
        return r
    }

    // MARK: - Clasificación exterior / hueco (por anidamiento, sin depender del sentido de giro)

    private static func classify(_ raw: [[CGPoint]]) -> [Loop] {
        var polys: [[P]] = raw.map { loop in
            var out: [P] = []
            for p in loop {
                let q = P(Double(p.x), Double(p.y))
                if let last = out.last, abs(last.x - q.x) + abs(last.y - q.y) < 1e-6 { continue }
                out.append(q)
            }
            return out
        }.filter { $0.count >= 3 }

        let n = polys.count
        let areas = polys.map { signedArea($0) }
        var depth = [Int](repeating: 0, count: n)
        var containers = [[Int]](repeating: [], count: n)
        for a in 0..<n {
            for c in 0..<n where a != c && contains(polys[c], polys[a][0]) {
                depth[a] += 1
                containers[a].append(c)
            }
        }

        var loops: [Loop] = []
        for i in 0..<n {
            let hole = depth[i] % 2 == 1
            if (areas[i] > 0) == hole { polys[i].reverse() }   // exterior CCW, hueco CW
            var parent: Int?
            if hole {
                parent = containers[i]
                    .filter { depth[$0] == depth[i] - 1 }
                    .min(by: { abs(areas[$0]) < abs(areas[$1]) })
            }
            loops.append(Loop(pts: polys[i], isHole: hole, parent: parent))
        }
        return loops
    }

    private static func signedArea(_ p: [P]) -> Double {
        var s = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    private static func contains(_ poly: [P], _ p: P) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

fileprivate func dot2(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.x + a.y * b.y }
fileprivate func norm2(_ a: SIMD2<Double>) -> SIMD2<Double> {
    let l = (a.x * a.x + a.y * a.y).squareRoot()
    return l > 1e-12 ? a / l : SIMD2<Double>(0, 0)
}

// MARK: - Triangulación (huecos por puentes + ear clipping)

private enum Triangulator {
    typealias P = SIMD2<Double>

    static func triangulate(outer: [Int], holes: [[Int]], pts: [P]) -> [Int] {
        var ring = outer
        let sorted = holes.sorted { maxX($0, pts) > maxX($1, pts) }

        for (hn, hole) in sorted.enumerated() {
            guard let hi = hole.indices.max(by: { pts[hole[$0]].x < pts[hole[$1]].x }) else { continue }
            let m = pts[hole[hi]]
            let others = Array(sorted[(hn + 1)...])

            let candidates = ring.indices.sorted {
                dist2(pts[ring[$0]], m) < dist2(pts[ring[$1]], m)
            }
            var chosen: Int?
            for c in candidates where visible(m, pts[ring[c]], ring, hole, others, pts) {
                chosen = c
                break
            }
            let j = chosen ?? candidates.first ?? 0

            var merged = Array(ring[0...j])
            for k in 0...hole.count { merged.append(hole[(hi + k) % hole.count]) }
            merged.append(ring[j])
            merged.append(contentsOf: ring[(j + 1)...])
            ring = merged
        }
        return earClip(ring, pts)
    }

    private static func earClip(_ poly: [Int], _ pts: [P]) -> [Int] {
        var idx = poly
        var tris: [Int] = []
        tris.reserveCapacity(poly.count * 3)
        var i = 0
        var stall = 0

        while idx.count > 3 {
            let n = idx.count
            i %= n
            let ia = idx[(i + n - 1) % n], ib = idx[i], ic = idx[(i + 1) % n]
            let a = pts[ia], b = pts[ib], c = pts[ic]
            let cr = cross(a, b, c)
            var removed = false

            if abs(cr) < 1e-14 {
                idx.remove(at: i); removed = true                // espiga / colineal
            } else if cr > 0 && !anyInside(a, b, c, idx, pts) {
                tris += [ia, ib, ic]
                idx.remove(at: i); removed = true
            }

            if removed { stall = 0 } else { i += 1; stall += 1 }

            if stall > idx.count && idx.count > 3 {              // sin orejas válidas: salir del bucle
                let n2 = idx.count
                i %= n2
                let fa = idx[(i + n2 - 1) % n2], fb = idx[i], fc = idx[(i + 1) % n2]
                if cross(pts[fa], pts[fb], pts[fc]) > 0 { tris += [fa, fb, fc] }
                idx.remove(at: i)
                stall = 0
            }
        }
        if idx.count == 3, cross(pts[idx[0]], pts[idx[1]], pts[idx[2]]) > 0 { tris += idx }
        return tris
    }

    private static func anyInside(_ a: P, _ b: P, _ c: P, _ idx: [Int], _ pts: [P]) -> Bool {
        for k in idx {
            let p = pts[k]
            if cross(a, b, p) > 1e-12 && cross(b, c, p) > 1e-12 && cross(c, a, p) > 1e-12 { return true }
        }
        return false
    }

    private static func visible(_ m: P, _ p: P, _ ring: [Int], _ hole: [Int],
                                _ others: [[Int]], _ pts: [P]) -> Bool {
        for loop in [ring, hole] + others {
            let n = loop.count
            for k in 0..<n {
                let a = pts[loop[k]], b = pts[loop[(k + 1) % n]]
                if same(a, m) || same(b, m) || same(a, p) || same(b, p) { continue }
                if segmentsCross(m, p, a, b) { return false }
            }
        }
        return true
    }

    private static func same(_ a: P, _ b: P) -> Bool { abs(a.x - b.x) + abs(a.y - b.y) < 1e-9 }
    private static func dist2(_ a: P, _ b: P) -> Double { (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) }
    private static func maxX(_ loop: [Int], _ pts: [P]) -> Double { loop.map { pts[$0].x }.max() ?? 0 }
    private static func cross(_ a: P, _ b: P, _ c: P) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    private static func segmentsCross(_ p1: P, _ p2: P, _ p3: P, _ p4: P) -> Bool {
        let d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2)
        let d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }
}