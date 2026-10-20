//
//  PomodoroStatsView.swift
//  PomodoroSense
//

import SwiftUI

// MARK: - Estado de la vista
struct PomodoroStatsViewState {
    var bronze: Int
    var silver: Int
    var gold: Int
    var currentStreak: Int
    var isSilverUnlocked: Bool
    var recordsForDate: (Date) -> [PomodoroSessionRecord]
    var goalForDate: (Date) -> DailyGoal?
    var onSaveGoal: (Date, String?) -> Void
    var onToggleGoal: (Date) -> Void
    var isGoldUnlocked: Bool
    var focusTimeForGoal: (DailyGoal) -> Int
    var focusMinutesForDate: (Date) -> Int
    var hasAnyRecordForDate: (Date) -> Bool
    var tierForDate: (Date, CalendarColorThresholds) -> CalendarColorTier
    var recentScoresForThresholds: () -> [Int]
    var onShowOwnedItems: () -> Void
    var allGoals: () -> [DailyGoal]
}

// MARK: - Vista
struct PomodoroStatsView: View {
    var state: PomodoroStatsViewState

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color
    var onDismiss: (() -> Void)? = nil

    @State private var visibleMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var thresholds: CalendarColorThresholds = .fallback
    @State private var selectedDay: Date? = nil
    @State private var showWalletPopup = false

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ZStack {
            backgroundColor

            VStack(spacing: 18) {
                header
                statsStrip
                monthNavigator
                weekdayHeader
                calendarGrid
                legend
                
                #if os(macOS)
                ownedItemsButton.hidden()
                #else
                ownedItemsButton
                #endif
                
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task {
            thresholds = CalendarColorCalculator.calculateThresholds(
                from: state.recentScoresForThresholds()
            )
        }
        // Popup de detalle del día
        .overlay {
            if let day = selectedDay {
                DayDetailPopup(
                    day: day,
                    records: state.recordsForDate(day),
                    goal: state.goalForDate(day),
                    accentColor: accentColor,
                    dimmedColor: dimmedColor,
                    backgroundColor: backgroundColor,
                    onSaveGoal: { state.onSaveGoal(day, $0) },
                    onToggleGoal: { state.onToggleGoal(day) },
                    onDismiss: {
                        withAnimation(HIGMotion.overlay) { selectedDay = nil }
                    },
                    focusTimeForGoal: state.focusTimeForGoal
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        // Popup de la billetera
        .overlay {
            walletPopupOverlay
        }
        #if os(macOS)
        .onExitCommand { onDismiss?() }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("STATS")
                .font(.system(size: 13, weight: .bold))
                .tracking(4)
                .foregroundColor(dimmedColor)
            Spacer()
            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(dimmedColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Strip de totales

    // MARK: - Strip de totales

    private var statsStrip: some View {
        HStack(spacing: 10) {
            // 1. Monedas
            if state.silver > 0 || state.gold > 0 {
                walletButton
            } else if state.bronze > 0 {
                tierBadge(tier: .bronze, amount: state.bronze)
            }

            // 2. Racha (solo si es mayor a 0)
            if state.currentStreak > 0 {
                statBadge(kind: .streak,
                          value: "\(state.currentStreak)",
                          label: state.currentStreak == 1 ? "DAY" : "DAYS",
                          tint: .orange)
            }
        }
        // Si no hay monedas NI racha, este HStack mide 0 y no ocupa espacio.
    }

    private var walletButton: some View {
        Button {
            Haptics.impact(.light, intensity: 0.6)
            withAnimation(HIGMotion.overlay) { showWalletPopup = true }
        } label: {
            VectorWalletView()
                .frame(width: 52, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var walletPopupOverlay: some View {
        if showWalletPopup {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(HIGMotion.overlay) { showWalletPopup = false }
                    }

                VStack(spacing: 0) {
                    HStack {
                        Text("BALANCES")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(3)
                            .foregroundColor(dimmedColor.opacity(0.6))
                        
                        Spacer()
                        
                        Button {
                            withAnimation(HIGMotion.overlay) { showWalletPopup = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(dimmedColor.opacity(0.7))
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    VStack(spacing: 4) {
                        if state.bronze > 0 {
                            walletRow(tier: .bronze, amount: state.bronze)
                        }
                        if state.silver > 0 {
                            walletRow(tier: .silver, amount: state.silver)
                        }
                        if state.gold > 0 {
                            walletRow(tier: .gold, amount: state.gold)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: 300)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(red: 0.12, green: 0.11, blue: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
    }

    private func walletRow(tier: CurrencyTier, amount: Int) -> some View {
        HStack(spacing: 16) {
            Image(systemName: tier.iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(tier.tintColor.opacity(0.8))
                .frame(width: 24)

            Text(tier.displayName)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundColor(dimmedColor.opacity(0.7))

            Spacer()

            Text("\(amount)")
                .font(.system(size: 20, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
        )
    }

    private func tierBadge(tier: CurrencyTier, amount: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tier.iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tier.tintColor)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(amount)")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(tier.displayName)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(tier.tintColor.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tier.tintColor.opacity(0.3), lineWidth: 1)
        )
    }

    private enum BadgeKind { case chips, streak }

    private func statBadge(kind: BadgeKind, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            switch kind {
            case .chips:
                CasinoChipView(size: 22, tint: tint)
            case .streak:
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(tint)
                    .shadow(color: tint.opacity(0.5), radius: 4, x: 0, y: 0)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(dimmedColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Navegador de mes

    private var monthNavigator: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentColor)
                    .minTapTarget(20)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthTitle)
                .font(.system(size: 12, weight: .semibold))
                .tracking(2)
                .foregroundColor(.white)

            Spacer()

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentColor)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: visibleMonth).uppercased()
    }

    private func previousMonth() {
        withAnimation(.easeInOut(duration: 0.2)) {
            visibleMonth = cal.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
        }
    }

    private func nextMonth() {
        withAnimation(.easeInOut(duration: 0.2)) {
            visibleMonth = cal.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
        }
    }

    // MARK: - Días de la semana

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                Text(sym)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(dimmedColor.opacity(0.7))
                    .frame(height: 14)
            }
        }
    }
    
    // MARK: - My Collection
    @ViewBuilder
    private var ownedItemsButton: some View {
        if shouldShowOwnedItems {
            Button {
                Haptics.impact(.light, intensity: 0.6)
                state.onShowOwnedItems()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("MY COLLECTION")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                }
                .foregroundColor(CurrencyTier.gold.tintColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CurrencyTier.gold.tintColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CurrencyTier.gold.tintColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private var shouldShowOwnedItems: Bool {
        !SessionStore.shared.wallet.purchasedItemIds.isEmpty
    }

    // MARK: - Grilla

    private var calendarGrid: some View {
        let days = daysInMonthGrid()
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day = day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let tier = state.tierForDate(day, thresholds)
        let hasAny = (tier != .empty)
        let tierColors = colorTier(for: tier)
        let isToday = cal.isDateInToday(day)
        let today = cal.startOfDay(for: Date())
        let isPast = day < today

        let goalOnDay = state.goalForDate(day)

        let borderGoal: DailyGoal?
        if isPast {
            borderGoal = goalOnDay
        } else {
            let allGoals = state.allGoals()
            borderGoal = allGoals.filter({ $0.dayStart >= day }).min(by: { $0.dayStart < $1.dayStart })
        }

        let goalTheme: GoalColorTheme? = borderGoal != nil ? GoalColorPalette.theme(for: borderGoal!) : nil

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(tierColors.fill)

            if let theme = goalTheme, let bg = borderGoal {
                let isCompleted = bg.completed
                let strokeColor = isCompleted ? Color.gray : theme.color
                let strokeOpacity = isCompleted ? 0.5 : (isPast ? 0.3 : 0.6)
                let shadowColor = isCompleted ? Color.clear : theme.glow.opacity(isToday ? 0.8 : 0.2)

                RoundedRectangle(cornerRadius: 6)
                    .stroke(strokeColor.opacity(strokeOpacity), lineWidth: 2)
                    .shadow(color: shadowColor, radius: isToday ? 8 : 4)
            }

            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(hasAny ? .white : dimmedColor.opacity(0.55))

            if hasAny {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(tierColors.border)
                        .frame(width: 12, height: 2)
                        .cornerRadius(1)
                        .padding(.bottom, 4)
                }
            }

            if let goal = goalOnDay {
                let theme = GoalColorPalette.theme(for: goal)
                VStack {
                    HStack {
                        Spacer()
                        StrikethroughStar(color: theme.color, isCompleted: goal.completed)
                            .padding(4)
                    }
                    Spacer()
                }
                .opacity(isPast ? 0.5 : 1.0)
            }

            if isToday {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(accentColor, lineWidth: 1.5)
                    .shadow(color: accentColor.opacity(0.5), radius: 3)
            }
        }
        .frame(height: 34)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            Haptics.selection()
            withAnimation(HIGMotion.overlay) { selectedDay = day }
        }
        .animation(.easeInOut(duration: 0.2), value: goalOnDay?.completed)
    }

    // MARK: - Escala de color

    private struct Tier {
        let fill: Color
        let border: Color
    }

    private func colorTier(for tier: CalendarColorTier) -> Tier {
        switch tier {
        case .empty:
            return Tier(fill: Color.white.opacity(0.03), border: .clear)
        case .noFocus:
            return Tier(fill: accentColor.opacity(0.08),
                        border: accentColor.opacity(0.25))
        case .level1:
            return Tier(fill: accentColor.opacity(0.20),
                        border: accentColor.opacity(0.50))
        case .level2:
            return Tier(fill: accentColor.opacity(0.38),
                        border: accentColor.opacity(0.70))
        case .level3:
            return Tier(fill: accentColor.opacity(0.58),
                        border: accentColor.opacity(0.90))
        case .level4:
            return Tier(fill: accentColor.opacity(0.78),
                        border: .white.opacity(0.85))
        case .level5:
            return Tier(fill: accentColor,
                        border: .white.opacity(0.95))
        }
    }

    // MARK: - Leyenda

    private var legend: some View {
        HStack(spacing: 6) {
            Text("LESS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundColor(dimmedColor.opacity(0.7))

            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor.opacity([0.18, 0.38, 0.65, 1.0][i]))
                    .frame(width: 12, height: 12)
            }

            Text("MORE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundColor(dimmedColor.opacity(0.7))
        }
    }

    // MARK: - Cálculo de días

    private func daysInMonthGrid() -> [Date?] {
        guard let monthInterval = cal.dateInterval(of: .month, for: visibleMonth),
              let firstWeekday = cal.dateComponents([.weekday], from: monthInterval.start).weekday
        else { return [] }

        let days = cal.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
        let leading = firstWeekday - 1

        var result: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<days {
            if let d = cal.date(byAdding: .day, value: offset, to: monthInterval.start) {
                result.append(d)
            }
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }
}

extension View {
    func glowPulse(color: Color) -> some View {
        self.modifier(GlowPulseModifier(color: color))
    }
}

struct GlowPulseModifier: ViewModifier {
    let color: Color
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(isPulsing ? 0.9 : 0.3), radius: isPulsing ? 6 : 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
