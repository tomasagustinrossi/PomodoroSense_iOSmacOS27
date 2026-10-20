//
//  MenuBarTimerView.swift
//  PomodoroSense
//

#if os(macOS)
import SwiftUI
import AppKit

struct MenuBarTimerView: View {
    @ObservedObject var timerVM: TimerViewModel
    @ObservedObject var presetsVM: PresetsViewModel
    @ObservedObject var freeModeVM: FreeModeViewModel
    
    @State private var isFreeModeActive = false

    var onDismiss: ((_ completion: @escaping () -> Void) -> Void)? = nil

    private static let contentTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.22)),
        removal: .identity
    )

    private static let searchThreshold = 5

    @State private var isSearchActive: Bool = false
    @State private var searchQuery: String = ""
    @State private var hoveredPresetID: PomodoroConfigDTO.ID?
    @FocusState private var searchFocused: Bool
    @State private var rowsAppeared: Bool = true

    private var theme: PomodoroTheme { timerVM.currentTheme }
    private var activeColor: Color {
        timerVM.isBreak ? theme.breakAccent : theme.workAccent
    }
    private var background: Color {
        timerVM.isBreak ? theme.breakBackground : theme.workBackground
    }
    private var dimmed: Color {
        timerVM.isBreak ? theme.textDimmedBreak : theme.textDimmedWork
    }

    private var filteredPresets: [PomodoroConfigDTO] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return presetsVM.savedConfigs
        }
        return presetsVM.savedConfigs.filter { $0.name.localizedStandardContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isFreeModeActive {
                MenuBarFreeModeView(
                    viewModel: freeModeVM,
                    accentColor: freeModeVM.currentTheme.workAccent,
                    dimmedColor: freeModeVM.currentTheme.textDimmedWork,
                    backgroundColor: freeModeVM.currentTheme.workBackground,
                    onStop: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isFreeModeActive = false
                        }
                    }
                )
                .transition(Self.contentTransition)
            } else if timerVM.isActive {
                activeContent
                    .transition(Self.contentTransition)
            } else {
                idleContent
                    .transition(Self.contentTransition)
                    .onAppear { replayRowsEntrance() }
            }
            
            Divider().background(Color.white.opacity(0.06))
            footer
        }
        .frame(width: 260)
        .background(background.animation(.easeInOut(duration: 0.35), value: isFreeModeActive ? false : timerVM.isBreak))
        .onReceive(NotificationCenter.default.publisher(for: .statusBarPopoverWillShow)) { _ in
            replayRowsEntrance()
        }
        .onChange(of: presetsVM.savedConfigs.count) { _, newCount in
            if newCount <= Self.searchThreshold { resetSearch() }
        }
        .onChange(of: timerVM.isActive) { _, active in
            if active { resetSearch() }
        }
    }

    // MARK: - Estado activo
    private var activeContent: some View {
        VStack(spacing: 10) {
            HStack {
                Text(timerVM.isBreak ? "BREAK" : "FOCUS")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(activeColor)
                    .contentTransition(.opacity)

                Spacer()

                stopButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: timerVM.isRunning)

            HStack(spacing: 14) {
                invisibleArrow(
                    system: "backward.end.fill",
                    label: "Previous session",
                    action: { timerVM.userSkipPrevious() }
                )

                VStack(spacing: 2) {
                    Text(timerVM.timeRemainingString)
                        .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(timerVM.isRunning ? .white : .gray)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: timerVM.timeRemainingString)
                        .animation(.easeInOut(duration: 0.25), value: timerVM.isRunning)

                    Text("\(timerVM.currentSession) OF \(timerVM.totalSessions)")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1.5)
                        .foregroundColor(dimmed.opacity(0.7))
                        .contentTransition(.numericText())
                }
                .frame(minWidth: 120)
                .contentShape(Rectangle())
                .onTapGesture { timerVM.userToggleTimer() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(timerVM.isRunning ? "Pause timer" : "Resume timer")

                invisibleArrow(
                    system: "forward.end.fill",
                    label: "Next session",
                    action: { timerVM.userSkipNext() }
                )
            }
            .padding(.bottom, 4)

            Text(timerVM.activeConfig.name.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(dimmed.opacity(0.5))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var stopButton: some View {
        Button(action: {
            timerVM.userStopAndReset()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8, weight: .black))

                if !timerVM.isRunning {
                    Text("STOP")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.5)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.7, anchor: .trailing))
                                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.05)),
                                removal: .opacity.combined(with: .scale(scale: 0.5, anchor: .trailing))
                                    .animation(.easeOut(duration: 0.15))
                            )
                        )
                }
            }
            .foregroundColor(timerVM.isRunning ? dimmed.opacity(0.35) : .white)
            .padding(.horizontal, timerVM.isRunning ? 5 : 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        timerVM.isRunning
                            ? Color.white.opacity(0.04)
                            : Color.red.opacity(0.75)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        timerVM.isRunning
                            ? Color.white.opacity(0.06)
                            : Color.red.opacity(0.9),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: timerVM.isRunning ? .clear : Color.red.opacity(0.35),
                radius: 4, x: 0, y: 1
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(timerVM.isRunning ? "Stop session" : "Stop")
        .accessibilityLabel("Stop session")
    }

    // MARK: - Estado idle
    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("START A SESSION")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(dimmed)

                Spacer()

                if presetsVM.savedConfigs.count > Self.searchThreshold {
                    Button(action: toggleSearch) {
                        Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isSearchActive ? activeColor : dimmed.opacity(0.6))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSearchActive ? "Close search" : "Search presets")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, isSearchActive ? 4 : 2)

            if isSearchActive {
                HStack(spacing: 6) {
                    TextField("Search…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .focused($searchFocused)
                        .onSubmit {
                            if let first = filteredPresets.first { startPreset(first) }
                        }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }

            if presetsVM.savedConfigs.isEmpty {
                Text("No presets saved.")
                    .font(.system(size: 11))
                    .foregroundColor(dimmed)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            } else if filteredPresets.isEmpty {
                Text("No matches.")
                    .font(.system(size: 11))
                    .foregroundColor(dimmed)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredPresets.enumerated()), id: \.element.id) { index, config in
                            presetRow(config)
                                .opacity(rowsAppeared ? 1 : 0)
                                .offset(y: rowsAppeared ? 0 : 6)
                                .animation(
                                    .spring(response: 0.4, dampingFraction: 0.78)
                                        .delay(Double(min(index, 8)) * 0.03),
                                    value: rowsAppeared
                                )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: 160)
                .scrollBounceBehavior(.always)
            }
        }
    }

    private func presetRow(_ config: PomodoroConfigDTO) -> some View {
        Button(action: { startPreset(config) }) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(activeColor)
                    .frame(width: 12)

                VStack(alignment: .leading, spacing: 0) {
                    Text(config.name.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("\(config.focus) / \(config.breakTime) MIN")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(dimmed.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(hoveredPresetID == config.id ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .onHover { inside in
            if inside {
                hoveredPresetID = config.id
            } else if hoveredPresetID == config.id {
                hoveredPresetID = nil
            }
        }
    }

    // MARK: - Footer
    private var footer: some View {
        HStack(spacing: 0) {
            footerButton(title: "OPEN APP", systemName: "macwindow", action: openApp)
            
            Spacer()
            
            // Botón de Infinito (solo visible si NO hay Pomodoro activo)
            if !timerVM.isActive && !isFreeModeActive {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isFreeModeActive.toggle()
                    }
                }) {
                    Image(systemName: "infinity")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(dimmed.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Free Mode")
                
                Spacer()
            }
            
            footerButton(title: "QUIT", systemName: "power", action: quitApp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func footerButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
            }
            .foregroundColor(dimmed.opacity(0.6))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Acciones
    private func invisibleArrow(system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(dimmed.opacity(0.55))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(ArrowPressStyle(dimmed: dimmed))
        .accessibilityLabel(label)
    }

    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isSearchActive.toggle()
            if !isSearchActive {
                searchQuery = ""
            }
        }

        if isSearchActive {
            Self.makePopoverPanelKey()
            Task { @MainActor in searchFocused = true }
        } else {
            searchFocused = false
        }
    }

    private func resetSearch() {
        guard isSearchActive || !searchQuery.isEmpty else { return }
        isSearchActive = false
        searchQuery = ""
        searchFocused = false
    }

    private static func makePopoverPanelKey() {
        NSApp.windows
            .first { $0 is NSPanel && $0.level == .popUpMenu && $0.canBecomeKey }?
            .makeKey()
    }

    private func startPreset(_ config: PomodoroConfigDTO) {
        // Frenar el Free Mode si estaba activo
        if freeModeVM.isRunning {
            freeModeVM.finishSession()
        }
        
        dismissThen {
            timerVM.loadConfiguration(config, autoStart: true)
            timerVM.wantsToNavigateToTimer = true
            activateApp()
        }
    }

    private func openApp() {
        dismissThen { activateApp() }
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        if let onDismiss {
            onDismiss(action)
        } else {
            action()
        }
    }

    private func activateApp() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func replayRowsEntrance() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { rowsAppeared = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            rowsAppeared = true
        }
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }
}

private struct ArrowPressStyle: ButtonStyle {
    let dimmed: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1.0)
            .foregroundColor(configuration.isPressed ? dimmed.opacity(0.9) : nil)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0, anchor: .center)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
#endif
