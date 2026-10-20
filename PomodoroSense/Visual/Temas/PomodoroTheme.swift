import SwiftUI

// El contrato estricto
protocol PomodoroTheme {
    var noiseName: String { get }
    var workBackground: Color { get }
    var workAccent: Color { get }
    var breakBackground: Color { get }
    var breakAccent: Color { get }
    var textDimmedWork: Color { get }
    var textDimmedBreak: Color { get }
    var ringBaseColor: Color { get }
}

// MARK: - Ruidos procedurales (existentes)

struct BrownNoiseTheme: PomodoroTheme {
    let noiseName = "BROWN NOISE"
    let workBackground = Color(red: 0.11, green: 0.12, blue: 0.13)
    let workAccent = Color(red: 0.95, green: 0.77, blue: 0.62)
    let breakBackground = Color(red: 0.13, green: 0.15, blue: 0.10)
    let breakAccent = Color(red: 0.85, green: 0.90, blue: 0.60)
    let textDimmedWork = Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.4)
    let textDimmedBreak = Color(red: 0.85, green: 0.90, blue: 0.60).opacity(0.4)
    let ringBaseColor = Color.white.opacity(0.06)
}

struct PinkNoiseTheme: PomodoroTheme {
    let noiseName = "PINK NOISE"
    let workBackground = Color(red: 0.13, green: 0.11, blue: 0.12)
    let workAccent = Color(red: 0.95, green: 0.65, blue: 0.75)
    let breakBackground = Color(red: 0.15, green: 0.12, blue: 0.14)
    let breakAccent = Color(red: 0.90, green: 0.70, blue: 0.80)
    let textDimmedWork = Color(red: 0.95, green: 0.65, blue: 0.75).opacity(0.4)
    let textDimmedBreak = Color(red: 0.90, green: 0.70, blue: 0.80).opacity(0.4)
    let ringBaseColor = Color.white.opacity(0.06)
}

struct WhiteNoiseTheme: PomodoroTheme {
    let noiseName = "WHITE NOISE"
    let workBackground = Color(red: 0.12, green: 0.12, blue: 0.12)
    let workAccent = Color(red: 0.90, green: 0.90, blue: 0.90)
    let breakBackground = Color(red: 0.10, green: 0.11, blue: 0.12)
    let breakAccent = Color(red: 0.75, green: 0.80, blue: 0.85)
    let textDimmedWork = Color(red: 0.90, green: 0.90, blue: 0.90).opacity(0.4)
    let textDimmedBreak = Color(red: 0.75, green: 0.80, blue: 0.85).opacity(0.4)
    let ringBaseColor = Color.white.opacity(0.06)
}

struct VioletNoiseTheme: PomodoroTheme {
    let noiseName = "VIOLET NOISE"
    let workBackground = Color(red: 0.11, green: 0.10, blue: 0.13)
    let workAccent = Color(red: 0.75, green: 0.65, blue: 0.95)
    let breakBackground = Color(red: 0.13, green: 0.12, blue: 0.15)
    let breakAccent = Color(red: 0.80, green: 0.75, blue: 0.90)
    let textDimmedWork = Color(red: 0.75, green: 0.65, blue: 0.95).opacity(0.4)
    let textDimmedBreak = Color(red: 0.80, green: 0.75, blue: 0.90).opacity(0.4)
    let ringBaseColor = Color.white.opacity(0.06)
}

// MARK: - Sonidos de archivo (nuevos)

/// NATURE — Bosque profundo.
/// Verdes musgo y hojas oscuras. Ya existía.
struct NatureTheme: PomodoroTheme {
    let noiseName = "NATURE"

    let workBackground = Color(red: 0.08, green: 0.15, blue: 0.10)
    let workAccent = Color(red: 0.40, green: 0.75, blue: 0.45)

    let breakBackground = Color(red: 0.12, green: 0.16, blue: 0.13)
    let breakAccent = Color(red: 0.60, green: 0.85, blue: 0.60)

    let textDimmedWork = Color(red: 0.40, green: 0.75, blue: 0.45).opacity(0.4)
    let textDimmedBreak = Color(red: 0.60, green: 0.85, blue: 0.60).opacity(0.4)

    let ringBaseColor = Color.white.opacity(0.06)
}

/// RAIN — Lluvia sobre ventana.
/// Grises azulados, frescos y calmos. Baja saturación, sensación de
/// día nublado. Work = lluvia intensa, Break = después de la lluvia.
struct RainTheme: PomodoroTheme {
    let noiseName = "RAIN"

    // Work: gris azulado muy oscuro (tormenta).
    let workBackground = Color(red: 0.09, green: 0.12, blue: 0.15)
    let workAccent = Color(red: 0.60, green: 0.72, blue: 0.82)

    // Break: azul grisáceo ligeramente más claro (post-lluvia).
    let breakBackground = Color(red: 0.11, green: 0.14, blue: 0.17)
    let breakAccent = Color(red: 0.72, green: 0.82, blue: 0.88)

    let textDimmedWork = Color(red: 0.60, green: 0.72, blue: 0.82).opacity(0.4)
    let textDimmedBreak = Color(red: 0.72, green: 0.82, blue: 0.88).opacity(0.4)

    let ringBaseColor = Color.white.opacity(0.06)
}

/// OCEAN — Olas del océano.
/// Azul marino profundo con acentos turquesa. Work = profundidad,
/// Break = superficie iluminada. Sensación de calma inmensa.
struct OceanTheme: PomodoroTheme {
    let noiseName = "OCEAN"

    // Work: azul marino muy profundo.
    let workBackground = Color(red: 0.06, green: 0.12, blue: 0.16)
    let workAccent = Color(red: 0.42, green: 0.72, blue: 0.78)

    // Break: azul ligeramente más cálido y claro (aguas superficiales).
    let breakBackground = Color(red: 0.08, green: 0.15, blue: 0.18)
    let breakAccent = Color(red: 0.55, green: 0.85, blue: 0.85)

    let textDimmedWork = Color(red: 0.42, green: 0.72, blue: 0.78).opacity(0.4)
    let textDimmedBreak = Color(red: 0.55, green: 0.85, blue: 0.85).opacity(0.4)

    let ringBaseColor = Color.white.opacity(0.06)
}

/// CLASSICAL — Música clásica.
/// Evoca madera de piano, marfil y oro envejecido. Work = estudio
/// nocturno, Break = salón iluminado. Cálido, elegante, sobrio.
struct ClassicalTheme: PomodoroTheme {
    let noiseName = "CLASSICAL"

    // Work: marrón muy oscuro (madera de piano).
    let workBackground = Color(red: 0.13, green: 0.11, blue: 0.09)
    let workAccent = Color(red: 0.85, green: 0.78, blue: 0.62)

    // Break: marrón más cálido, dorado suave.
    let breakBackground = Color(red: 0.15, green: 0.13, blue: 0.11)
    let breakAccent = Color(red: 0.90, green: 0.83, blue: 0.68)

    let textDimmedWork = Color(red: 0.85, green: 0.78, blue: 0.62).opacity(0.4)
    let textDimmedBreak = Color(red: 0.90, green: 0.83, blue: 0.68).opacity(0.4)

    let ringBaseColor = Color.white.opacity(0.06)
}

/// FIREPLACE — Chimenea.
/// Naranjas cálidos y rojos apagados, brasas. Work = fuego vivo,
/// Break = brasas suaves. Cálido y hogareño, sin ser estridente.
struct FireplaceTheme: PomodoroTheme {
    let noiseName = "FIREPLACE"

    // Work: marrón rojizo muy oscuro (madera quemándose).
    let workBackground = Color(red: 0.13, green: 0.09, blue: 0.07)
    let workAccent = Color(red: 0.90, green: 0.55, blue: 0.35)

    // Break: marrón cálido con brasa (ámbar).
    let breakBackground = Color(red: 0.14, green: 0.10, blue: 0.08)
    let breakAccent = Color(red: 0.95, green: 0.68, blue: 0.45)

    let textDimmedWork = Color(red: 0.90, green: 0.55, blue: 0.35).opacity(0.4)
    let textDimmedBreak = Color(red: 0.95, green: 0.68, blue: 0.45).opacity(0.4)

    let ringBaseColor = Color.white.opacity(0.06)
}

// MARK: - Fallback

struct DefaultNoiseTheme: PomodoroTheme {
    let noiseName = "NO NOISE"
    let workBackground = Color(red: 0.11, green: 0.12, blue: 0.13)
    let workAccent = Color(red: 0.60, green: 0.70, blue: 0.90)
    let breakBackground = Color(red: 0.10, green: 0.13, blue: 0.15)
    let breakAccent = Color(red: 0.50, green: 0.80, blue: 0.85)
    let textDimmedWork = Color(red: 0.60, green: 0.70, blue: 0.90).opacity(0.4)
    let textDimmedBreak = Color(red: 0.50, green: 0.80, blue: 0.85).opacity(0.4)
    let ringBaseColor = Color.white.opacity(0.06)
}

// MARK: - ThemeManager

struct ThemeManager {
    static func getTheme(for noiseId: Int) -> PomodoroTheme {
        switch noiseId {
        case 1: return BrownNoiseTheme()
        case 2: return PinkNoiseTheme()
        case 3: return WhiteNoiseTheme()
        case 4: return VioletNoiseTheme()
        case 5: return NatureTheme()
        case 6: return RainTheme()
        case 7: return OceanTheme()
        case 8: return ClassicalTheme()
        case 9: return FireplaceTheme()
        default: return DefaultNoiseTheme()
        }
    }
}
