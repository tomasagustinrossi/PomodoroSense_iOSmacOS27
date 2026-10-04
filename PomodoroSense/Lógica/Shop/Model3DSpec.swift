//
//  Model3DSpec.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 18/10/2026.
//


//
//  Model3DView.swift
//  PomodoroSense
//
//  Vista 3D única (reemplaza GoldLogo3DView y Rotatable3DView).
//  Recibe un ShopItemVisual + la sección (para el metal) y se encarga de todo:
//  escena, luces, entorno, normalización de tamaño, giro automático y arrastre.
//

import SwiftUI
import SceneKit
import CoreGraphics

// MARK: - Spec

struct Model3DSpec: Hashable {
    let visual: ShopItemVisual
    let category: ShopCategory
}

// MARK: - Fábrica de escena

enum Model3DFactory {

    final class Rig {
        let outer = SCNNode()   // yaw/pitch del usuario
        let spin = SCNNode()    // giro automático
        func setContent(_ node: SCNNode) {
            spin.childNodes.forEach { $0.removeFromParentNode() }
            spin.addChildNode(node)
        }
    }

    static func makeRig() -> (SCNScene, Rig) {
        let scene = SCNScene()
        let rig = Rig()

        scene.lightingEnvironment.contents = environment
        scene.lightingEnvironment.intensity = 1.5

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 38
        cam.position = vec3(0, 0, 4.0)
        scene.rootNode.addChildNode(cam)

        func addLight(_ color: CGColor, _ intensity: CGFloat, _ x: Double, _ y: Double) {
            let l = SCNLight()
            l.type = .directional
            l.color = color
            l.intensity = intensity
            let n = SCNNode()
            n.light = l
            n.eulerAngles = vec3(x, y, 0)
            scene.rootNode.addChildNode(n)
        }
        addLight(CGColor(red: 1, green: 0.96, blue: 0.9, alpha: 1), 900, -.pi / 4, -.pi / 5)  // key
        addLight(CGColor(red: 0.85, green: 0.92, blue: 1, alpha: 1), 300, .pi / 5, .pi / 3)   // fill
        addLight(CGColor(gray: 1, alpha: 1), 500, .pi / 6, .pi * 0.8)                         // rim

        rig.outer.addChildNode(rig.spin)
        scene.rootNode.addChildNode(rig.outer)
        return (scene, rig)
    }

    static func makeContent(_ spec: Model3DSpec) -> SCNNode {
        let metal = spec.category.metal
        var node: SCNNode?

        switch spec.visual {
        case .icon(let symbol):
            node = ExtrudedIcon.node(cacheKey: "sf:\(symbol)", metal: metal,
                                     depth: ExtrusionDefaults.depth) {
                SymbolRasterizer.cgImage(systemName: symbol)
            }
        case .image(let name, let depth):
            node = ExtrudedIcon.node(cacheKey: "img:\(name)", metal: metal, depth: depth) {
                AssetImageLoader.load(name)
            }
        case .model3D(let name, let recolor):
            node = loadModel(name, recolor: recolor ? metal : nil)
        case .procedural(let shape):
            node = ProceduralShapes.node(shape, metal: metal)
        }

        return normalize(node ?? ProceduralShapes.node(.hexCube, metal: metal))
    }

    // Centra y escala cualquier contenido a una esfera de radio 1.
    private static func normalize(_ node: SCNNode) -> SCNNode {
        let (center, radius) = node.boundingSphere
        let wrapper = SCNNode()
        node.position = vec3(-Double(center.x), -Double(center.y), -Double(center.z))
        let s = Double(radius) > 0 ? 1.0 / Double(radius) : 1.0
        wrapper.scale = vec3(s, s, s)
        wrapper.addChildNode(node)
        return wrapper
    }

    private static func loadModel(_ name: String, recolor: MetalStyle?) -> SCNNode? {
        guard let url = BundleLookup.url(name, exts: ["usdz", "scn", "dae"]),
              let scene = try? SCNScene(url: url, options: nil) else { return nil }
        let container = SCNNode()
        for child in scene.rootNode.childNodes { container.addChildNode(child) }
        if let metal = recolor {
            let mat = metal.makeMaterial()
            container.enumerateHierarchy { n, _ in n.geometry?.materials = [mat] }
        }
        return container
    }

    // Mapa de entorno neutro: el color del metal lo da el material, no el entorno.
    static let environment: CGImage? = {
        let w = 1024, h = 512
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [
            CGColor(gray: 0.03, alpha: 1),
            CGColor(gray: 0.15, alpha: 1),
            CGColor(gray: 0.55, alpha: 1)
        ] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        }
        let boxes: [(CGRect, CGFloat)] = [
            (CGRect(x: 120, y: 300, width: 260, height: 130), 1.0),
            (CGRect(x: 600, y: 330, width: 300, height: 110), 0.9),
            (CGRect(x: 380, y: 120, width: 220, height: 40), 0.7),
            (CGRect(x: 850, y: 180, width: 60, height: 200), 0.8),
            (CGRect(x: 20, y: 160, width: 60, height: 180), 0.6)
        ]
        for (r, a) in boxes {
            ctx.setFillColor(CGColor(gray: 1, alpha: a))
            ctx.fill(r)
        }
        return ctx.makeImage()
    }()
}

// MARK: - Vista SwiftUI pública

struct Model3DView: View {
    let visual: ShopItemVisual
    let category: ShopCategory
    var size: CGFloat = 220
    var autoRotate: Bool = true
    var interactive: Bool = true

    @State private var yaw: Double = -0.55
    @State private var pitch: Double = 0.18
    @State private var startYaw: Double?
    @State private var startPitch: Double?
    @State private var hasInteracted = false

    private let maxPitch: Double = 0.6
    private var spec: Model3DSpec { Model3DSpec(visual: visual, category: category) }

    var body: some View {
        Model3DSceneView(spec: spec, yaw: yaw, pitch: pitch,
                         autoRotate: autoRotate && !hasInteracted)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .allowsHitTesting(interactive)      // si no es interactivo, el tap llega al Button padre
            .gesture(interactive ? dragGesture : nil)
            .onChange(of: spec) { _, _ in
                yaw = -0.55; pitch = 0.18; hasInteracted = false
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                hasInteracted = true
                if startYaw == nil { startYaw = yaw; startPitch = pitch }
                yaw = (startYaw ?? 0) + Double(value.translation.width) * 0.012
                let p = (startPitch ?? 0) + Double(value.translation.height) * 0.008
                pitch = min(max(p, -maxPitch), maxPitch)
            }
            .onEnded { _ in startYaw = nil; startPitch = nil }
    }
}

// MARK: - Representable (iOS + macOS compartido)

#if os(iOS)
typealias PlatformViewRepresentable = UIViewRepresentable
#else
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

private struct Model3DSceneView: PlatformViewRepresentable {
    let spec: Model3DSpec
    let yaw: Double
    let pitch: Double
    let autoRotate: Bool

    final class Coordinator {
        var rig: Model3DFactory.Rig?
        var spec: Model3DSpec?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    private func make(_ ctx: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        let (scene, rig) = Model3DFactory.makeRig()
        view.scene = scene
        ctx.coordinator.rig = rig
        return view
    }

    private func update(_ view: SCNView, _ ctx: Context) {
        let c = ctx.coordinator
        guard let rig = c.rig else { return }

        // Si cambia el item (p. ej. al navegar la colección) se reconstruye el contenido.
        if c.spec != spec {
            c.spec = spec
            rig.setContent(Model3DFactory.makeContent(spec))
        }
        rig.outer.eulerAngles = vec3(pitch, yaw, 0)

        if autoRotate {
            if rig.spin.action(forKey: "spin") == nil {
                rig.spin.runAction(.repeatForever(
                    .rotateBy(x: 0, y: .pi * 2, z: 0, duration: 14)), forKey: "spin")
            }
        } else {
            rig.spin.removeAction(forKey: "spin")
        }
        // Las vistas estáticas (grids) no gastan GPU: solo se redibujan al cambiar.
        view.rendersContinuously = autoRotate
    }

    #if os(iOS)
    func makeUIView(context: Context) -> SCNView { make(context) }
    func updateUIView(_ view: SCNView, context: Context) { update(view, context) }
    #else
    func makeNSView(context: Context) -> SCNView { make(context) }
    func updateNSView(_ view: SCNView, context: Context) { update(view, context) }
    #endif
}