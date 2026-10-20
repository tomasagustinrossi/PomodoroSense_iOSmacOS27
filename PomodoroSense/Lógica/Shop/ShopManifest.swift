//
//  ShopCatalogLoader.swift
//  PomodoroSense
//
//  El catálogo se arma desde datos, no desde código:
//   1) ShopCatalog.json  (array en la raíz, o { "items": [...] })
//   2) Carpeta "ShopItems/<bronze|silver|gold>/" (Folder Reference azul en Xcode)
//   3) Si no existe nada de lo anterior, usa `builtIn`.
//

import Foundation

struct ShopManifest: Decodable {
    let items: [ShopLossy<ShopManifestEntry>]
}

/// Una entrada inválida se descarta (con aviso en consola) sin romper el resto del catálogo.
struct ShopLossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        do { value = try T(from: decoder) }
        catch { print("⚠️ ShopCatalog.json: entrada inválida descartada → \(error)"); value = nil }
    }
}

struct ShopManifestEntry: Decodable {
    let id: String?
    let category: ShopCategory
    let name: String
    let description: String?
    let cost: Int
    let image: String?
    let model: String?
    let symbol: String?
    let shape: ProceduralShape?
    let depth: Double?
    let recolor: Bool?
    // "type" y cualquier otra clave desconocida se ignoran sin error.
}

enum ShopCatalogLoader {

    private static let imageExts = ["png", "jpg", "jpeg", "webp", "heic"]
    private static let modelExts = ["usdz", "scn", "dae"]
    private static let defaultCost: [ShopCategory: Int] = [.bronze: 10, .silver: 5, .gold: 2]

    static func load() -> [any ShopItem] {
        var items = fromManifest()
        let known = Set(items.map(\.id))
        items += discover().filter { !known.contains($0.id) }
        if items.isEmpty {
            print("⚠️ Catálogo vacío: usando builtIn")
            items = builtIn
        }
        items = deduplicated(items)
        validate(items)
        print("🛍️ Shop: \(items.count) items → \(items.map(\.id).joined(separator: ", "))")
        return items
    }

    // MARK: 1) Manifest JSON

    private static func decodeEntries(_ data: Data) throws -> [ShopManifestEntry] {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true   // tolera comas finales y comentarios

        // 1) JSON válido: array en la raíz o { "items": [...] }
        if let list = try? decoder.decode([ShopLossy<ShopManifestEntry>].self, from: data) {
            return list.compactMap(\.value)
        }
        if let manifest = try? decoder.decode(ShopManifest.self, from: data) {
            return manifest.items.compactMap(\.value)
        }

        // 2) JSON roto (coma que falta, etc.): rescatar objeto por objeto
        print("⚠️ ShopCatalog.json tiene errores de sintaxis; rescatando item por item…")
        let entries = rescueObjects(in: data).compactMap { chunk -> ShopManifestEntry? in
            do { return try decoder.decode(ShopManifestEntry.self, from: chunk) }
            catch {
                let preview = String(data: chunk, encoding: .utf8)?.prefix(80) ?? ""
                print("⚠️ ShopCatalog.json: objeto descartado → \(preview)… \(error)")
                return nil
            }
        }
        if entries.isEmpty { throw CocoaError(.coderReadCorrupt) }
        return entries
    }

    /// Extrae cada `{ ... }` que sea un item, balanceando llaves (ignora las que están dentro de strings).
    private static func rescueObjects(in data: Data) -> [Data] {
        let bytes = [UInt8](data)
        let open = UInt8(ascii: "{"), close = UInt8(ascii: "}")
        let arrOpen = UInt8(ascii: "["), arrClose = UInt8(ascii: "]")
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")

        // Raíz "[" -> los items están a nivel 1. Raíz "{" (con "items") -> nivel 2.
        let root = bytes.first { $0 == open || $0 == arrOpen }
        let entryLevel = (root == arrOpen) ? 1 : 2

        var result: [Data] = []
        var depth = 0, start = 0
        var inString = false, escaped = false

        for (i, b) in bytes.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if b == backslash { escaped = true }
                else if b == quote { inString = false }
                continue
            }
            switch b {
            case quote:
                inString = true
            case open, arrOpen:
                if b == open && depth == entryLevel { start = i }
                depth += 1
            case close, arrClose:
                guard depth > 0 else { continue }
                depth -= 1
                if b == close && depth == entryLevel { result.append(Data(bytes[start...i])) }
            default:
                break
            }
        }
        return result
    }

    private static func fromManifest() -> [ShopItemDefinition] {
        guard let url = Bundle.main.url(forResource: "ShopCatalog", withExtension: "json") else {
            print("⚠️ ShopCatalog.json NO está en el bundle (revisá Target Membership / Copy Bundle Resources)")
            return []
        }
        let entries: [ShopManifestEntry]
        do {
            entries = try decodeEntries(Data(contentsOf: url))
        } catch {
            print("⚠️ ShopCatalog.json no se pudo leer (JSON mal formado: ¿coma de más o de menos?) → \(error)")
            return []
        }
        print("✅ ShopCatalog.json: \(entries.count) item(s) cargados")

        return entries.map { e in
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
                visual: visual
            )
        }
    }

    // MARK: 2) Carpeta de assets

    private static func discover() -> [ShopItemDefinition] {
        guard let root = Bundle.main.url(forResource: "ShopItems", withExtension: nil) else {
            print("⚠️ Carpeta ShopItems NO está en el bundle (tiene que agregarse como Folder Reference azul)")
            return []
        }
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
                    cost: defaultCost[cat] ?? 250,
                    iconName: "cube.fill",
                    visual: visual
                ))
            }
        }
        return result
    }

    // MARK: Utilidades

    private static func slug(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func deduplicated(_ items: [ShopItemDefinition]) -> [ShopItemDefinition] {
        var seen = Set<String>()
        var out: [ShopItemDefinition] = []
        for item in items {
            if seen.insert(item.id).inserted {
                out.append(item)
            } else {
                print("⚠️ Shop: id duplicado '\(item.id)' descartado (usá ids únicos en el JSON)")
            }
        }
        return out
    }

    private static func validate(_ items: [ShopItemDefinition]) {
        for item in items {
            let tier = item.category.tier
            let cost = item.cost[tier] ?? 0
            if cost <= 0 {
                print("⚠️ Shop: '\(item.id)' tiene costo \(cost)")
            } else if cost > tier.softCap {
                print("⚠️ Shop: '\(item.id)' cuesta \(cost) pero el tope de \(tier.displayName) es \(tier.softCap): nunca se podrá comprar")
            }
        }
    }

    // MARK: 3) Fallback (solo si JSON y carpeta fallan): mismos ids que el JSON

    static let builtIn: [ShopItemDefinition] = [
        ShopItemDefinition(id: "bronze.chip_pack", category: .bronze, displayName: "CHIP",
                           description: "Just a chip.",
                           cost: 10, iconName: "cube"),
        ShopItemDefinition(id: "bronze.bolt", category: .bronze, displayName: "MOTIVATION BOOST",
                           description: "Keep the momentum... Just.. DO IT!",
                           cost: 250, iconName: "bolt"),
        ShopItemDefinition(id: "silver.eye", category: .silver, displayName: "VISION",
                           description: "Keep your attention on what matters.",
                           cost: 5, iconName: "eye"),
        ShopItemDefinition(id: "gold.sun", category: .gold, displayName: "GOLDEN SUN",
                           description: "Bring your brightest energy to every session.",
                           cost: 2, iconName: "sun.max")
    ]
}
