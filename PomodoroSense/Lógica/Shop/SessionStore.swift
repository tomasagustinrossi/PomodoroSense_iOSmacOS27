import Foundation
import Combine
import WidgetKit // <-- NECESARIO PARA RECARGAR EL WIDGET

@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()
    @Published private(set) var wallet: CurrencyWallet = CurrencyWallet()

    @Published private(set) var records: [PomodoroSessionRecord] = []
    /// Reportes agregados de meses antiguos (fuera de la ventana de 90 días).
    @Published private(set) var monthlyReports: [MonthlyReport] = []
    @Published private(set) var user: UserProfile = .makeDefault()
    @Published private(set) var dailyGoals: [DailyGoal] = []
    
    private let goalsKey = "Pomodoro_Daily_Goals"
    private let recordsKey = "Pomodoro_Session_Records"
    private let userKey    = "Pomodoro_User_Profile"
    private let reportsKey = "Pomodoro_Monthly_Reports"
    

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

#if DEBUG
    /// Verificación en runtime del acceso al App Group.
    static func debugVerifyAppGroup() {
        let appGroupId = "group.com.tomiirossi.PomodoroSense"
        print("🔍 [AppGroup Test] Intentando abrir: \(appGroupId)")

        guard let suite = UserDefaults(suiteName: appGroupId) else {
            print("🔍 [AppGroup Test] ❌ UserDefaults(suiteName:) devolvió nil")
            return
        }

        let key = "widget.debug.counter"
        let before = suite.integer(forKey: key)
        suite.set(before + 1, forKey: key)
        suite.synchronize()

        let after = suite.integer(forKey: key)
        print("🔍 [AppGroup Test] ✅ Access OK. Contador antes: \(before), después: \(after)")
        print("🔍 [AppGroup Test] Si el contador incrementa entre runs → App Group funciona.")
    }
#endif

#if DEBUG
    /// Solo para tests: inserta un record en un día específico.
    func recordCompletedSessionOn(day: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let record = PomodoroSessionRecord(
            id: UUID(),
            ownerDeviceId: SyncPersistence.shared.myPeerId,
            dayStart: start,
            timestamp: start,
            presetName: "TEST",
            focusMinutes: 30,
            sessionNumber: 1,
            totalSessions: 5,
            wasSkipped: false,
            wasInterrupted: false
        )
        records.append(record)
        persist()
    }

    /// Solo para tests: inserta un lote de records arbitrarios.
    /// Se usa desde MergedCalendarTests y SessionStoreCompactionTests.
    func insertRecordsForTest(_ newRecords: [PomodoroSessionRecord]) {
        records.append(contentsOf: newRecords)
        persist()
    }
#endif
    /// Solo para tests: deja el store como recién inicializado.
    func clearAllForTesting() {
            records.removeAll()
            monthlyReports.removeAll()
            dailyGoals.removeAll()
            persistGoals()
            wallet = CurrencyWallet()
            user = .makeDefault()
            persist()
            persistWallet()
            persistMonthlyReports()
            persistUser()
            // Limpiar también el estado de sesión persistido (session_isRunning,
            // session_isBreak, session_currentSession, etc.). Sin esto, un test
            // que terminó en break filtran `isBreak = true` al próximo
            // `TimerViewModel()` vía `restorePersistedState()`.
            TimerViewModel.clearPersistedSessionKeys()
    }
    

    // MARK: - Export / Merge

    /// Devuelve todos los records para sincronización.
    nonisolated func exportAllRecords() async -> [PomodoroSessionRecord] {
        await MainActor.run { self.records }
    }

    // MARK: - Corridas de preset (Fase 1)

    /// Marca toda una corrida de preset como inválida. Todos los records con
    /// ese `presetRunId` pasan a tener `presetInvalidated = true`, lo que los
    /// excluye de chips y del calendario.
    /// Se llama cuando el usuario saltea un focus, o presiona STOP.
    /// Retorna la cantidad de records afectados.
    @discardableResult
    func markPresetInvalidated(_ presetRunId: UUID) -> Int {
        var affected = 0
        for i in records.indices where records[i].presetRunId == presetRunId {
            records[i].presetInvalidated = true
            affected += 1
        }
        if affected > 0 { persist() }
        return affected
    }
    
    // MARK: - Tienda

    /// Intenta comprar un item. Devuelve `true` si se concretó.
    @discardableResult
    func purchaseItem(_ item: any ShopItem) -> Bool {
        guard let newWallet = ShopCatalog.purchase(item, wallet: wallet) else { return false }
        wallet = newWallet
        persistWallet()
        return true
    }

    /// Mueve el `dayStart` de toda la corrida al día indicado. Sirve para el
    /// cruce de medianoche: un preset que arrancó 23:30 y terminó 00:15 del
    /// día siguiente cuenta entero para el segundo día.
    /// `day` puede ser cualquier Date; internamente se normaliza a startOfDay.
    /// Retorna la cantidad de records movidos.
    @discardableResult
    func reassignPresetToDate(_ presetRunId: UUID, to day: Date) -> Int {
        let normalized = Calendar.current.startOfDay(for: day)
        var affected = 0
        for i in records.indices where records[i].presetRunId == presetRunId {
            records[i].dayStart = normalized
            affected += 1
        }
        if affected > 0 { persist() }
        return affected
    }
    
    /// Invalida los records del preset en curso cuya `sessionNumber` sea >= `fromSession`.
    /// Se usa al cambiar hacia atrás a una sesión ya completada: los records de esa
    /// sesión y las posteriores se descartan (no suman chips ni calendario) porque
    /// se van a rehacer. Los records de sesiones anteriores se preservan.
    /// Devuelve la cantidad de records afectados.
    @discardableResult
    func markPresetRecordsInvalidated(_ presetRunId: UUID, fromSession: Int) -> Int {
        var affected = 0
        for i in records.indices
            where records[i].presetRunId == presetRunId
               && records[i].sessionNumber >= fromSession
               && !records[i].presetInvalidated {
            records[i].presetInvalidated = true
            affected += 1
        }
        if affected > 0 { persist() }
        return affected
    }
    
    /// Calcula la calidad global sumando los minutos de todo el preset.
    /// Reasigna esa máxima calidad a cada sesión individual y retorna las válidas.
    @discardableResult
    func commitAndCalculateGlobalQuality(forPresetRunId presetRunId: UUID) -> [PomodoroSessionRecord] {
        let runRecords = records(forPresetRunId: presetRunId).filter { $0.qualifiesForChips }
        guard !runRecords.isEmpty else { return [] }

        // Sumar todos los minutos del preset para obtener la calidad global
        let totalMinutes = runRecords.reduce(0) { $0 + $1.focusMinutes }
        let globalQuality = SessionQuality.from(minutes: totalMinutes)

        var affected = 0
        for i in records.indices where records[i].presetRunId == presetRunId && records[i].qualifiesForChips {
            // Asigna la calidad más alta a todas las sesiones de esta corrida
            records[i].quality = globalQuality
            affected += 1
        }
        
        if affected > 0 { persist() }
        
        return records(forPresetRunId: presetRunId).filter { $0.qualifiesForChips }
    }


    /// Devuelve todos los records de una corrida de preset.
    /// Ordenados por timestamp ascendente.
    func records(forPresetRunId presetRunId: UUID) -> [PomodoroSessionRecord] {
        records
            .filter { $0.presetRunId == presetRunId }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Registro

    @discardableResult
    func recordCompletedSession(
        presetName: String,
        focusMinutes: Int,
        sessionNumber: Int,
        breakMinutes: Int? = nil,
        totalSessions: Int,
        mirroredToDeviceIds: Set<UUID> = [],
        presetRunId: UUID? = nil
    ) -> PomodoroSessionRecord {
        let cal = Calendar.current
        let now = Date()
        let record = PomodoroSessionRecord(
            id: UUID(),
            ownerDeviceId: SyncPersistence.shared.myPeerId,
            dayStart: cal.startOfDay(for: now),
            timestamp: now,
            presetName: presetName,
            focusMinutes: focusMinutes,
            sessionNumber: sessionNumber,
            totalSessions: totalSessions,
            wasSkipped: false,
            wasInterrupted: false,
            quality: SessionQuality.from(minutes: focusMinutes),
            mirroredToDeviceIds: mirroredToDeviceIds,
            presetRunId: presetRunId,
            breakMinutes: breakMinutes
        )
        records.append(record)
        persist()
        return record
    }

    @discardableResult
    func recordSkippedSession(
        presetName: String,
        focusMinutes: Int,
        sessionNumber: Int,
        breakMinutes: Int? = nil,
        totalSessions: Int,
        presetRunId: UUID? = nil
    ) -> PomodoroSessionRecord {
        let cal = Calendar.current
        let now = Date()
        let record = PomodoroSessionRecord(
            id: UUID(),
            ownerDeviceId: SyncPersistence.shared.myPeerId,
            dayStart: cal.startOfDay(for: now),
            timestamp: now,
            presetName: presetName,
            focusMinutes: focusMinutes,
            sessionNumber: sessionNumber,
            totalSessions: totalSessions,
            wasSkipped: true,
            wasInterrupted: false,
            quality: 0,
            presetRunId: presetRunId,
            breakMinutes: breakMinutes
        )
        records.append(record)
        persist()
        return record
    }

    func recordInterruptedSession(
        presetName: String,
        focusMinutes: Int,
        sessionNumber: Int,
        breakMinutes: Int? = nil,
        totalSessions: Int,
        presetRunId: UUID? = nil
    ) {
        let cal = Calendar.current
        let now = Date()
        let record = PomodoroSessionRecord(
            id: UUID(),
            ownerDeviceId: SyncPersistence.shared.myPeerId,
            dayStart: cal.startOfDay(for: now),
            timestamp: now,
            presetName: presetName,
            focusMinutes: focusMinutes,
            sessionNumber: sessionNumber,
            totalSessions: totalSessions,
            wasSkipped: false,
            wasInterrupted: true,
            quality: 0,
            presetRunId: presetRunId,
            breakMinutes: breakMinutes
        )
        records.append(record)
        persist()
    }
    // MARK: - Consultas para la UI

    func records(on day: Date) -> [PomodoroSessionRecord] {
        let cal = Calendar.current
        let target = cal.startOfDay(for: day)
        return records.filter { cal.isDate($0.dayStart, inSameDayAs: target) }
    }

    func totalFocusMinutes(on date: Date) -> Int {
        let targetDay = Calendar.current.startOfDay(for: date)
        return records
            .filter { Calendar.current.isDate($0.dayStart, inSameDayAs: targetDay) }
            // FIX: Asegurar que se omitan las sesiones salteadas, interrumpidas y los presets invalidados
            .filter { !$0.wasSkipped && !$0.wasInterrupted && !$0.presetInvalidated }
            .reduce(0) { $0 + $1.focusMinutes }
    }


    /// ¿Hay algún record VÁLIDO (no invalidado por skip/STOP) para el día?
    /// Un día con todo invalidado se considera vacío para el calendario.
    func hasAnyRecord(on day: Date) -> Bool {
        records(on: day).contains { !$0.presetInvalidated }
    }

    func score(on day: Date) -> Int {
        let dayRecords = records(on: day)
        guard !dayRecords.isEmpty else { return 0 }
        let streak = streakEnding(on: day)
        return ScoreCalculator.dailyScore(records: dayRecords, streakDays: streak)
    }

    /// Score de calendario del día: suma de `focusMinutes × quality` de las
    /// sesiones completadas. Se usa para colorear el calendario.
    /// No confundir con `score(on:)` (que es el score de chips).
    func calendarScore(on day: Date) -> Int {
        records(on: day)
            .filter { $0.qualifiesForChips }
            .reduce(0) { sum, record in
                sum + record.focusMinutes * record.effectiveQuality
            }
    }

    var totalChips: Int {
        let grouped = Dictionary(grouping: records) { $0.dayStart }
        return grouped.reduce(0) { acc, pair in
            let day = pair.key
            let dayRecords = pair.value
            let streak = streakEnding(on: day)
            return acc + ScoreCalculator.dailyScore(records: dayRecords, streakDays: streak)
        }
    }

    func streakEnding(on day: Date) -> Int {
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: day)
        var streak = 0
        // Solo records válidos cuentan para la racha: un día con todo
        // invalidado no rompe ni suma.
        let daysWithSessions = Set(
            records.filter { !$0.presetInvalidated }.map { $0.dayStart }
        )

        while daysWithSessions.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Racha actual. Estricta: si hoy no arrancaste ninguna sesión, es 0.
    var currentStreak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let daysWithSessions = Set(
            records.filter { !$0.presetInvalidated }.map { $0.dayStart }
        )

        guard daysWithSessions.contains(today) else { return 0 }
        return streakEnding(on: today)
    }

    func comboLabel(on day: Date) -> String {
        let dayRecords = records(on: day)
        guard let first = dayRecords.first else { return "" }
        return ScoreCalculator.comboLabel(
            sessionsToday: dayRecords.count,
            totalInPreset: first.totalSessions
        )
    }

    /// Scores de los últimos `days` días (excluyendo hoy). Se usa para
    /// calcular los percentiles del calendario dinámico.
    func recentCalendarScores(days: Int) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var scores: [Int] = []
        scores.reserveCapacity(days)
        for offset in 1...days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            scores.append(calendarScore(on: day))
        }
        return scores
    }

    // MARK: - Persistencia

    private func load() {
        if let data = defaults.data(forKey: "Pomodoro_Currency_Wallet"),
           let decoded = try? JSONDecoder().decode(CurrencyWallet.self, from: data) {
            wallet = decoded
        } else {
            wallet = CurrencyWallet()
        }

        if let data = defaults.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([PomodoroSessionRecord].self, from: data) {
            records = decoded
        }

        if let data = defaults.data(forKey: reportsKey),
           let decoded = try? JSONDecoder().decode([MonthlyReport].self, from: data) {
            monthlyReports = decoded
        }
        if let data = defaults.data(forKey: userKey),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            user = decoded
        } else {
            user = .makeDefault()
            persistUser()
        }
        if let data = defaults.data(forKey: goalsKey),
           let decoded = try? JSONDecoder().decode([DailyGoal].self, from: data) {
            dailyGoals = decoded
        }
        
        
        if let data = defaults.data(forKey: goalsKey),
           let decoded = try? JSONDecoder().decode([DailyGoal].self, from: data) {
            dailyGoals = decoded
        }

        // Compacta records antiguos en reports. Corre en cada arranque;
        // si no hay nada para compactar, es no-op.
        compactOldRecordsIfNeeded()
    }
    
    // MARK: - API de goals
    func goal(on day: Date) -> DailyGoal? {
        let target = Calendar.current.startOfDay(for: day)
        return dailyGoals.first { Calendar.current.isDate($0.dayStart, inSameDayAs: target) }
    }

    func setGoalText(for day: Date, text: String?) {
        let target = Calendar.current.startOfDay(for: day)
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            dailyGoals.removeAll { Calendar.current.isDate($0.dayStart, inSameDayAs: target) }
        } else if let idx = dailyGoals.firstIndex(where: {
            Calendar.current.isDate($0.dayStart, inSameDayAs: target)
        }) {
            dailyGoals[idx].text = trimmed
        } else {
            dailyGoals.append(DailyGoal(dayStart: target, text: trimmed))
        }
        persistGoals()
    }

    func toggleGoalCompletion(on day: Date) {
        let target = Calendar.current.startOfDay(for: day)
        if let idx = dailyGoals.firstIndex(where: {
            Calendar.current.isDate($0.dayStart, inSameDayAs: target)
        }) {
            dailyGoals[idx].completed.toggle()
            persistGoals()
        }
    }

    private func persistGoals() {
        if let data = try? JSONEncoder().encode(dailyGoals) {
            defaults.set(data, forKey: goalsKey)
        }
    }


    private func persistWallet() {
        if let data = try? JSONEncoder().encode(wallet) {
            defaults.set(data, forKey: "Pomodoro_Currency_Wallet")
        }
        self.syncWidgetData()
    }

    /// Acredita las ganancias de una sesión en el wallet y reevalúa desbloqueos.
    /// Devuelve el monto REALMENTE acreditado por tier (puede ser menor que
    /// `earnings` si el wallet ya está en el softCap).
    @discardableResult
    func creditSession(
        _ earnings: [CurrencyTier: Int],
        streakDays: Int
    ) -> [CurrencyTier: Int] {
        var newWallet = wallet
        var actuallyCredited: [CurrencyTier: Int] = [:]

        for (tier, amount) in earnings {
            let before = newWallet[tier]
            newWallet.add(amount, to: tier)
            let delta = newWallet[tier] - before
            if delta > 0 { actuallyCredited[tier] = delta }
        }

        newWallet.reevaluateUnlocks(streakDays: streakDays)
        wallet = newWallet
        persistWallet()
        return actuallyCredited
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: recordsKey)
        }
        self.syncWidgetData()
    }

    private func persistUser() {
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: userKey)
        }
    }

    func addTrophy(_ id: String) {
        user.trophiesOwned.append(id)
        persistUser()
    }

    // MARK: - Purga de records remotos al desconectar

    /// Borra los records que son **snapshots remotos puros**: tienen
    /// `ownerDeviceId != myPeerId` y no fueron compartidos conmigo por
    /// una sesión en mirror (mirroredToDeviceIds vacío).
    @discardableResult
    func purgeRemoteOnlyRecords() -> Int {
        let myId = SyncPersistence.shared.myPeerId
        let before = records.count
        records.removeAll { $0.isRemoteOnly(forMyPeerId: myId) }
        let removed = before - records.count
        if removed > 0 {
            persist()
        }
        return removed
    }
    

    // MARK: - Compactación de records antiguos

    /// Retención: mantenemos los últimos 90 días de records individuales
    /// para el calendario detallado. Los meses anteriores se agregan en
    /// `MonthlyReport` y sus records individuales se borran.
    func compactOldRecordsIfNeeded() {
        let cal = Calendar.current
        let now = Date()

        // Cutoff exacto: 90 días atrás (startOfDay).
        // Antes se usaba "primer día del mes que está 90 días atrás",
        // lo que extendía la retención hasta ~120 días según el día del mes.
        // El doc dice "últimos 90 días" y los tests lo validan: usamos la
        // fecha exacta.
        guard let cutoffDate = cal.date(byAdding: .day, value: -90, to: now) else { return }
        let cutoff = cal.startOfDay(for: cutoffDate)

        // Records elegibles: anteriores al cutoff.
        let eligibleRecords = records.filter { $0.dayStart < cutoff }
        guard !eligibleRecords.isEmpty else { return }

        // Agrupar por (year, month).
        struct MonthKey: Hashable {
            let year: Int
            let month: Int
        }

        let grouped = Dictionary(grouping: eligibleRecords) { record -> MonthKey in
            let comps = cal.dateComponents([.year, .month], from: record.dayStart)
            return MonthKey(year: comps.year ?? 0, month: comps.month ?? 0)
        }

        var updatedReports = monthlyReports
        var keysToPurge = Set<MonthKey>()

        for (key, monthRecords) in grouped {
            let existing = updatedReports.first {
                $0.year == key.year && $0.month == key.month
            }

            if existing == nil {
                let report = buildMonthlyReport(
                    from: monthRecords,
                    year: key.year,
                    month: key.month
                )
                updatedReports.append(report)
            }

            keysToPurge.insert(key)
        }

        updatedReports.sort { ($0.year, $0.month) > ($1.year, $1.month) }
        monthlyReports = updatedReports
        persistMonthlyReports()

        records.removeAll { record in
            let comps = cal.dateComponents([.year, .month], from: record.dayStart)
            return keysToPurge.contains(
                MonthKey(year: comps.year ?? 0, month: comps.month ?? 0)
            )
        }
        persist()
    }

    /// Construye un reporte a partir de los records de un mes.
    private func buildMonthlyReport(
        from monthRecords: [PomodoroSessionRecord],
        year: Int,
        month: Int
    ) -> MonthlyReport {
        let cal = Calendar.current

        let completed = monthRecords.filter { $0.qualifiesForChips }
        let skipped = monthRecords.filter { $0.wasSkipped }
        let interrupted = monthRecords.filter { $0.wasInterrupted }

        let totalMinutes = completed.reduce(0) { $0 + $1.focusMinutes }

        var bronze = 0
        let fakeWallet = CurrencyWallet()
        for record in completed {
            let earnings = ScoreCalculator.tierEarnings(
                for: record,
                streakDays: 1,
                wallet: fakeWallet
            )
            bronze += earnings[.bronze] ?? 0
        }

        let longest = Self.longestStreak(in: monthRecords)

        let activeDays: Set<Int> = Set(
            monthRecords.compactMap { record in
                cal.dateComponents([.day], from: record.dayStart).day
            }
        )

        return MonthlyReport(
            year: year,
            month: month,
            totalFocusMinutes: totalMinutes,
            totalSessionsCompleted: completed.count,
            totalSessionsSkipped: skipped.count,
            totalSessionsInterrupted: interrupted.count,
            bronzeEarned: bronze,
            silverEarned: 0,
            goldEarned: 0,
            longestStreakInMonth: longest,
            activeDays: activeDays
        )
    }

    /// Calcula la racha más larga dentro de un conjunto de records.
    private static func longestStreak(in records: [PomodoroSessionRecord]) -> Int {
        let cal = Calendar.current
        let days = Set(records.map { cal.startOfDay(for: $0.dayStart) }).sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for i in 1..<days.count {
            let prev = days[i - 1]
            let curr = days[i]

            if let expected = cal.date(byAdding: .day, value: 1, to: prev),
               cal.isDate(expected, inSameDayAs: curr) {
                current += 1
            } else {
                longest = max(longest, current)
                current = 1
            }
        }
        return max(longest, current)
    }

    /// Persiste los reports mensuales.
    private func persistMonthlyReports() {
        if let data = try? JSONEncoder().encode(monthlyReports) {
            defaults.set(data, forKey: reportsKey)
        }
    }

    // MARK: - Sincronización con Widgets (IPC)

    private func syncWidgetData() {
        let economy = WidgetEconomyState(
            bronze: wallet.bronze,
            silver: wallet.silver,
            gold: wallet.gold,
            streak: currentStreak,
            hasRecordsToday: hasAnyRecord(on: Date())
        )

        WidgetShared.writeEconomyState(economy)
        WidgetShared.reloadWidgets()
    }
}
