#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

enum AppScreen {
    case mainTimer
    case timerSetup
    case savedPresets
    case freeMode
    case shop
    case ownedItems
}

struct PomodoroMinimalistView: View {

    // MARK: - Inyección de dependencias
    /// TimerViewModel inyectado desde `PomodoroSenseApp`.
    @ObservedObject var timerViewModel: TimerViewModel

    /// PresetsViewModel inyectado desde `PomodoroSenseApp`.
    @ObservedObject var presetsVM: PresetsViewModel
    @ObservedObject var freeModeVM: FreeModeViewModel

    @Environment(\.scenePhase) var scenePhase

    @State private var configToEdit: PomodoroConfigDTO? = nil
    @State private var pendingSelectionId: UUID? = nil
    @State private var currentScreen: AppScreen = .savedPresets
    
    

    var body: some View {
        ZStack {
            switch currentScreen {
            case .mainTimer:
                MainTimerScreen(
                    timerVM: timerViewModel,
                    onNavigate: { screen in
                        withAnimation(HIGMotion.navigate) {
                            currentScreen = screen
                        }
                    },
                    onSavePreset: { config in
                        presetsVM.savePreset(config)
                    }
                )

            case .savedPresets:
                SavedPresetsView(
                    presetsVM: presetsVM,
                    timerVM: timerViewModel,
                    freeModeVM: freeModeVM, // <-- AGREGADO ACÁ
                    isTimerActive: timerViewModel.isActive,
                    activeConfigId: timerViewModel.activeConfig.id,
                    pendingSelectionId: $pendingSelectionId,
                    onNavigate: { destinationScreen, payload in
                        if destinationScreen == .timerSetup {
                            configToEdit = payload
                        }
                        if destinationScreen == .mainTimer, let config = payload {
                            timerViewModel.loadConfiguration(config, autoStart: true)
                        }
                        withAnimation(HIGMotion.navigate) {
                            currentScreen = destinationScreen
                        }
                    },
                    onStop: {
                        withAnimation(HIGMotion.state) {
                            timerViewModel.userStopAndReset()
                        }
                    }
                )
            case .freeMode:
                FreeModeView(
                    viewModel: freeModeVM,
                    onBack: {
                        withAnimation(HIGMotion.navigate) {
                            currentScreen = .savedPresets
                        }
                    }
                )
                
            case .shop:
                ShopView(
                    accentColor: Color(red: 0.95, green: 0.77, blue: 0.62),
                    dimmedColor: Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.4),
                    backgroundColor: Color(red: 0.11, green: 0.12, blue: 0.13),
                    onBack: {
                        withAnimation(HIGMotion.navigate) {
                            currentScreen = .savedPresets
                        }
                    }
                )

            case .ownedItems:
                OwnedItemsView(
                    dimmedColor: Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.4),
                    onBack: {
                        withAnimation(HIGMotion.navigate) {
                            currentScreen = .savedPresets
                        }
                    }
                )

            case .timerSetup:
                PomodoroSettingsView(
                    initialConfig: configToEdit,
                    onNavigate: { screen, _ in
                        withAnimation(HIGMotion.navigate) {
                            currentScreen = screen
                        }
                    },
                    onSave: { configuration in
                        presetsVM.savePreset(configuration)
                        UserDefaults.standard.set(configuration.id.uuidString,
                                                  forKey: "Selected_Preset_Id")
                        configToEdit = nil
                        pendingSelectionId = configuration.id
                        withAnimation(HIGMotion.navigate) {
                            currentScreen = .savedPresets
                        }
                    }
                )
            }

            // ─── Popup de reward: fuera del switch, dentro del ZStack ───
            if let reward = timerViewModel.sessionReward {
                SessionRewardPopup(
                    payload: reward,
                    accentColor: timerViewModel.currentTheme.workAccent,
                    dimmedColor: timerViewModel.currentTheme.textDimmedWork,
                    backgroundColor: timerViewModel.currentTheme.workBackground,
                    onDismiss: {
                        timerViewModel.dismissSessionReward()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .zIndex(100)
            }

            // ─── Toast mini al finalizar el preset completo ───
            if let summary = timerViewModel.sessionSummary {
                ZStack {
                    // Fondo invisible: capta taps FUERA del toast
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            timerViewModel.dismissSessionSummary()
                        }

                    VStack {
                        SessionSummaryToast(
                            chipsEarned: summary.chipsEarned,
                            newStreak: summary.newStreak,
                            accentColor: timerViewModel.currentTheme.workAccent,
                            dimmedColor: timerViewModel.currentTheme.textDimmedWork,
                            backgroundColor: timerViewModel.currentTheme.workBackground,
                            onDismiss: {
                                timerViewModel.dismissSessionSummary()
                            }
                        )
                        .padding(.top, 12)
                        .contentShape(Capsule())
                        .onTapGesture {
                            // Absorbe el tap: tocar el toast no lo cierra
                        }

                        Spacer()
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(99)
            }
        }
        .id(currentScreen)
        // En macOS, el mínimo debe cubrir el layout HStack de TimerSetup
        // (320 + 350 + spacings + padding ≈ 780). Sin esto, la ventana se
        // achica y corta los bloques.
        #if os(macOS)
        .frame(minWidth: 860, minHeight: 580)
        #else
        .frame(minWidth: 350, minHeight: 450)
        #endif
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                timerViewModel.sceneMovedToBackground()
            } else if newPhase == .active {
                // 1) Procesar comandos pendientes del widget (STOP, TOGGLE, SKIP).
                timerViewModel.handlePendingWidgetCommands()
                freeModeVM.handleWidgetCommand() // <-- AGREGAR ESTO

                // 2) Reconciliación de timer.
                timerViewModel.sceneMovedToForeground()
                freeModeVM.restartTickerIfNeeded()
            }
        }
        .task {
            await timerViewModel.restoreSyncIfNeeded()
        }
        .onChange(of: timerViewModel.wantsToNavigateToTimer) { _, newValue in
            guard newValue else { return }
            timerViewModel.wantsToNavigateToTimer = false
            guard currentScreen != .mainTimer else { return }
            withAnimation(HIGMotion.navigate) {
                currentScreen = .mainTimer
            }
        }
        .onChange(of: timerViewModel.wantsToNavigateToSavedPresets) { _, newValue in
            guard newValue else { return }
            timerViewModel.wantsToNavigateToSavedPresets = false
            guard currentScreen != .savedPresets else { return }
            withAnimation(HIGMotion.navigate) {
                currentScreen = .savedPresets
            }
        }
    }
}

// MARK: - Pantalla Principal
struct MainTimerScreen: View {
    @State private var showEqualizer: Bool = false

    /// `true` si hay cualquier popup/tooltip encima del timer.
    /// Se usa para desactivar gestos, teclado y scroll del fondo.
    private var isAnyPopupOpen: Bool {
        showEqualizer
            || timerVM.sessionReward != nil
            || timerVM.sessionSummary != nil
            || timerVM.tierUnlock != nil
    }

    #if os(macOS)
    /// Monitor local para interceptar Return de forma confiable.
    /// Los `.keyboardShortcut(.return)` en botones ocultos no se registran
    /// consistentemente cuando la vista vuelve al árbol (bug conocido de
    /// SwiftUI/AppKit). Este monitor garantiza el comportamiento.
    @State private var returnKeyMonitor: Any?
    #endif

    @ObservedObject var timerVM: TimerViewModel
    var onNavigate: ((AppScreen) -> Void)? = nil
    var onSavePreset: ((PomodoroConfigDTO) -> Void)? = nil

    // Alineación dinámica según el sistema
    #if os(macOS)
    private let returnAlignment: Alignment = .top
    private let returnIcon = "arrowtriangle.up.fill"
    #else
    private let returnAlignment: Alignment = .leading
    private let returnIcon = "arrowtriangle.left.fill"
    #endif

    // 1. DETECTOR INTELIGENTE DE ORIENTACIÓN
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var hClass
    @Environment(\.verticalSizeClass) var vClass
    private var isPortrait: Bool { hClass == .compact && vClass == .regular }
    #else
    private var isPortrait: Bool { false }
    #endif

    private var activeBackground: Color { timerVM.isBreak ? timerVM.currentTheme.breakBackground : timerVM.currentTheme.workBackground }
    private var activeAccent: Color { timerVM.isBreak ? timerVM.currentTheme.breakAccent : timerVM.currentTheme.workAccent }
    private var activeDimmed: Color { timerVM.isBreak ? timerVM.currentTheme.textDimmedBreak : timerVM.currentTheme.textDimmedWork }

    // ⚠️ FIX: convertido a MÉTODO para poder mutar `showEqualizer` (View es struct)
    @ViewBuilder
    private func equalizerOverlay() -> some View {
        ZStack {
            HIGScrim {
                onSavePreset?(timerVM.activeConfig)
                withAnimation(HIGMotion.overlay) { showEqualizer = false }
            }
            .transition(.opacity)

            EqualizerSheetView(
                initialNoiseId: timerVM.activeConfig.audio.noiseId,
                initialFreqId: timerVM.activeConfig.audio.freqId,
                accentColor: activeAccent,
                dimmedColor: activeDimmed,
                backgroundColor: activeBackground,
                onNoiseChanged: { timerVM.updateNoiseId($0) },
                onFreqChanged: { timerVM.updateFreqId($0) },
                onSave: { onSavePreset?(timerVM.activeConfig) },
                onDismiss: {
                    withAnimation(HIGMotion.overlay) {
                        showEqualizer = false
                    }
                }
            )
            #if os(iOS)
            .frame(maxWidth: 460, maxHeight: 420)
            #else
            .frame(maxWidth: 460, maxHeight: 520)
            #endif
            .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 12)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    // Botón de retorno (solo aparece si el cronómetro está pausado)
    @ViewBuilder
    private var returnButton: some View {
        if !timerVM.isRunning {
            Button(action: {
                Haptics.impact(.light, intensity: 0.6)
                withAnimation(HIGMotion.navigate) {
                    onNavigate?(.savedPresets)
                }
            }) {
                Image(systemName: returnIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(activeAccent)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    )
                    .overlay(Circle().stroke(activeAccent.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.pressable)
            #if os(macOS)
            .padding(30)
            #endif
            .transition(.scale.combined(with: .opacity))
        }
    }

    var body: some View {
        ZStack {
            Group {
                Button("") {
                    if !isAnyPopupOpen { onNavigate?(.savedPresets) }
                }
                .keyboardShortcut(.cancelAction)
            }
            .opacity(0)
            .frame(width: 0, height: 0)

            // MARK: - Atajos de Teclado Globales
            //
            // Space, Return y P → toggle (play/pause).
            // ↑ / ↓ → volver a SavedPresets (comportamiento existente, sin tocar).
            Group {
                Button("") { if !isAnyPopupOpen { timerVM.userToggleTimer() } }.keyboardShortcut(.space, modifiers: [])
                Button("") { if !isAnyPopupOpen { timerVM.userToggleTimer() } }.keyboardShortcut(KeyEquivalent("p"), modifiers: [])
                Button("") { if !isAnyPopupOpen { onNavigate?(.savedPresets) } }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { if !isAnyPopupOpen { onNavigate?(.savedPresets) } }.keyboardShortcut(.upArrow, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)

            activeBackground
                .ignoresSafeArea()
                .animation(HIGMotion.phase, value: timerVM.isBreak)
                .animation(HIGMotion.phase, value: timerVM.currentTheme.noiseName)

            VStack {

                TopHeaderView(
                    isBreak: timerVM.isBreak,
                    accentColor: activeDimmed,
                    noiseName: formattedAudioString(),
                    focusTime: timerVM.activeConfig.focus,
                    breakTime: timerVM.activeConfig.breakTime
                )

                HStack {
                    Spacer()
                    Button(action: {
                        Haptics.selection()
                        withAnimation(HIGMotion.overlay) { showEqualizer = true }
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(activeDimmed.opacity(0.5))
                            .frame(width: 44, height: 44) // Hit area invisible
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.top, -5)

                Spacer(minLength: 10)

                HStack(spacing: isPortrait ? 5 : 20) {
                    Button(action: {
                        guard !isAnyPopupOpen else { return }
                        Haptics.selection()
                        if timerVM.isMirror {
                            timerVM.userSkipPrevious()
                        } else {
                            if timerVM.skipToPreviousPhase() { onNavigate?(.savedPresets) }
                        }
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(activeDimmed.opacity(0.6))
                    }
                    .buttonStyle(.pressable)
                    .frame(width: isPortrait ? 40 : 80, height: 80)
                    .contentShape(Rectangle())
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .scaleEffect(timerVM.isRunning ? 0.9 : 1.0)
                    .opacity(timerVM.isRunning ? 0.0 : 1.0)
                    .animation(HIGMotion.state, value: timerVM.isRunning)

                    CenterTimerView(
                        timerVM: timerVM,
                        accentColor: activeAccent,
                        dimmedColor: activeDimmed,
                        ringBaseColor: timerVM.currentTheme.ringBaseColor
                    )
                    .scaleEffect(timerVM.isRunning ? 0.96 : 1.0)
                    .animation(HIGMotion.state, value: timerVM.isRunning)

                    Button(action: {
                        guard !isAnyPopupOpen else { return }
                        Haptics.selection()
                        if timerVM.isMirror {
                            timerVM.userSkipNext()
                        } else {
                            _ = timerVM.skipToNextPhase(wasCompleted: false)
                        }
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(activeDimmed.opacity(0.6))
                    }
                    .buttonStyle(.pressable)
                    .frame(width: isPortrait ? 40 : 80, height: 80)
                    .contentShape(Rectangle())
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .scaleEffect(timerVM.isRunning ? 0.9 : 1.0)
                    .opacity(timerVM.isRunning ? 0.0 : 1.0)
                    .animation(HIGMotion.state, value: timerVM.isRunning)
                }

                Spacer(minLength: 10)
                
                BottomProgressView(
                                    totalSessions: timerVM.totalSessions,
                                    currentSession: timerVM.currentSession,
                                    isBreak: timerVM.isBreak,
                                    accentColor: activeAccent,
                                    dimmedColor: activeDimmed,
                                    totalTimeLeft: timerVM.totalTimeRemainingString,
                                    onSelectSession: { n in
                                        timerVM.userSelectSession(n)
                                    }
                                )
            }
            .padding(isPortrait ? 16 : 40)
        }
        // MARK: - Flecha de Retorno
        .overlay {
            #if os(iOS)
            GeometryReader { geo in
                returnButton
                    .position(x: geo.size.width * 0.25,
                              y: geo.size.height * 0.75)
            }
            #else
            returnButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: returnAlignment)
            #endif
        }
        // HOJA DEL ECUALIZADOR
        .overlay {
            if showEqualizer {
                equalizerOverlay()   // ← Llamada al método
            }
        }
        #if os(macOS)
        .onExitCommand {
            if showEqualizer {
                withAnimation(HIGMotion.overlay) {
                    showEqualizer = false
                }
            } else {
                onNavigate?(.savedPresets)
            }
        }
        .scrollWheelBack {
            if !isAnyPopupOpen { onNavigate?(.savedPresets) }
        }
        #endif
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { value in
                    guard !isAnyPopupOpen else { return }
                    let translation = value.translation
                    #if os(macOS)
                    if translation.height < -50 || translation.height > 50 { onNavigate?(.savedPresets) }
                    #else
                    if translation.width < -50 || translation.width > 50 { onNavigate?(.savedPresets) }
                    #endif
                }
        )
        .onTapGesture {
            guard !isAnyPopupOpen else { return }
            timerVM.userToggleTimer()
        }
        // HIG: la respuesta háptica sigue al CAMBIO DE ESTADO, no al gesto. Así también vibra
        // cuando el cambio viene de la isla, del teclado o del Master (mirror).
        .onChange(of: timerVM.isRunning) { _, running in
            Haptics.impact(running ? .medium : .soft, intensity: 0.85)
        }
        .onChange(of: timerVM.isBreak) { _, _ in
            Haptics.impact(.light, intensity: 0.6)
        }
        #if os(macOS)
        .onAppear { installReturnKeyMonitor() }
        .onDisappear { removeReturnKeyMonitor() }
        #endif
    }

    // MARK: - Formateador Dinámico de Audio
    private func formattedAudioString() -> String {
        let noiseId = timerVM.activeConfig.audio.noiseId
        let freqId = timerVM.activeConfig.audio.freqId

        var freqStr = ""
        switch freqId {
        case 1: freqStr = "40 HZ"
        case 2: freqStr = "15 HZ"
        case 3: freqStr = "10 HZ"
        case 4: freqStr = "6 HZ"
        default: break
        }

        var noiseStr = ""
        switch noiseId {
        case 1: noiseStr = "BROWN NOISE"
        case 2: noiseStr = "PINK NOISE"
        case 3: noiseStr = "WHITE NOISE"
        case 4: noiseStr = "VIOLET NOISE"
        case 5: noiseStr = "NATURE"
        default: break
        }

        if !freqStr.isEmpty && !noiseStr.isEmpty {
            return "\(freqStr) - \(noiseStr)"
        } else if !freqStr.isEmpty {
            return freqStr
        } else if !noiseStr.isEmpty {
            return noiseStr
        } else {
            return "NO SOUND"
        }
    }

    #if os(macOS)
    /// Intercepta Return para toggle. Se consume el evento para que no
    /// llegue a la responder chain (que es la que causaba el bug).
    /// No dispara si el ecualizador está abierto (por si en el futuro
    /// contiene TextField).
    private func installReturnKeyMonitor() {
        guard returnKeyMonitor == nil else { return }
        returnKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // keyCode 36 = Return principal
            // keyCode 76 = Enter del teclado numérico
            let isReturn = event.keyCode == 36 || event.keyCode == 76

            // Sin modifiers (Shift, Cmd, Alt, Ctrl) para no robar otros atajos.
            let noModifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .isEmpty

            guard isReturn, noModifiers, !showEqualizer else {
                return event   // dejar pasar el evento
            }

            timerVM.userToggleTimer()
            return nil         // consumir el evento
        }
    }

    private func removeReturnKeyMonitor() {
        if let monitor = returnKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        returnKeyMonitor = nil
    }
    #endif
}

// MARK: - Timer Central
struct CenterTimerView: View {
    @ObservedObject var timerVM: TimerViewModel

    var accentColor: Color
    var dimmedColor: Color
    var ringBaseColor: Color

    #if os(iOS)
    @Environment(\.horizontalSizeClass) var hClass
    @Environment(\.verticalSizeClass) var vClass
    private var isPortrait: Bool { hClass == .compact && vClass == .regular }
    #else
    private var isPortrait: Bool { false }
    #endif

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2)
                .foregroundColor(ringBaseColor)

            Circle()
                .trim(from: 0.0, to: timerVM.progress)
                .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .foregroundColor(accentColor)
                .rotationEffect(.degrees(-90))
                .animation(HIGMotion.progress, value: timerVM.progress)
        }
        .frame(minWidth: isPortrait ? 230 : 260, maxWidth: 480, minHeight: isPortrait ? 230 : 260, maxHeight: 480)
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 20)
        .overlay(
            VStack(spacing: 12) {
                Text(timerVM.isBreak ? "BREAK" : "FOCUS")
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .tracking(6)
                    .foregroundColor(dimmedColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(timerVM.timeRemainingString)
                    #if os(macOS)
                    .font(.system(size: 140, weight: .ultraLight, design: .default))
                    #else
                    .font(.system(size: isPortrait ? 85 : 95, weight: .ultraLight, design: .default))
                    #endif
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .foregroundColor(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(HIGMotion.numeric, value: timerVM.timeRemainingString)
                    .padding(.horizontal, 10)

                Text("SESSION \(timerVM.currentSession) OF \(timerVM.totalSessions)")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .tracking(2)
                    .foregroundColor(dimmedColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 20)
        )
        .contentShape(Circle())
        .onTapGesture {
            timerVM.userToggleTimer()
        }
    }
}

// MARK: - Header (Limpio)
struct TopHeaderView: View {
    var isBreak: Bool
    var accentColor: Color
    var noiseName: String
    var focusTime: Int
    var breakTime: Int

    var body: some View {
        HStack {
            Text("\(focusTime) / \(breakTime) METHOD")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .tracking(2)

            Spacer()

            Text(noiseName)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .tracking(2)
        }
        .foregroundColor(accentColor)
    }
}

// MARK: - Preview
struct PomodoroMinimalistView_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroMinimalistView(
            timerViewModel: TimerViewModel(),
            presetsVM: PresetsViewModel(repository: UserDefaultsPomodoroRepository()),
            freeModeVM: FreeModeViewModel() // <-- CORREGIDO ACÁ
        )
        .frame(width: 1000, height: 700)
    }
}

// MARK: - Frames de cada sesión (para saber sobre cuál está el dedo)
private struct SessionMidXKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Eleva una baldosa en vertical según su distancia horizontal al dedo.
/// Solo `amplitude` (q) es animable: el dedo se sigue sin animación.
// MARK: - Efecto Topológico Continuo (Soporte Invisible)
// MARK: - Efecto Topológico Continuo (Soporte Invisible + Squash)
private struct TileLiftEffect: ViewModifier, Animatable {
    var amplitude: CGFloat          // q(t): 0...1
    var fingerX: CGFloat            // Rastreo continuo del dedo
    var squash: CGFloat             // <0 aplasta, >0 estira
    let tileX: CGFloat
    let maxLift: CGFloat            // A
    let radius: CGFloat             // R
    var applyRotation: Bool         // true = rectángulos, false = números

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(amplitude, AnimatablePair(fingerX, squash)) }
        set {
            amplitude = newValue.first
            fingerX = newValue.second.first
            squash = newValue.second.second
        }
    }

    private var d: CGFloat { tileX - fingerX }
    
    private var bell: CGFloat {
        guard radius > 0, abs(d) < radius else { return 0 }
        return 0.5 * (1 + cos(.pi * d / radius))
    }
    
    private var lift: CGFloat {
        maxLift * bell * max(0, amplitude) // Nunca por debajo del nivel inicial
    }
    
    private var angle: Double {
        guard applyRotation, bell > 0, amplitude > 0.001 else { return 0 }
        let slope = maxLift * 0.5 * amplitude * (.pi / radius) * sin(.pi * d / radius)
        return Double(atan(slope) * 180 / .pi)
    }

    func body(content: Content) -> some View {
        let s = applyRotation ? squash * bell : 0
        let sy = max(0.3, 1 + 1.1 * s)
        let sx = max(0.5, 1 - 0.22 * s)
        
        return content
            .scaleEffect(x: sx, y: sy, anchor: .center)
            .rotationEffect(.degrees(angle), anchor: .center)
            .offset(y: -lift)
    }
}

// MARK: - Progreso inferior
struct BottomProgressView: View {
    var totalSessions: Int
    var currentSession: Int
    var isBreak: Bool
    var accentColor: Color
    var dimmedColor: Color
    var totalTimeLeft: String

    /// macOS: 1 clic. iOS: mantener 0,75 s y arrastrar.
    var onSelectSession: ((Int) -> Void)? = nil

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    // MARK: Parámetros de ajuste
    private static let barSpace = "sessionsBar"
    private let holdDuration: Double = 0.75     // mantener para poder seleccionar
    #if os(macOS)
    private let moveTolerance: CGFloat = 3      // Alta sensibilidad para puntero de mouse
    #else
    private let moveTolerance: CGFloat = 10     // movimiento para arrancar la onda
    #endif
    private let maxLift: CGFloat = 16           // A: elevación máxima (pt)
    private let tapAmplitude: CGFloat = 0.35    // intensidad del amague al tocar
    private let releaseDuration: Double = 0.5   // relajación al soltar

    private enum Phase { case idle, pressing, waving, selecting, ignored }

    // MARK: Estado
    @State private var phase: Phase = .idle
    @GestureState private var isTouching = false
    @State private var fingerX: CGFloat = 0
    @State private var startLocation: CGPoint = .zero
    @State private var hoveredIndex: Int? = nil
    @State private var cellMidX: [Int: CGFloat] = [:]
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var effectTask: Task<Void, Never>? = nil // Agregado
    
    #if os(macOS)
    /// Controla el estado del rebote local tras hacer clic
    @State private var macClickedIndex: Int? = nil
    #endif
        
    /// q(t): factor temporal de la onda (0 = plano, 1 = máxima elevación).
    @State private var wave: CGFloat = 0
    @State private var squash: CGFloat = 0 // Agregado
    
    /// Determina hasta qué sesión se debe pintar la UI en el frame actual.
        /// Si el usuario está arrastrando, asume la posición del dedo. Si está en reposo, usa la real.
    private var effectiveSession: Int {
        if (phase == .selecting || phase == .waving), let idx = hoveredIndex {
            return idx
        }
        return currentSession
    }

    var body: some View {
            ViewThatFits(in: .horizontal) {
                // MARK: - Layout Principal (Anclado al centro absoluto)
                HStack(alignment: .bottom, spacing: 20) {
                    
                    // 1. Caja Izquierda Simétrica
                    ZStack(alignment: .bottomLeading) {
                        rightText.hidden() // Fantasma: fuerza el ancho máximo entre ambos
                        leftText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 2. Barra Central (Inmóvil)
                    sessionsBar
                        .layoutPriority(1) // Protege la barra de ser comprimida
                    
                    // 3. Caja Derecha Simétrica
                    ZStack(alignment: .bottomTrailing) {
                        leftText.hidden() // Fantasma: fuerza el ancho máximo entre ambos
                        rightText
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    
                }

                // MARK: - Layout Fallback (Colapsado en pantallas estrechas)
                VStack(spacing: 18) {
                    sessionsBar

                    HStack {
                        leftText
                        Spacer()
                        rightText
                    }
                }
            }
            .padding(.horizontal)
            .onDisappear {
                holdTask?.cancel()
                holdTask = nil
                effectTask?.cancel()
                effectTask = nil
                phase = .idle
                hoveredIndex = nil
                wave = 0
                squash = 0
            }
        }

    private var leftText: some View {
            Text("PROGRESS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundColor(dimmedColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }

        private var rightText: some View {
            Text(totalTimeLeft)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .tracking(2)
                .foregroundColor(dimmedColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }

    // MARK: - Radio de la onda (se adapta a la separación entre baldosas)

    private var waveRadius: CGFloat {
        let xs = cellMidX.values.sorted()
        guard xs.count >= 2, let first = xs.first, let last = xs.last else { return 90 }
        let pitch = (last - first) / CGFloat(xs.count - 1)
        return min(max(pitch * 2.4, 56), 130)
    }

    // MARK: - Barra de sesiones

    @ViewBuilder
        private var sessionsBar: some View {
            #if os(macOS)
            let limit = 41
            #else
            let limit = (horizontalSizeClass == .regular || verticalSizeClass == .compact) ? 13 : 8
            #endif

            let showNumbers = totalSessions <= limit
            let radius = waveRadius

            HStack(alignment: .bottom, spacing: showNumbers ? 4 : 6) {
                ForEach(0..<totalSessions, id: \.self) { index in
                    let sessionIndex = index + 1

                    HStack(alignment: .bottom, spacing: showNumbers ? 4 : 3) {
                        sessionColumn(sessionIndex, showNumbers: showNumbers, radius: radius)

                        if sessionIndex < totalSessions {
                            connectorColumn(sessionIndex, showNumbers: showNumbers, radius: radius)
                        }
                    }
                    .frame(minHeight: 50, alignment: .bottom)
                    .contentShape(Rectangle())
                    // Apple Standard: Interpolación elástica del repintado en tiempo real.
                    .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.75), value: effectiveSession)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            #if os(iOS)
            .padding(.vertical, 10)
            #endif
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.barSpace)
            .onPreferenceChange(SessionMidXKey.self) { mids in
                if mids != cellMidX { cellMidX = mids }
            }
            .overlay(alignment: .topLeading) { selectionBubble }
            // Gesto Universal (Funde Clic y Arrastre para ambos OS)
            .highPriorityGesture(selectionGesture)
            .onChange(of: isTouching) { _, touching in
                if !touching { finishTouch() }
            }
        }

    @ViewBuilder
        private func sessionColumn(_ sessionIndex: Int, showNumbers: Bool, radius: CGFloat) -> some View {
            let isHovered = phase == .selecting && hoveredIndex == sessionIndex
            let isPainted = sessionIndex <= effectiveSession
            
            let tint: Color = isPainted
                ? (isHovered ? accentColor.opacity(1.0) : accentColor.opacity(0.85))
                : dimmedColor.opacity(0.3)

            #if os(macOS)
            let localWave: CGFloat = 0
            let localSquash: CGFloat = 0
            let applyRot = false
            
            // Fusión de estados: Reacciona tanto al clic estático como al arrastre dinámico
            let isMacActive = (macClickedIndex == sessionIndex) || isHovered
            let macScale: CGFloat = isMacActive ? 0.92 : 1.0
            let macBrightness: Double = isMacActive ? 0.3 : 0.0
            #else
            let localWave = wave
            let localSquash = squash
            let applyRot = true
            
            let macScale: CGFloat = 1.0
            let macBrightness: Double = 0.0
            #endif

            VStack(spacing: 8) {
                Capsule()
                    .fill(tint)
                    .frame(minWidth: showNumbers ? 8 : 4, idealWidth: 45, maxWidth: 45, minHeight: 4, maxHeight: 4)
                    .brightness(macBrightness)
                    .scaleEffect(macScale)
                    .modifier(TileLiftEffect(
                        amplitude: localWave,
                        fingerX: fingerX,
                        squash: localSquash,
                        tileX: cellMidX[sessionIndex] ?? 0,
                        maxLift: maxLift,
                        radius: radius,
                        applyRotation: applyRot
                    ))

                if showNumbers {
                    Text("\(sessionIndex)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(tint)
                        .lineLimit(1)
                        .opacity(isPainted ? 1.0 : 0.6)
                        .scaleEffect(macScale)
                        .modifier(TileLiftEffect(
                            amplitude: localWave,
                            fingerX: fingerX,
                            squash: localSquash,
                            tileX: cellMidX[sessionIndex] ?? 0,
                            maxLift: maxLift,
                            radius: radius,
                            applyRotation: false
                        ))
                }
            }
            .background(
                GeometryReader { geo in
                    // Habilitado universalmente para dar soporte de coordenadas al puntero del mouse
                    Color.clear.preference(
                        key: SessionMidXKey.self,
                        value: [sessionIndex: geo.frame(in: .named(Self.barSpace)).midX]
                    )
                }
            )
        }

        @ViewBuilder
        private func connectorColumn(_ sessionIndex: Int, showNumbers: Bool, radius: CGFloat) -> some View {
            let a = cellMidX[sessionIndex] ?? 0
            let b = cellMidX[sessionIndex + 1] ?? a
            let x = (a + b) / 2

            let isPainted = (sessionIndex < effectiveSession) || (sessionIndex == effectiveSession && isBreak)
            let tint: Color = isPainted ? accentColor.opacity(0.7) : dimmedColor.opacity(0.2)

            #if os(macOS)
            let localWave: CGFloat = 0
            let localSquash: CGFloat = 0
            let applyRot = false
            #else
            let localWave = wave
            let localSquash = squash
            let applyRot = true
            #endif

            VStack(spacing: 8) {
                Capsule()
                    .fill(tint)
                    .frame(minWidth: showNumbers ? 3 : 2, idealWidth: 10, maxWidth: 10, minHeight: 4, maxHeight: 4)
                    .modifier(TileLiftEffect(
                        amplitude: localWave,
                        fingerX: fingerX,
                        squash: localSquash,
                        tileX: x,
                        maxLift: maxLift,
                        radius: radius,
                        applyRotation: applyRot
                    ))

                if showNumbers {
                    Text(" ").font(.system(size: 11))
                        .modifier(TileLiftEffect(
                            amplitude: localWave,
                            fingerX: fingerX,
                            squash: localSquash,
                            tileX: x,
                            maxLift: maxLift,
                            radius: radius,
                            applyRotation: false
                        ))
                }
            }
        }

    // MARK: - Burbuja "SESSION N"

    @ViewBuilder
    private var selectionBubble: some View {
        GeometryReader { geo in
            if phase == .selecting, let idx = hoveredIndex {
                Text("SESSION \(idx)")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundColor(accentColor)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(accentColor.opacity(0.35), lineWidth: 1))
                    .position(
                        x: min(max(fingerX, 56), max(56, geo.size.width - 56)),
                        y: -52
                    )
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: phase == .selecting)
    }

    // MARK: - Gesto (iOS)

    // MARK: - Gesto (iOS)

        // Reducido a 0.16 para latencia ultra-baja a 120Hz. Damping 0.76 permite overshoot mínimo.
        private var trackingSpring: Animation {
            .interactiveSpring(response: 0.16, dampingFraction: 0.76, blendDuration: 0.1)
        }

        private var selectionGesture: some Gesture {
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.barSpace))
                .updating($isTouching) { _, state, _ in state = true }
                .onChanged { value in
                    let x = value.location.x
                    
                    switch phase {
                    case .idle:
                        beginPress(at: value.location)
                        
                    case .pressing:
                        withAnimation(trackingSpring) { fingerX = x }
                        let dx = x - startLocation.x
                        let dy = value.location.y - startLocation.y
                        
                        if hypot(dx, dy) > moveTolerance {
                            if abs(dx) >= abs(dy) {
                                startSwiping(at: x)
                            } else {
                                ignoreGesture()
                            }
                        }
                        
                    case .selecting, .waving:
                        withAnimation(trackingSpring) { fingerX = x }
                        let idx = nearestSession(to: x)
                        if idx != hoveredIndex {
                            hoveredIndex = idx
                            haptic(.tick)
                        }
                        
                    case .ignored:
                        break
                    }
                }
        }

        // MARK: - Fases del gesto

        private func beginPress(at location: CGPoint) {
            phase = .pressing
            startLocation = location
            fingerX = location.x
            
            effectTask?.cancel()
            effectTask = nil
            haptic(.press)
            
            // Anticipación
            withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) {
                squash = -0.4
                wave = tapAmplitude
            }
            
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(holdDuration * 0.55))
                guard !Task.isCancelled, phase == .pressing else { return }
                
                haptic(.charge)
                withAnimation(.easeIn(duration: holdDuration * 0.45)) { squash = -0.75 }
                
                try? await Task.sleep(for: .seconds(holdDuration * 0.45))
                guard !Task.isCancelled, phase == .pressing else { return }
                
                activateSelection()
            }
        }

        private func startSwiping(at x: CGFloat) {
            holdTask?.cancel()
            holdTask = nil
            phase = .selecting
            hoveredIndex = nearestSession(to: x)
            haptic(.swipe)
            pop(0.6, waveTo: 1, endWave: 1, echo: false)
        }

        private func activateSelection() {
            phase = .selecting
            hoveredIndex = nearestSession(to: fingerX)
            haptic(.activate)
            pop(0.85, waveTo: 1, endWave: 1, echo: false)
        }

        private func ignoreGesture() {
            holdTask?.cancel()
            holdTask = nil
            phase = .ignored
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                squash = 0
                wave = 0
            }
        }

    private func finishTouch() {
            guard phase != .idle else { return }
            
            holdTask?.cancel()
            holdTask = nil
            
            let previous = phase
            let target = hoveredIndex
            let startLocX = startLocation.x // Guardamos la X original para el clic en macOS
            
            phase = .idle
            hoveredIndex = nil
            
            switch previous {
            case .pressing:
                #if os(macOS)
                // macOS Desktop: Un clic sin arrastre selecciona de inmediato la cápsula clickeada.
                if let clickTarget = nearestSession(to: startLocX) {
                    handleMacClick(on: clickTarget)
                }
                #else
                // iOS: Toque abortado (requiere swipe para seleccionar).
                haptic(.tap)
                pop(0.9, waveTo: 0.6, endWave: 0, echo: true)
                #endif
                
            case .selecting, .waving:
                if let target {
                    haptic(.commit)
                    onSelectSession?(target)
                }
                pop(0.7, waveTo: 0.7, endWave: 0, echo: true)
                
            default:
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    squash = 0
                    wave = 0
                }
            }
        }

    /// Estira de golpe (exageración) y después asienta con rebote (follow-through).
        private func pop(_ amount: CGFloat, waveTo: CGFloat, endWave: CGFloat, echo: Bool) {
            effectTask?.cancel()
            
            withAnimation(.spring(response: 0.2, dampingFraction: 0.45)) {
                squash = amount
                wave = waveTo
            }
            
            effectTask = Task { @MainActor in
                // Menor tiempo de bloqueo para la fase de retorno
                try? await Task.sleep(for: .milliseconds(85))
                guard !Task.isCancelled else { return }
                
                if echo { haptic(.echo) }
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                    squash = 0
                    wave = endWave
                }
            }
        }
    
#if os(macOS)
    private func handleMacClick(on index: Int) {
        // Tensión inicial: micro-contracción elegante y flash de luz
        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.6)) {
            macClickedIndex = index
        }
        
        onSelectSession?(index)
        
        // Gravedad de retorno: asienta suavemente como un control táctil premium
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                if macClickedIndex == index {
                    macClickedIndex = nil
                }
            }
        }
    }
    #endif

        private func nearestSession(to x: CGFloat) -> Int? {
            cellMidX.min { abs($0.value - x) < abs($1.value - x) }?.key
        }

        // MARK: - Haptics

        private enum HapticKind { case press, charge, activate, swipe, tick, commit, tap, echo }

        private func haptic(_ kind: HapticKind) {
            switch kind {
            case .press:    Haptics.impact(.light,  intensity: 0.5)
            case .charge:   Haptics.impact(.soft,   intensity: 0.8)
            case .activate: Haptics.impact(.medium, intensity: 1.0)
            case .swipe:    Haptics.impact(.light,  intensity: 0.7)
            case .tick:     Haptics.selection()
            case .commit:   Haptics.success()
            case .tap:      Haptics.impact(.medium, intensity: 0.8)
            case .echo:     Haptics.impact(.soft,   intensity: 0.5)
            }
    }
}
