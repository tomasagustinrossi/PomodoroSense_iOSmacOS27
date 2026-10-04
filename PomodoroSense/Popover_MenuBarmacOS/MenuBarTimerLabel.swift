//
//  MenuBarTimerView.swift
//  PomodoroSense
//
//  Contenido del popover del status item de macOS.
//  Ultra minimalista.
//

#if os(macOS)
import SwiftUI
import AppKit

struct MenuBarTimerView: View {
    @ObservedObject var timerVM: TimerViewModel
    @ObservedObject var presetsVM: PresetsViewModel

    /// Cantidad de presets a partir de la cual se muestra la lupa.
    private static let searchThreshold = 5

    @State private var isSearchActive: Bool = false
    @State private var searchQuery: String = ""

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
        if searchQuery.isEmpty {
            return presetsVM.savedConfigs
        }
        let q = searchQuery.lowercased()
        return presetsVM.savedConfigs.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if timerVM.isActive {
                activeContent
            } else {
                idleContent
            }
            Divider().background(Color.white.opacity(0.06))
            footer
        }
        .frame(width: 260)
        .background(background)
    }

    // MARK: - Estado activo

    private var activeContent: some View {
        VStack(spacing: 10) {
            // Header con fase + STOP en dos estados
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
            .animation(.spring(response: 0.35, dampingFraction: 0.75),
                       value: timerVM.isRunning)

            // Timer central + flechas
            HStack(spacing: 14) {
                invisibleArrow(system: "backward.end.fill", action: { timerVM.userSkipPrevious() })

                VStack(spacing: 2) {
                    Text(timerVM.timeRemainingString)
                        .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(timerVM.isRunning ? .white : .gray)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.9),
                                   value: timerVM.timeRemainingString)
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

                invisibleArrow(system: "forward.end.fill", action: { timerVM.userSkipNext() })
            }
            .padding(.bottom, 4)

            // Preset (una sola línea, muy tenue)
            Text(timerVM.activeConfig.name.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(dimmed.opacity(0.5))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }
    
    // MARK: - STOP (dos estados animados)

    /// STOP en dos formas:
    /// - Corriendo: puntito mínimo y discreto.
    /// - Pausado: pastilla roja con la palabra "STOP" y un ícono.
    ///
    /// La transición usa spring suave para sentirse "Apple".
    @ViewBuilder
    private var stopButton: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                timerVM.userStopAndReset()
            }
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
    }


    // MARK: - Estado idle

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header con título + lupa (si aplica)
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
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, isSearchActive ? 4 : 2)

            // Campo de búsqueda
            if isSearchActive {
                HStack(spacing: 6) {
                    TextField("Search…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }

            // Lista de presets
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
                                    ForEach(filteredPresets) { config in
                                        presetRow(config)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.bottom, 6)
                            }
                            .frame(maxHeight: 160)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            footerButton(title: "OPEN APP", systemName: "macwindow", action: openApp)
            Spacer()
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

    // MARK: - Flecha invisible

    private func invisibleArrow(system: String, action: @escaping () -> Void) -> some View {
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
    }

    // MARK: - Acciones

    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isSearchActive.toggle()
            if !isSearchActive {
                searchQuery = ""
            }
        }
    }

    private func startPreset(_ config: PomodoroConfigDTO) {
        timerVM.loadConfiguration(config, autoStart: true)
        timerVM.wantsToNavigateToTimer = true
        openApp()
    }

    private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }
}


/// Estilo de botón para las flechas: escala leve al presionar.
private struct ArrowPressStyle: ButtonStyle {
    let dimmed: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1.0)
            .foregroundColor(configuration.isPressed ? dimmed.opacity(0.9) : nil)
            .animation(.spring(response: 0.2, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

#endif
