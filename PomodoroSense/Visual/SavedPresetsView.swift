//
//  SavedPresetsView.swift
//  PomodoroSense
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Vista de Presets Guardados

struct SavedPresetsView: View {

    // MARK: - Constantes
    private static let selectedPresetKey = "Selected_Preset_Id"

    // MARK: - Inyección de Dependencias
    @ObservedObject var presetsVM: PresetsViewModel
    @ObservedObject var timerVM: TimerViewModel
    @ObservedObject var freeModeVM: FreeModeViewModel
    @ObservedObject private var store = SessionStore.shared

    var isTimerActive: Bool = false
    var activeConfigId: UUID? = nil
    @Binding var pendingSelectionId: UUID?
    var onNavigate: ((AppScreen, PomodoroConfigDTO?) -> Void)? = nil
    var onStop: (() -> Void)? = nil

    // MARK: - Estado
    @State private var selectedConfigId: UUID? = nil
    @State private var isStartingFreeMode = false

    // Selección por arrastre (iOS)
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var hoveredPresetId: UUID? = nil

    // Foco y teclado
    @State private var activeZone: SavedPresetsFocus = .presetList
    @FocusState private var isViewFocused: Bool

    // Búsqueda
    @State private var isSearchActive: Bool = false
    @State private var searchQuery: String = ""

    // Overlays
    @State private var showStats = false
    @State private var showTimerInProgress = false
    @State private var showSyncSettings = false
    @State private var showUnlinkConfirm = false

    // Preset pendiente de arrancar
    @State private var configToStart: PomodoroConfigDTO? = nil

    @FocusState private var isSearchFocused: Bool

    // MARK: - Paleta de Colores
    let workBackground = Color(red: 0.11, green: 0.12, blue: 0.13)
    let workAccent = Color(red: 0.95, green: 0.77, blue: 0.62)
    let textDimmedWork = Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.4)
    let destructiveRed = Color(red: 0.90, green: 0.30, blue: 0.30)

    // MARK: - Iconos según plataforma
    private var returnArrowIcon: String {
        #if os(macOS)
        return "arrowtriangle.down.fill"
        #else
        return "arrowtriangle.right.fill"
        #endif
    }

    private var backIconName: String {
        #if os(macOS)
        return "chevron.up"
        #else
        return "chevron.left"
        #endif
    }

    private var forwardIconName: String {
        #if os(macOS)
        return "chevron.down"
        #else
        return "chevron.right"
        #endif
    }

    // MARK: - Datos derivados
    var filteredConfigs: [PomodoroConfigDTO] {
        if searchQuery.isEmpty {
            return presetsVM.savedConfigs
        } else {
            return presetsVM.savedConfigs.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            navigationKeyShortcuts
            backgroundLayer
            mainContent
        }
        .overlay { timerInProgressOverlay }
        .overlay { syncSettingsOverlay }
        .overlay { unlinkOverlay }
        .overlay(alignment: .bottomTrailing) { freeModeButtonOverlay }
        .overlay { statsOverlay }
        .overlay(alignment: .bottomLeading) {
            #if os(macOS)
            macCollectionButton
            #endif
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showTimerInProgress)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showSyncSettings)
        .animation(HIGMotion.overlay, value: showUnlinkConfirm)
        .onAppear(perform: handleOnAppear)
        .onChange(of: selectedConfigId) { _, newValue in
            handleSelectedConfigChange(newValue)
        }
        #if os(macOS)
        .scrollWheelBack {
            onNavigate?(.mainTimer, nil)
        }
        #endif
        .gesture(navigationDragGesture)
        #if os(macOS)
        .focusable()
        .focused($isViewFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
        #endif
    }

    // MARK: - Sub-secciones del body

    @ViewBuilder
    private var navigationKeyShortcuts: some View {
        Group {
            Button("") { onNavigate?(.mainTimer, nil) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("") { onNavigate?(.mainTimer, nil) }
                .keyboardShortcut(.upArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private var backgroundLayer: some View {
        workBackground
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: handleBackgroundTap)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            customNavigationBar
                .padding(.top, 30)
                .padding(.horizontal, 40)
                .frame(maxWidth: 600)

            if case .connected(_, let role, let peerName) = timerVM.syncState {
                Button {
                    Haptics.impact(.light, intensity: 0.6)
                    withAnimation(HIGMotion.overlay) { showUnlinkConfirm = true }
                } label: {
                    connectedBadge(peerName: peerName, role: role)
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Linked to \(peerName). Tap to unlink.")
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isSearchActive {
                searchBar
                    .padding(.horizontal, 40)
                    .padding(.top, 14)
                    .frame(maxWidth: 600)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 20)

            presetCardsSection

            Spacer(minLength: 20)

            playControls
                .padding(.bottom, 50)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isTimerActive)
        }
    }

    // MARK: - Preset cards
    @ViewBuilder
    private var presetCardsSection: some View {
        #if os(macOS)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(filteredConfigs) { config in
                    presetCard(for: config)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: 160)
        #else
        compactPresetList
        #endif
    }

    #if os(iOS)
    private var compactPresetList: some View {
        let isCompactList = filteredConfigs.count <= 5
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                ForEach(filteredConfigs) { config in
                    presetCard(for: config)
                }
            }
            .padding(.horizontal, 30)
            .coordinateSpace(name: "presetsContainer")
            .onPreferenceChange(CardFramePreferenceKey.self) { frames in
                cardFrames = frames
            }
            .modifier(CompactDragSelectModifier(
                enabled: isCompactList,
                onChanged: { location in updateHoveredPreset(at: location) },
                onEnded: { value in finishPresetDrag(value: value) }
            ))
        }
        .frame(maxWidth: 400)
        .scrollDisabled(isCompactList)
    }
    #endif

    // MARK: - Overlays

    @ViewBuilder
    private var timerInProgressOverlay: some View {
        if showTimerInProgress {
            TimerInProgressPopup(
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                backgroundColor: workBackground,
                title: {
                    if timerVM.isMirror { return "MIRROR MODE ACTIVE" }
                    if isStartingFreeMode { return "TIMER IN PROGRESS" }
                    if freeModeVM.isRunning { return "FREE MODE ACTIVE" }
                    return "TIMER IN PROGRESS"
                }(),
                message: {
                    if timerVM.isMirror { return "You are currently mirroring another device.\nStarting a new session will unlink you from that device." }
                    if isStartingFreeMode { return "You already have a session running.\nStarting Free Mode will discard the current progress." }
                    if freeModeVM.isRunning { return "You are currently in Free Mode.\nStarting a new preset will finish your free session." }
                    return "You already have a session running.\nStarting a new one will discard the current progress."
                }(),
                confirmLabel: {
                    if timerVM.isMirror { return "UNLINK & START" }
                    if isStartingFreeMode { return "START FREE MODE" }
                    if freeModeVM.isRunning { return "START PRESET" }
                    return "START NEW"
                }(),
                iconName: {
                    if timerVM.isMirror { return "rectangle.connected.to.line.below" }
                    if isStartingFreeMode { return "exclamationmark.triangle.fill" }
                    if freeModeVM.isRunning { return "infinity" }
                    return "exclamationmark.triangle.fill"
                }(),
                onCancel: {
                    configToStart = nil
                    isStartingFreeMode = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showTimerInProgress = false
                    }
                },
                onStartNew: {
                    if isStartingFreeMode {
                        timerVM.userStopAndReset()
                        isStartingFreeMode = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showTimerInProgress = false
                        }
                        onNavigate?(.freeMode, nil)
                    } else if let config = configToStart {
                        if timerVM.isMirror {
                            timerVM.userStartNewSession(with: config)
                        } else if freeModeVM.isRunning {
                            freeModeVM.finishSession()
                            onNavigate?(.mainTimer, config)
                        } else {
                            onNavigate?(.mainTimer, config)
                        }
                        configToStart = nil
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showTimerInProgress = false
                        }
                    }
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var syncSettingsOverlay: some View {
        if showSyncSettings {
            SyncSettingsPopup(
                timerVM: timerVM,
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                backgroundColor: workBackground,
                onDismiss: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showSyncSettings = false
                    }
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var unlinkOverlay: some View {
        if showUnlinkConfirm {
            let name: String = {
                if case .connected(_, _, let peerName) = timerVM.syncState { return peerName }
                return "the other device"
            }()

            TimerInProgressPopup(
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                backgroundColor: workBackground,
                title: "UNLINK DEVICE",
                message: "You'll stop syncing with \(name).\nYou can link them again from Sync settings.",
                confirmLabel: "UNLINK",
                iconName: "link",
                onCancel: {
                    withAnimation(HIGMotion.overlay) { showUnlinkConfirm = false }
                },
                onStartNew: {
                    withAnimation(HIGMotion.overlay) { showUnlinkConfirm = false }
                    Task { await timerVM.disableSync() }
                }
            )
            .transition(.higPopup)
        }
    }

    @ViewBuilder
    private var statsOverlay: some View {
        if showStats {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) { showStats = false }
                    }

                PomodoroStatsView(
                    state: statsViewState,
                    accentColor: workAccent,
                    dimmedColor: textDimmedWork,
                    backgroundColor: workBackground,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.25)) { showStats = false }
                    }
                )
                .frame(maxWidth: 420, maxHeight: 560)
                .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 12)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
    }

    private var statsViewState: PomodoroStatsViewState {
        PomodoroStatsViewState(
            bronze: SessionStore.shared.wallet.bronze,
            silver: SessionStore.shared.wallet.silver,
            gold: SessionStore.shared.wallet.gold,
            currentStreak: SessionStore.shared.currentStreak,
            isSilverUnlocked: SessionStore.shared.wallet.isUnlocked(.silver),
            recordsForDate: { day in SessionStore.shared.records(on: day) },
            goalForDate: { day in SessionStore.shared.goal(on: day) },
            onSaveGoal: { day, text in SessionStore.shared.setGoalText(for: day, text: text) },
            onToggleGoal: { day in SessionStore.shared.toggleGoalCompletion(on: day) },
            isGoldUnlocked: SessionStore.shared.wallet.isUnlocked(.gold),
            // ▼ focusTimeForGoal va JUSTO ACÁ, antes de focusMinutesForDate ▼
            focusTimeForGoal: { goal in
                let cal = Calendar.current
                let start = cal.startOfDay(for: goal.createdAt)
                let end = cal.startOfDay(for: goal.dayStart)
                return SessionStore.shared.records
                    .filter { $0.dayStart >= start && $0.dayStart <= end && $0.qualifiesForChips }
                    .reduce(0) { $0 + $1.focusMinutes }
            },
            focusMinutesForDate: { SessionStore.shared.totalFocusMinutes(on: $0) },
            hasAnyRecordForDate: { SessionStore.shared.hasAnyRecord(on: $0) },
            tierForDate: { day, thresholds in
                guard SessionStore.shared.hasAnyRecord(on: day) else { return .empty }
                let score = SessionStore.shared.calendarScore(on: day)
                return CalendarColorCalculator.tier(for: score, thresholds: thresholds)
            },
            recentScoresForThresholds: {
                SessionStore.shared.recentCalendarScores(days: CalendarColorCalculator.windowDays)
            },
            onShowOwnedItems: {
                showStats = false
                onNavigate?(.ownedItems, nil)
            },
            allGoals: { SessionStore.shared.dailyGoals }
        )
    }
    
    
    // MARK: - Handlers

    private func handleOnAppear() {
        if let forced = pendingSelectionId {
            selectedConfigId = forced
            DispatchQueue.main.async {
                pendingSelectionId = nil
            }
        }

        if isTimerActive, let activeId = activeConfigId {
            selectedConfigId = activeId
        } else if let stored = UserDefaults.standard.string(forKey: Self.selectedPresetKey),
                  let storedUUID = UUID(uuidString: stored),
                  presetsVM.savedConfigs.contains(where: { $0.id == storedUUID }) {
            selectedConfigId = storedUUID
        } else if selectedConfigId == nil {
            selectedConfigId = presetsVM.savedConfigs.first?.id
        }

        activeZone = .presetList

        #if os(macOS)
        DispatchQueue.main.async {
            isViewFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isViewFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isViewFocused = true
        }
        #endif
    }

    private func handleSelectedConfigChange(_ newValue: UUID?) {
        if let id = newValue {
            UserDefaults.standard.set(id.uuidString, forKey: Self.selectedPresetKey)
        }
    }

    private var navigationDragGesture: some Gesture {
        DragGesture()
            .onEnded { value in
                let translation = value.translation
                #if os(macOS)
                if translation.width < -40 && abs(translation.width) > abs(translation.height) {
                    attemptStartFreeMode()
                } else if abs(translation.height) > 40 {
                    onNavigate?(.mainTimer, nil)
                }
                #else
                if translation.height > 40 && abs(translation.height) > abs(translation.width) {
                    attemptStartFreeMode()
                } else if abs(translation.width) > 40 {
                    onNavigate?(.mainTimer, nil)
                }
                #endif
            }
    }

    @ViewBuilder
    private var freeModeButtonOverlay: some View {
        #if os(iOS)
        NeonFreeModeButton(direction: .down) {
            attemptStartFreeMode()
        }
        .padding(.trailing, 10)
        .padding(.bottom, 8)
        #else
        NeonFreeModeButton(direction: .right) {
            attemptStartFreeMode()
        }
        .padding(.trailing, 24)
        .padding(.bottom, 50)
        #endif
    }

    // MARK: - Indicador de dispositivo vinculado

    @ViewBuilder
    private func connectedBadge(peerName: String, role: LocalSyncRole) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.6), radius: 3)

            Text("LINKED TO \(peerName.uppercased())")
                .font(.system(size: 9, weight: .heavy))
                .tracking(2)
                .foregroundColor(workAccent.opacity(0.8))

            Text("·")
                .font(.system(size: 9))
                .foregroundColor(textDimmedWork.opacity(0.5))

            Text(role == .master ? "MASTER" : "MIRROR")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(workAccent.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.green.opacity(0.08)))
        .overlay(Capsule().stroke(Color.green.opacity(0.25), lineWidth: 0.5))
        .animation(.spring(response: 0.35, dampingFraction: 0.85),
                   value: timerVM.syncState.isConnected)
    }

    // MARK: - Tarjeta de preset

    private func presetCard(for config: PomodoroConfigDTO) -> some View {
        PresetCardView(
            config: config,
            isSelected: selectedConfigId == config.id && activeZone == .presetList,
            accentColor: workAccent,
            dimmedColor: textDimmedWork,
            destructiveColor: destructiveRed,
            onSelect: { selectedConfigId = config.id },
            onEdit: { editConfig(config) },
            onDelete: { deleteConfig(config) }
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CardFramePreferenceKey.self,
                    value: [config.id: geo.frame(in: .named("presetsContainer"))]
                )
            }
        )
    }

    // MARK: - Selección por arrastre (iOS)

    private func updateHoveredPreset(at point: CGPoint) {
        for (id, frame) in cardFrames where frame.contains(point) {
            if hoveredPresetId != id {
                hoveredPresetId = id
                if selectedConfigId != id {
                    selectedConfigId = id
                    Haptics.selection()
                }
            }
            return
        }
    }

    private func finishPresetDrag(value: DragGesture.Value) {
        let isTap = abs(value.translation.width) < 3 && abs(value.translation.height) < 3
        let isHorizontalSwipe = abs(value.translation.width) > abs(value.translation.height)
            && abs(value.translation.width) > 40

        if isHorizontalSwipe {
            onNavigate?(.mainTimer, nil)
        } else if isTap {
            let hitCard = cardFrames.values.contains { $0.contains(value.location) }
            if !hitCard {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedConfigId = nil
                }
            }
        }
        hoveredPresetId = nil
    }

    // MARK: - Acciones de teclado

    private func cycleFocus(forward: Bool) {
        activeZone = SavedPresetsKeyboard.cycle(from: activeZone, forward: forward)
    }

    private func handleEnterOnActiveZone() {
        switch SavedPresetsKeyboard.enterAction(for: activeZone) {
        case .toggleSearch:
            toggleSearch()
        case .showStats:
            withAnimation(.easeInOut(duration: 0.25)) { showStats = true }
        case .showSync:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                showSyncSettings = true
            }
            Haptics.impact(.light, intensity: 0.6)
        case .showShop:
            if shopIsAvailable {
                onNavigate?(.shop, nil)
            }
        case .startFreeMode:
            attemptStartFreeMode()
        case .newPreset:
            requestNewPreset()
        case .startSelectedPreset:
            executeAndNavigate()
        }
    }

    private func handleSpaceOnActiveZone() {
        switch SavedPresetsKeyboard.spaceAction(
            isTimerActive: isTimerActive,
            focusedZone: activeZone
        ) {
        case .toggleTimer:
            timerVM.userToggleTimer()
        case .startSelectedPreset:
            executeAndNavigate()
        case .none:
            break
        }
    }

    #if os(macOS)
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if showStats || showSyncSettings || showTimerInProgress || showUnlinkConfirm || isSearchFocused {
            return .ignored
        }

        let hasMods = press.modifiers.contains(.command)
            || press.modifiers.contains(.option)
            || press.modifiers.contains(.control)

        if press.key == .tab {
            let forward = !press.modifiers.contains(.shift)
            activeZone = SavedPresetsKeyboard.cycle(from: activeZone, forward: forward)
            return .handled
        }

        guard !hasMods else { return .ignored }

        switch press.key {
        case .return:
            handleEnterOnActiveZone()
            return .handled
        case .space:
            handleSpaceOnActiveZone()
            return .handled
        case .leftArrow:
            movePresetSelection(by: -1)
            activeZone = .presetList
            return .handled
        case .rightArrow:
            movePresetSelection(by: 1)
            activeZone = .presetList
            return .handled
        default:
            return .ignored
        }
    }
    #endif

    private func movePresetSelection(by offset: Int) {
        let configs = filteredConfigs
        guard !configs.isEmpty else { return }

        let currentIdx: Int? = selectedConfigId.flatMap { id in
            configs.firstIndex(where: { $0.id == id })
        }

        guard let nextIdx = SavedPresetsKeyboard.movePresetIndex(
            currentIndex: currentIdx,
            count: configs.count,
            offset: offset
        ) else { return }

        selectedConfigId = configs[nextIdx].id
    }

    // MARK: - Controles Play / Stop / Retorno

    private var playControls: some View {
        ZStack {
            Button(action: executeAndNavigate) {
                Image(systemName: "play.fill")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(workBackground)
                    .frame(width: 80, height: 80)
                    .background(workAccent)
                    .clipShape(Circle())
                    .shadow(color: workAccent.opacity(0.25), radius: 15, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .opacity(presetsVM.savedConfigs.isEmpty ? 0.5 : 1.0)
            .disabled(presetsVM.savedConfigs.isEmpty || showStats || showSyncSettings || showTimerInProgress || showUnlinkConfirm)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityLabel("Start selected preset")

            if isTimerActive {
                Button(action: { onStop?() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(workAccent)
                        .frame(width: 44, height: 44)
                        .background(workBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(workAccent.opacity(0.3), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .offset(x: -80)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Stop timer")
            }

            if isTimerActive {
                Button(action: { onNavigate?(.mainTimer, nil) }) {
                    Image(systemName: returnArrowIcon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(workAccent)
                        .frame(width: 44, height: 44)
                        .background(workBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(workAccent.opacity(0.3), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .offset(x: 80)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Back to timer")
            }
        }
    }

    // MARK: - Control de Foco

    private func handleBackgroundTap() {
        isSearchFocused = false
        if searchQuery.isEmpty && isSearchActive {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchActive = false
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedConfigId = nil
        }
    }

    // MARK: - Navbar

    private var customNavigationBar: some View {
        #if os(iOS)
        HStack(spacing: 12) {
            Text("SAVED PRESETS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.5)
                .foregroundColor(textDimmedWork)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(0)

            Spacer(minLength: 6)

            HStack(spacing: 2) {
                navbarButton(
                    systemName: "magnifyingglass", zone: .navSearch,
                    isActive: isSearchActive, action: toggleSearch,
                    label: "Search presets"
                )
                navbarButton(
                    systemName: "calendar", zone: .navStats,
                    isActive: false,
                    action: { withAnimation(.easeInOut(duration: 0.25)) { showStats = true } },
                    label: "Statistics"
                )
                navbarButton(
                    systemName: "gearshape", zone: .navSync,
                    isActive: showSyncSettings,
                    action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            showSyncSettings = true
                        }
                        Haptics.impact(.light, intensity: 0.6)
                    },
                    label: "Sync settings"
                )
                navbarButton(
                    systemName: "plus", zone: .navPlus,
                    isActive: false, action: requestNewPreset,
                    label: "New preset"
                )
                if shopIsAvailable {
                    navbarButton(
                        systemName: "bag",
                        zone: .navShop,
                        isActive: false,
                        action: { onNavigate?(.shop, nil) },
                        label: "Shop"
                    )
                }
            }
            .layoutPriority(1)
        }
        #else
        HStack(alignment: .center) {
            HStack {
                Button { } label: {
                    Image(systemName: backIconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(textDimmedWork)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .hidden()
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("SAVED PRESETS")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .tracking(4)
                .foregroundColor(textDimmedWork)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            HStack(spacing: 12) {
                Spacer()
                navbarButton(
                    systemName: "magnifyingglass", zone: .navSearch,
                    isActive: isSearchActive, action: toggleSearch,
                    label: "Search presets"
                )
                navbarButton(
                    systemName: "calendar", zone: .navStats,
                    isActive: false,
                    action: { withAnimation(.easeInOut(duration: 0.25)) { showStats = true } },
                    label: "Statistics"
                )
                navbarButton(
                    systemName: "gearshape", zone: .navSync,
                    isActive: showSyncSettings,
                    action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            showSyncSettings = true
                        }
                    },
                    label: "Sync settings"
                )
                navbarButton(
                    systemName: "plus", zone: .navPlus,
                    isActive: false, action: requestNewPreset,
                    label: "New preset"
                )
                if shopIsAvailable {
                    navbarButton(
                        systemName: "bag",
                        zone: .navShop,
                        isActive: false,
                        action: { onNavigate?(.shop, nil) },
                        label: "Shop"
                    )
                }
                Button { } label: {
                    Image(systemName: forwardIconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(textDimmedWork)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hidden()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        #endif
    }
    
    @AppStorage("shop.debug.hideLockedContent") private var hideLockedContent: Bool = true

    private var shopIsAvailable: Bool {
        if !hideLockedContent { return true }
        return SessionStore.shared.wallet.hasEverReceivedCurrency
    }

    @ViewBuilder
    private func navbarButton(
        systemName: String,
        zone: SavedPresetsFocus,
        isActive: Bool,
        action: @escaping () -> Void,
        label: String
    ) -> some View {
        let isFocused = activeZone == zone

        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive || isFocused ? workAccent : textDimmedWork)
                .frame(width: 24, height: 24)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isFocused ? workAccent : Color.clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var searchBar: some View {
        HStack {
            TextField("Search preset...", text: $searchQuery)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .tint(workAccent)
                .autocorrectionDisabled(true)
                .focused($isSearchFocused)
                .textFieldStyle(.plain)

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(textDimmedWork)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Despachador de navegación

    private func executeAndNavigate() {
        guard !showTimerInProgress else { return }

        let resolved: PomodoroConfigDTO?
        if let id = selectedConfigId,
           let found = presetsVM.savedConfigs.first(where: { $0.id == id }) {
            resolved = found
        } else if let stored = UserDefaults.standard.string(forKey: Self.selectedPresetKey),
                  let storedUUID = UUID(uuidString: stored),
                  let found = presetsVM.savedConfigs.first(where: { $0.id == storedUUID }) {
            resolved = found
            selectedConfigId = storedUUID
        } else if let first = presetsVM.savedConfigs.first {
            resolved = first
            selectedConfigId = first.id
        } else {
            resolved = nil
        }

        guard let config = resolved else { return }

        if timerVM.isMirror || isTimerActive || freeModeVM.isRunning {
            isStartingFreeMode = false
            configToStart = config
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showTimerInProgress = true
            }
        } else {
            onNavigate?(.mainTimer, config)
        }
    }

    private func attemptStartFreeMode() {
        if isTimerActive {
            isStartingFreeMode = true
            configToStart = nil
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showTimerInProgress = true
            }
        } else {
            onNavigate?(.freeMode, nil)
        }
    }

    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.2)) { isSearchActive.toggle() }
        if isSearchActive {
            isSearchFocused = true
        } else {
            searchQuery = ""
            isSearchFocused = false
        }
    }

    private func requestNewPreset() {
        onNavigate?(.timerSetup, nil)
    }

    private func editConfig(_ config: PomodoroConfigDTO) {
        onNavigate?(.timerSetup, config)
    }

    private func deleteConfig(_ config: PomodoroConfigDTO) {
        withAnimation(.easeInOut(duration: 0.3)) {
            presetsVM.deletePreset(id: config.id)
            if selectedConfigId == config.id {
                selectedConfigId = presetsVM.savedConfigs.first?.id
            }
        }
    }
    
    // MARK: - Botón de Colección (macOS)
    @ViewBuilder
    private var macCollectionButton: some View {
        // Solo lo mostramos si el usuario tiene algún item comprado
        if !SessionStore.shared.wallet.purchasedItemIds.isEmpty {
            Button {
                Haptics.impact(.light, intensity: 0.6)
                onNavigate?(.ownedItems, nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("MY COLLECTION")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                }
                .foregroundColor(CurrencyTier.gold.tintColor)
                .padding(.horizontal, 14)
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
            .padding(.leading, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Tarjeta Reutilizable

struct PresetCardView: View {
    var config: PomodoroConfigDTO
    var isSelected: Bool
    var accentColor: Color
    var dimmedColor: Color
    var destructiveColor: Color
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(config.name)
                    .font(.system(size: 13, weight: .bold, design: .default))
                    .tracking(1.5)
                    .foregroundColor(isSelected ? accentColor : dimmedColor)

                HStack(spacing: 10) {
                    Text("\(config.focus)/\(config.breakTime) MIN")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .monospacedDigit()
                    Text("•").font(.system(size: 10))
                    Text("\(config.sessions) SESSIONS")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                }
                .foregroundColor(isSelected ? accentColor.opacity(0.8) : dimmedColor.opacity(0.6))

                Text("\(decodeNoise(config.audio.noiseId)) • \(decodeFreq(config.audio.freqId))")
                    .font(.system(size: 9, weight: .medium, design: .default))
                    .tracking(1)
                    .foregroundColor(dimmedColor.opacity(0.5))
                    .padding(.top, 2)
            }

            Spacer(minLength: 10)

            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? accentColor : dimmedColor.opacity(0.5))
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit preset")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected
                                         ? destructiveColor.opacity(0.8)
                                         : dimmedColor.opacity(0.3))
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete preset")
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? accentColor.opacity(0.04) : Color.clear)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accentColor : dimmedColor.opacity(0.15), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .frame(width: 250)
    }

    private func decodeNoise(_ id: Int) -> String {
        AmbientSound.from(id: id).displayName
    }

    private func decodeFreq(_ id: Int) -> String {
        switch id {
        case 1: return "40 HZ"
        case 2: return "15 HZ"
        case 3: return "10 HZ"
        case 4: return "6 HZ"
        default: return "NO WAVES"
        }
    }
}

// MARK: - Preview

struct SavedPresetsView_Previews: PreviewProvider {
    static var previews: some View {
        SavedPresetsView(
            presetsVM: PresetsViewModel(repository: UserDefaultsPomodoroRepository()),
            timerVM: TimerViewModel(),
            freeModeVM: FreeModeViewModel(),
            isTimerActive: true,
            activeConfigId: nil,
            pendingSelectionId: .constant(nil),
            onNavigate: { destination, payload in
                let payloadInfo = payload?.name ?? "Ninguno"
                print("Preview navegando a \(destination) con Payload:\n\(payloadInfo)")
            },
            onStop: {
                print("Preview: stop presionado")
            }
        )
        .frame(width: 400, height: 800)
    }
}

// MARK: - PreferenceKey para frames de presets

private struct CardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct CompactDragSelectModifier: ViewModifier {
    let enabled: Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: (DragGesture.Value) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("presetsContainer"))
                    .onChanged { value in onChanged(value.location) }
                    .onEnded { value in onEnded(value) }
            )
        } else {
            content
        }
    }
}
