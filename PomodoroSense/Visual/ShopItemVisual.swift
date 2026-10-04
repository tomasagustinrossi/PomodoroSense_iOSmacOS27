import Foundation

/// Describe cómo se renderiza visualmente un item de la tienda.
/// Hoy solo hay `.icon` (SF Symbols), pero está preparado para `.model3D`
/// (archivos `.usdz` / `.scn` en el bundle, rotables por drag).
enum ShopItemVisual: Codable, Hashable {
    case icon(systemName: String)
    case model3D(name: String)

    private enum CodingKeys: String, CodingKey {
        case type, value
    }
    private enum Kind: String, Codable {
        case icon, model3D
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        let value = try c.decode(String.self, forKey: .value)
        switch kind {
        case .icon:    self = .icon(systemName: value)
        case .model3D: self = .model3D(name: value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .icon(let name):
            try c.encode(Kind.icon, forKey: .type)
            try c.encode(name, forKey: .value)
        case .model3D(let name):
            try c.encode(Kind.model3D, forKey: .type)
            try c.encode(name, forKey: .value)
        }
    }
}