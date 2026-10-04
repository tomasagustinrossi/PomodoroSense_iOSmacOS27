import Foundation

/// Todos los sonidos de ambiente de la app.
/// IDs 1–4: ruidos procedurales (color).
/// IDs 5+: archivos de audio del bundle (nature, rain, ocean, etc.).
enum AmbientSound: Int, CaseIterable, Identifiable, Hashable {
    case none = 0
    case brown = 1
    case pink = 2
    case white = 3
    case violet = 4
    // A partir de acá, todos son archivos del bundle:
    case nature = 5
    case rain = 6
    case ocean = 7
    case classicalMusic = 8
    case fireplace = 9

    var id: Int { rawValue }

    /// Nombre largo para listas, presets, header.
    var displayName: String {
        switch self {
        case .none:            return "NONE"
        case .brown:           return "BROWN NOISE"
        case .pink:            return "PINK NOISE"
        case .white:           return "WHITE NOISE"
        case .violet:          return "VIOLET NOISE"
        case .nature:          return "NATURE"
        case .rain:            return "RAIN"
        case .ocean:           return "OCEAN"
        case .classicalMusic:  return "CLASSICAL"
        case .fireplace:       return "FIREPLACE"
        }
    }

    /// Nombre corto para botones compactos.
    var shortName: String {
        switch self {
        case .none:            return "OFF"
        case .brown:           return "BROWN"
        case .pink:            return "PINK"
        case .white:           return "WHITE"
        case .violet:          return "VIOLET"
        case .nature:          return "NATURE"
        case .rain:            return "RAIN"
        case .ocean:           return "OCEAN"
        case .classicalMusic:  return "CLASSIC"
        case .fireplace:       return "FIRE"
        }
    }

    /// Nombre base del archivo en el bundle (sin extensión).
    /// `nil` para ruidos procedurales.
    var fileName: String? {
        switch self {
        case .nature:         return "nature_ambience"
        case .rain:           return "nature_rain"
        case .ocean:          return "ocean_waves"
        case .classicalMusic: return "classic_music"
        case .fireplace:      return "fireplace"
        default:              return nil
        }
    }

    /// `true` si este sonido se reproduce como archivo (streaming + loop).
    var isFileBased: Bool { fileName != nil }

    /// Todos menos `.none` — útil para iterar en la UI.
    static var selectable: [AmbientSound] { allCases.filter { $0 != .none } }

    /// Helper inverso seguro.
    static func from(id: Int) -> AmbientSound { AmbientSound(rawValue: id) ?? .none }
}