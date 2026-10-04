//
//  ShopCatalogLoader.swift
//  PomodoroSense
//
//  El catálogo se arma desde datos, no desde código:
//   1) ShopCatalog.json  (manifest: nombre, costo, descripción, imagen/modelo…)
//   2) Carpeta "ShopItems/<bronze|silver|gold>/" (Folder Reference azul en Xcode):
//      todo .png/.jpg/.usdz/.scn que pongas ahí aparece solo en la tienda y en la colección.
//   3) Si no existe nada de lo anterior, usa `builtIn` (tus items actuales).
//

import Foundation

struct ShopManifest: Decodable {
    let items: [ShopManifestEntry]
}

struct ShopManifestEntry: Decodable {
    let id: String?              // ⚠️ fijalo si ya hay compras guardadas: la propiedad se guarda por id
    let category: ShopCategory   // "bronze" | "silver" | "gold"  -> define el metal
    let name: String
    let description: String?
    let cost: Int
    let image: String?           // PNG/JPG
    let model: String?           // .usdz / .scn
    let symbol: String?          // SF Symbol
    let shape: ProceduralShape?
    let depth: Double?           // grosor de la extrusión (default 0.34)
    let recolor: Bool?           // aplicar metal de la sección a un .usdz
    let grants: Int?             // grantedEarnings
}

enum ShopCatalogLoader {

    private static let imageExts = ["png", "jpg", "jpeg", "webp", "heic"]
    private static let modelExts = ["usdz", "scn", "dae"]
    private static let defaultCost: [ShopCategory: Int] = [.bronze: 100, .silver: 25, .gold: 10]

    static func load() -> [any ShopItem] {
        var items = fromManifest()
        let known = Set(items.map(\.id))
        items += discover().filter { !known.contains($0.id) }
        if items.isEmpty { items = builtIn }
        return items
    }

    // MARK: 1) Manifest JSON

    private static func fromManifest() -> [ShopItemDefinition] {
        guard let url = Bundle.main.url(forResource: "ShopCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(ShopManifest.self, from: data) else { return [] }

        return manifest.items.map { e in
            let visual: ShopItemVisual
            if let image = e.image {
                visual = .image(name: image, depth: e.depth ?? ExtrusionDefaults.depth)
            } else if let model = e.model {
                visual = .model3D(name: model, recolor: e.recolor ?? false)
            } else if let shape = e.shape {
                visual = .procedural(shape)
            } else if let symbol = e.symbol {
                visual = .icon(systemName: symbol)
            } else {
                visual = .procedural(.hexCube)
            }
            return ShopItemDefinition(
                id: e.id ?? "\(e.category.rawValue).\(slug(e.name))",
                category: e.category,
                displayName: e.name.uppercased(),
                description: e.description ?? "",
                cost: e.cost,
                iconName: e.symbol ?? "cube.fill",
                visual: visual,
                grantedEarnings: e.grants
            )
        }
    }

    // MARK: 2) Carpeta de assets

    private static func discover() -> [ShopItemDefinition] {
        guard let root = Bundle.main.url(forResource: "ShopItems", withExtension: nil) else { return [] }
        var result: [ShopItemDefinition] = []

        for cat in ShopCategory.allCases {
            let dir = root.appendingPathComponent(cat.rawValue, isDirectory: true)
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { continue }

            for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let ext = url.pathExtension.lowercased()
                let base = url.deletingPathExtension().lastPathComponent
                let path = "ShopItems/\(cat.rawValue)/\(url.lastPathComponent)"

                let visual: ShopItemVisual
                if imageExts.contains(ext) { visual = .image(name: path) }
                else if modelExts.contains(ext) { visual = .model3D(name: path) }
                else { continue }

                result.append(ShopItemDefinition(
                    id: "\(cat.rawValue).\(slug(base))",
                    category: cat,
                    displayName: base.replacingOccurrences(of: "_", with: " ").uppercased(),
                    description: "",
                    cost: defaultCost[cat] ?? 10,
                    iconName: "cube.fill",
                    visual: visual
                ))
            }
        }
        return result
    }

    private static func slug(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: 3) Fallback: tus items actuales (ahora todos se ven distintos gracias a los SF Symbols)

    static let builtIn: [ShopItemDefinition] = [
        ShopItemDefinition(id: "bronze.chip_pack", category: .bronze, displayName: "CHIP PACK",
                           description: "A small bundle of chips to jumpstart a session.",
                           cost: 100, iconName: "circle.hexagongrid.fill", grantedEarnings: 50),
        ShopItemDefinition(id: "bronze.motivation", category: .bronze, displayName: "MOTIVATION BOOST",
                           description: "Keep the momentum going with a small perk.",
                           cost: 250, iconName: "bolt.fill", grantedEarnings: 120),
        ShopItemDefinition(id: "bronze.coffee", category: .bronze, displayName: "VIRTUAL COFFEE",
                           description: "Brew a virtual cup. Cosmetic only.",
                           cost: 60, iconName: "cup.and.saucer.fill"),
        ShopItemDefinition(id: "silver.streak_shield", category: .silver, displayName: "STREAK SHIELD",
                           description: "Visualize protection for your streak.",
                           cost: 25, iconName: "shield.fill", grantedEarnings: 10),
        ShopItemDefinition(id: "silver.focus_orb", category: .silver, displayName: "FOCUS ORB",
                           description: "A glow for your focus. Premium cosmetic.",
                           cost: 40, iconName: "circle.hexagongrid.circle.fill", grantedEarnings: 15),
        ShopItemDefinition(id: "gold.focus_crown", category: .gold, displayName: "FOCUS CROWN",
                           description: "The legendary mark of master focusers.",
                           cost: 10, iconName: "crown.fill", grantedEarnings: 5)
    ]
}