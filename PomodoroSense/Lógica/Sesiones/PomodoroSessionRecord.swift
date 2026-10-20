//
//  PomodoroSessionRecord.swift
//  PomodoroSense
//

import Foundation

// MARK: - Registro de una sesión de foco completada
struct PomodoroSessionRecord: Codable, Identifiable, Hashable {

    // MARK: - Identidad

    let id: UUID
    /// UUID del dispositivo que creó el record.
    let ownerDeviceId: UUID

    // MARK: - Tiempo

    /// Día al que pertenece el record. Es `var` para permitir que
    /// `SessionStore.reassignPresetToDate(_:to:)` mueva toda la corrida
    /// al día del cierre (cruce de medianoche).
    var dayStart: Date
    /// Duración del break del preset (en minutos). `nil` en records viejos.
    var breakMinutes: Int?
    /// Momento exacto en que se creó el record. Nunca se muta.
    let timestamp: Date

    // MARK: - Contenido de la sesión

    let presetName: String
    let focusMinutes: Int
    let sessionNumber: Int
    let totalSessions: Int
    var wasSkipped: Bool
    var wasInterrupted: Bool

    /// Calidad calculada al momento de crear el record (0–5).
    /// Si es `nil` (record viejo), se calcula on-the-fly con
    /// `SessionQuality.from(minutes:)` al leer.
    var quality: Int?

    // MARK: - Corrida del preset

    /// UUID de la corrida del preset. Todos los records creados durante
    /// el mismo preset (focus 1..N) comparten este ID. Se usa para:
    ///   - Agrupar records al momento de acreditar chips (solo al cierre).
    ///   - Invalidar toda la corrida si hubo un skip.
    ///   - Reasignar el `dayStart` de la corrida al día del cierre.
    /// `nil` en records viejos o creados fuera de un preset.
    var presetRunId: UUID?

    /// Si la corrida del preset fue invalidada (skip o STOP a mitad), todos
    /// sus records quedan marcados para no acreditar chips ni contar para
    /// el calendario. Se setea en masa vía `SessionStore.markPresetInvalidated`.
    var presetInvalidated: Bool

    /// IDs de los devices con los que este record fue compartido durante
    /// una sesión en mirror.
    ///
    /// Reglas:
    /// - Sin mirror activo: `[]`.
    /// - Master en mirror: `[mirrorPeerId]` (yo soy el dueño, se lo mandé al mirror).
    /// - Slave en mirror: `[myPeerId]` (el master me lo mandó, somos co-dueños).
    /// - Snapshot puro (recibido al conectar sin ser de una sesión compartida): `[]`.
    ///
    /// Se usa para purgar records remotos puros al desconectar sin perder
    /// los compartidos legítimos.
    var mirroredToDeviceIds: Set<UUID>

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id, ownerDeviceId, dayStart, timestamp, presetName
        case focusMinutes, sessionNumber, totalSessions
        case wasSkipped, wasInterrupted
        case quality
        case mirroredToDeviceIds
        case presetRunId, presetInvalidated
        case breakMinutes
    }

    // MARK: - Init desde decoder (tolerante)

    /// Decoder tolerante: si un record viejo no tiene `ownerDeviceId`,
    /// `wasSkipped`, `wasInterrupted`, `quality`, `mirroredToDeviceIds`,
    /// `presetRunId`, `presetInvalidated` o `breakMinutes`, se les asigna
    /// un default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        ownerDeviceId  = try c.decodeIfPresent(UUID.self, forKey: .ownerDeviceId) ?? UUID()
        dayStart       = try c.decode(Date.self,   forKey: .dayStart)
        timestamp      = try c.decode(Date.self,   forKey: .timestamp)
        presetName     = try c.decode(String.self, forKey: .presetName)
        focusMinutes   = try c.decode(Int.self,    forKey: .focusMinutes)
        sessionNumber  = try c.decode(Int.self,    forKey: .sessionNumber)
        totalSessions  = try c.decode(Int.self,    forKey: .totalSessions)
        wasSkipped     = try c.decodeIfPresent(Bool.self, forKey: .wasSkipped) ?? false
        wasInterrupted = try c.decodeIfPresent(Bool.self, forKey: .wasInterrupted) ?? false
        quality        = try c.decodeIfPresent(Int.self,  forKey: .quality)
        mirroredToDeviceIds = try c.decodeIfPresent(Set<UUID>.self, forKey: .mirroredToDeviceIds) ?? []
        presetRunId    = try c.decodeIfPresent(UUID.self, forKey: .presetRunId)
        presetInvalidated = try c.decodeIfPresent(Bool.self, forKey: .presetInvalidated) ?? false
        breakMinutes   = try c.decodeIfPresent(Int.self, forKey: .breakMinutes)
    }

    // MARK: - Init designado

    init(
        id: UUID,
        ownerDeviceId: UUID,
        dayStart: Date,
        timestamp: Date,
        presetName: String,
        focusMinutes: Int,
        sessionNumber: Int,
        totalSessions: Int,
        wasSkipped: Bool = false,
        wasInterrupted: Bool = false,
        quality: Int? = nil,
        mirroredToDeviceIds: Set<UUID> = [],
        presetRunId: UUID? = nil,
        presetInvalidated: Bool = false,
        breakMinutes: Int? = nil
    ) {
        self.id = id
        self.ownerDeviceId = ownerDeviceId
        self.dayStart = dayStart
        self.timestamp = timestamp
        self.presetName = presetName
        self.focusMinutes = focusMinutes
        self.sessionNumber = sessionNumber
        self.totalSessions = totalSessions
        self.wasSkipped = wasSkipped
        self.wasInterrupted = wasInterrupted
        self.quality = quality
        self.mirroredToDeviceIds = mirroredToDeviceIds
        self.presetRunId = presetRunId
        self.presetInvalidated = presetInvalidated
        self.breakMinutes = breakMinutes
    }

    // MARK: - Cómputos

    /// ¿Da chips? Ni salteadas, ni interrumpidas, ni corridas invalidadas.
    var qualifiesForChips: Bool {
        !wasSkipped && !wasInterrupted && !presetInvalidated
    }

    /// Calidad efectiva del record.
    /// Si el `quality` persistido es `nil` (record viejo), lo calculamos
    /// on-the-fly a partir de los minutos. Si ya está seteado, lo devolvemos.
    var effectiveQuality: Int {
        quality ?? SessionQuality.from(minutes: focusMinutes)
    }

    /// `true` si este record es un snapshot remoto puro: no es mío y no
    /// fue compartido conmigo por una sesión en mirror. Se purga al
    /// desconectar para no dejar basura.
    func isRemoteOnly(forMyPeerId myId: UUID) -> Bool {
        ownerDeviceId != myId && mirroredToDeviceIds.isEmpty
    }
}

// MARK: - Perfil de usuario (invisible, para futuro)
struct UserProfile: Codable, Hashable {
    let id: UUID
    var displayName: String?
    var joinedAt: Date
    var trophiesOwned: [String]

    static func makeDefault() -> UserProfile {
        UserProfile(id: UUID(),
                    displayName: nil,
                    joinedAt: Date(),
                    trophiesOwned: [])
    }
}

// MARK: - Reward por sesión
struct SessionReward {
    let points: Int          // lo que suma esta sesión al score del día
    let multiplier: Double   // racha aplicada
    let isLucky: Bool        // para animación especial
}

// MARK: - Cálculo de puntos estilo casino
//
// Sistema en tres capas:
//   1. Chips base por sesión  → curva de hockey según duración.
//   2. Decay del día           → las primeras 4 valen 100%; luego -10% por sesión.
//   3. Multiplicador de racha  → eje central. Cap 10x.
enum ScoreCalculator {

    // MARK: Configuración
    // ⚠️ Todos los parámetros viven en `ScoreBalance.swift`.
    // No editar valores acá; editar en ScoreBalance.
    static var maxSessionMinutes: Int    { ScoreBalance.maxSessionMinutes }
    static var minChipMinutes: Int       { ScoreBalance.minChipMinutes }
    static var minConsolationMinutes: Int { ScoreBalance.minConsolationMinutes }
    static var freeSessionsPerDay: Int   { ScoreBalance.freeSessionsPerDay }
    static var streakCap: Double         { ScoreBalance.streakCap }
    static var luckyPercent: UInt64      { ScoreBalance.luckyPercent }
    static var luckyBoost: Double        { ScoreBalance.luckyBoost }

    // MARK: Curva por sesión
    /// 30→2 · 35→3 · 40→4 · 45→7 · 50→10 · 55→15 · 60→20
    /// Los parámetros están en `ScoreBalance.swift`.
    static func sessionChips(forMinutes minutes: Int) -> Int {
        let m = min(max(minutes, 0), maxSessionMinutes)
        guard m >= minChipMinutes else { return 0 }
        let t = Double(m - minChipMinutes) / Double(maxSessionMinutes - minChipMinutes)
        return ScoreBalance.chipCurveBase + Int((t * t * Double(ScoreBalance.chipCurveQuadratic)).rounded())
    }

    /// Chips base por duración, ya con el bonus de calidad aplicado.
    /// Ej: 60 min (base 20) * calidad 5 (1.10) = 22 chips.
    /// Ej: 60 min (base 20) * calidad 2 (1.02) = 20 chips (redondeo).
    static func sessionChipsWithQuality(forMinutes minutes: Int, quality: Int) -> Int {
        let base = Double(sessionChips(forMinutes: minutes))
        let mult = SessionQuality.chipMultiplier(for: quality)
        return Int((base * mult).rounded())
    }

    // MARK: Decay del día
    /// Las primeras 4 sesiones valen 100 %; luego decae.
    static func dayDecay(sessionIndex: Int) -> Double {
        let extra = sessionIndex - ScoreBalance.freeSessionsPerDay
        return extra > 0
            ? pow(ScoreBalance.decayPerExtraSession, Double(extra))
            : 1.0
    }

    // MARK: Racha
    static func streakMultiplier(consecutiveDays: Int) -> Double {
        guard consecutiveDays > 0 else { return 1.0 }
        return min(
            pow(ScoreBalance.streakBaseMultiplier, Double(consecutiveDays - 1)),
            ScoreBalance.streakCap
        )
    }

    // MARK: Reward por sesión
    /// Desglose por sesión. Suma de `points` == `dailyScore`.
    static func rewards(records: [PomodoroSessionRecord], streakDays: Int) -> [SessionReward] {
        let completed = records
            .filter { $0.qualifiesForChips }
            .sorted { $0.timestamp < $1.timestamp }

        guard !completed.isEmpty else { return [] }

        let mult = streakMultiplier(consecutiveDays: streakDays)
        var running = 0.0
        var previousPoints = 0
        var result: [SessionReward] = []

        for (index, record) in completed.enumerated() {
            // Base con bonus de calidad aplicado.
            var base = Double(
                sessionChipsWithQuality(
                    forMinutes: record.focusMinutes,
                    quality: record.effectiveQuality
                )
            )

            // Consolación: sesión ≥15 min que normalmente da 0.
            if base == 0,
               record.focusMinutes >= minConsolationMinutes,
               streakDays >= 2 || index >= 1 {
                base = 1
            }

            // Lucky: solo en sesiones "de verdad" (≥30 min).
            let lucky = record.focusMinutes >= minChipMinutes
                && isLucky(seed: Int(record.timestamp.timeIntervalSince1970))
            if lucky { base *= luckyBoost }

            running += base * dayDecay(sessionIndex: index + 1)
            let cumulative = Int((running * mult).rounded())
            result.append(SessionReward(points: cumulative - previousPoints,
                                        multiplier: mult,
                                        isLucky: lucky))
            previousPoints = cumulative
        }
        return result
    }

    static func dailyScore(records: [PomodoroSessionRecord], streakDays: Int) -> Int {
        rewards(records: records, streakDays: streakDays).reduce(0) { $0 + $1.points }
    }

    // MARK: Etiquetas (solo display)
    static func comboLabel(sessionsToday: Int, totalInPreset: Int) -> String {
        if sessionsToday <= 0 { return "" }
        if totalInPreset > 0 && sessionsToday >= totalInPreset { return "JACKPOT" }
        if sessionsToday >= 3 { return "HOT STREAK" }
        if sessionsToday == 2 { return "COMBO x2" }
        return "WARM UP"
    }

    // MARK: Lucky
    /// Hash estable (splitmix64): mismo timestamp → mismo resultado siempre.
    private static func isLucky(seed: Int) -> Bool {
        var x = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x ^= x >> 31
        return x % 100 < luckyPercent
    }
}

extension ScoreCalculator {

    // MARK: - Ganancias por tier

    /// Calcula cuánto gana el usuario en cada tier con una sesión.
    /// Devuelve un diccionario `[CurrencyTier: Int]`.
    ///
    /// Reglas:
    /// - **Bronze**: siempre otorga. Cap natural en el multiplicador de racha día 26.
    /// - **Silver**: sólo si está desbloqueado. Crece con la racha *por encima* del día 26.
    /// - **Gold**: sólo si está desbloqueado. Placeholder 1x hasta definir balanceo final.
    static func tierEarnings(
        for record: PomodoroSessionRecord,
        streakDays: Int,
        wallet: CurrencyWallet
    ) -> [CurrencyTier: Int] {
        let base = Double(
            sessionChipsWithQuality(
                forMinutes: record.focusMinutes,
                quality: record.effectiveQuality
            )
        )
        guard base > 0 else { return [:] }

        var earnings: [CurrencyTier: Int] = [:]

        // Bronze (siempre acredita, tope natural en 1000)
        let bronzeMult = bronzeMultiplier(streakDays: streakDays)
        earnings[.bronze] = Int((base * bronzeMult).rounded())

        // Silver (solo desbloqueado, más difícil)
        if wallet.isUnlocked(.silver) {
            let silverMult = silverMultiplier(streakDays: streakDays)
            let silverRaw = base * silverMult / CurrencyTier.silver.difficultyMultiplier
            let amount = Int(silverRaw.rounded())
            if amount > 0 { earnings[.silver] = amount }
        }

        // GOLD (La mecánica secreta)
        if wallet.isUnlocked(.gold) {
            // Solo se gana oro si la sesión es INTENSA (90+ minutos).
            if record.focusMinutes >= 90 {
                let goldAmount = record.focusMinutes / 90
                earnings[.gold] = goldAmount
            }
        }

        return earnings
    }

    // MARK: - Curvas por tier (ajustables)

    /// Multiplicador de racha para Bronze.
    /// Actual: `pow(1.1, days-1)` con cap 10x en día 26.
    static func bronzeMultiplier(streakDays: Int) -> Double {
        guard streakDays > 0 else { return 1.0 }
        return min(
            pow(ScoreBalance.streakBaseMultiplier, Double(streakDays - 1)),
            ScoreBalance.bronzeStreakCap
        )
    }

    /// Multiplicador de racha para Silver.
    /// Solo se activa a partir del día de unlock. Curva pensada para ~2 meses
    /// de racha mantenida hasta tocar el softCap.
    /// Los parámetros viven en `ScoreBalance.swift`.
    static func silverMultiplier(streakDays: Int) -> Double {
        guard streakDays >= ScoreBalance.silverUnlockDay else { return 0 }
        let daysInSilver = Double(streakDays - ScoreBalance.silverUnlockDay + 1)
        return min(daysInSilver / ScoreBalance.silverCurveDivisor,
                   ScoreBalance.silverMultiplierCap)
    }

    /// Multiplicador de racha para Gold.
    /// Placeholder constante (1x) hasta definir balanceo final. El gating por
    /// desbloqueo se hace en `tierEarnings` vía `wallet.isUnlocked(.gold)`.
    /// El valor vive en `ScoreBalance.swift`.
    static func goldMultiplier(streakDays: Int) -> Double {
        return ScoreBalance.goldMultiplier
    }
}
