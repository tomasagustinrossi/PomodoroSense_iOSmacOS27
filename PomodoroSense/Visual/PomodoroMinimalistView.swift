import SwiftUI

enum AppScreen {
    case mainTimer
    case timerSetup
    case savedPresets
}

struct PomodoroMinimalistView: View {
    
    // MARK: - Variables de Estado y Entorno
    @StateObject private var timerViewModel = TimerViewModel()
    @StateObject private var presetsVM = PresetsViewModel(repository: UserDefaultsPomodoroRepository())
    
    @Environment(\.scenePhase) var scenePhase // NUEVO: Para saber si la app se minimiza
        
    @State private var configToEdit: PomodoroConfigDTO? = nil
    @State private var currentScreen: AppScreen = .savedPresets
        
    // MARK: - Estado de Alertas (Reglas de Negocio)
    @State private var showWarning: Bool = false
    @State private var warningMessage: String = ""
    @State private var warningTask: Task<Void, Never>? = nil // Para cancelar alertas previas si spamean el botón
    
    
    
    var body: some View {
        ZStack {
        switch currentScreen {
        case .mainTimer:
            MainTimerScreen(
                timerVM: timerViewModel,
                onNavigate: { screen in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { currentScreen = screen }
                }
            )
            
        case .savedPresets:
                        SavedPresetsView(
                            presetsVM: presetsVM,
                            isTimerActive: timerViewModel.isRunning || timerViewModel.progress < 1.0 || timerViewModel.currentSession > 1,
                            onNavigate: { destinationScreen, payload in
                                
                                // 1. Si el payload trae un DTO (porque le dimos al Lápiz de editar), lo guardamos en la mochila.
                                // Si le dimos al "+", payload será nil y la mochila quedará vacía (creación nueva).
                                if destinationScreen == .timerSetup {
                                    configToEdit = payload
                                }
                                
                                // 2. Si le dimos al "Play", disparamos el motor
                                if destinationScreen == .mainTimer, let config = payload {
                                    timerViewModel.loadConfiguration(config, autoStart: true)
                                }
                                
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    currentScreen = destinationScreen
                                }
                            }
                        )
                        
                    case .timerSetup:
                        PomodoroSettingsView(
                            initialConfig: configToEdit, // Le pasamos lo que haya en la mochila
                            onNavigate: { screen, _ in
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { currentScreen = screen }
                            },
                            onSave: { configuration in
                                print("🎯 [UI] Recibido DTO para guardar: \(configuration.name)")
                                
                                // Guardamos en el disco
                                presetsVM.savePreset(configuration)
                                
                                // Si el temporizador principal estaba corriendo con esta configuración,
                                // opcionalmente podrías actualizarlo aquí.
                                // timerViewModel.loadConfiguration(configuration)
                                
                                // Volvemos a la lista
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { currentScreen = .savedPresets }
                            }
                        )
        }
    }
    // Limita la reducción de la ventana en macOS y fuerza un tamaño seguro en iPad/iOS
    .frame(minWidth: 350, minHeight: 450)
    // MARK: - Detección de Segundo Plano
    .onChange(of: scenePhase) { oldPhase, newPhase in
        if newPhase == .background {
            timerViewModel.sceneMovedToBackground()
        } else if newPhase == .active {
            timerViewModel.sceneMovedToForeground()
        }
    }
    }
    
    // MARK: - Pantalla Principal
        struct MainTimerScreen: View {
            @ObservedObject var timerVM: TimerViewModel
            var onNavigate: ((AppScreen) -> Void)? = nil
            
            // Propiedades computadas enrutando directamente al protocolo
            private var activeBackground: Color { timerVM.isBreak ? timerVM.currentTheme.breakBackground : timerVM.currentTheme.workBackground }
            private var activeAccent: Color { timerVM.isBreak ? timerVM.currentTheme.breakAccent : timerVM.currentTheme.workAccent }
            private var activeDimmed: Color { timerVM.isBreak ? timerVM.currentTheme.textDimmedBreak : timerVM.currentTheme.textDimmedWork }
            
            var body: some View {
                ZStack {
                    activeBackground
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 1.2), value: timerVM.isBreak)
                        .animation(.easeInOut(duration: 0.8), value: timerVM.currentTheme.noiseName) // Transición suave si cambian de preset
                    
                    VStack {
                        TopHeaderView(
                            isBreak: timerVM.isBreak,
                            accentColor: activeDimmed,
                            noiseName: timerVM.currentTheme.noiseName, // Inyectamos el texto del motor
                            focusTime: timerVM.activeConfig.focus,     // Inyección
                            breakTime: timerVM.activeConfig.breakTime  // Inyección
                        )
                        
                        Spacer(minLength: 10) // Mínimo margen elástico
                        
                        // Controles Laterales con el Reloj en el centro
                        HStack(spacing: 20) {
                            Button(action: {
                                if timerVM.skipToPreviousPhase() { onNavigate?(.savedPresets) }
                            }) {
                                Image(systemName: "backward.end.fill")
                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundColor(activeDimmed.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(timerVM.isRunning ? 0.9 : 1.0)
                            .opacity(timerVM.isRunning ? 0.0 : 1.0)
                            .animation(.spring(), value: timerVM.isRunning)
                            
                            CenterTimerView(
                                timerVM: timerVM,
                                accentColor: activeAccent,
                                dimmedColor: activeDimmed,
                                ringBaseColor: timerVM.currentTheme.ringBaseColor
                            )
                            .scaleEffect(timerVM.isRunning ? 0.96 : 1.0)
                            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.5), value: timerVM.isRunning)
                            
                            Button(action: {
                                if timerVM.skipToNextPhase() { onNavigate?(.savedPresets) }
                            }) {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundColor(activeDimmed.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(timerVM.isRunning ? 0.9 : 1.0)
                            .opacity(timerVM.isRunning ? 0.0 : 1.0)
                            .animation(.spring(), value: timerVM.isRunning)
                        }
                        
                        Spacer(minLength: 10) // Mínimo margen elástico
                        
                        BottomProgressView(
                            totalSessions: timerVM.totalSessions,
                            currentSession: timerVM.currentSession,
                            isBreak: timerVM.isBreak,
                            accentColor: activeAccent,
                            dimmedColor: activeDimmed,
                            totalTimeLeft: timerVM.totalTimeRemainingString // Inyección
                        )
                    }
                    .padding(40)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            let translation = value.translation
    #if os(macOS)
                            if translation.height < -50 || translation.height > 50 { onNavigate?(.savedPresets) }
    #else
                            if translation.width < -50 || translation.width > 50 { onNavigate?(.savedPresets) }
    #endif
                        }
                )
                .onTapGesture {
                    timerVM.toggleTimer()
                }
            }
        }
        
    // MARK: - Timer Central
        
        struct CenterTimerView: View {
            @ObservedObject var timerVM: TimerViewModel
            
            var accentColor: Color
            var dimmedColor: Color
            var ringBaseColor: Color
            
            var body: some View {
                // 1. Unificamos los anillos como el contenedor padre geométrico
                ZStack {
                    Circle()
                        .stroke(lineWidth: 1)
                        .foregroundColor(ringBaseColor)
                    
                    Circle()
                        .trim(from: 0.0, to: timerVM.progress)
                        .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .foregroundColor(accentColor)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: timerVM.progress)
                }
                .frame(maxWidth: 480)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 20)
                // 2. Encapsulamos los textos en un overlay para forzar la reducción de fuente en ventanas pequeñas
                .overlay(
                    VStack(spacing: 12) {
                        Text(timerVM.isBreak ? "BREAK" : "FOCUS")
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .tracking(6)
                            // CORRECCIÓN DE COLOR: Aplicamos dimmedColor para igualar la jerarquía visual inferior
                            .foregroundColor(dimmedColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
                        Text(timerVM.timeRemainingString) // LECTURA EN TIEMPO REAL
                            .font(.system(size: 140, weight: .ultraLight, design: .default))
                            .monospacedDigit()
                            .lineLimit(1)
                            // Factor de escala agresivo (0.2) para que el texto principal se comprima en macOS
                            .minimumScaleFactor(0.2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        Text("SESSION \(timerVM.currentSession) OF \(timerVM.totalSessions)")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .tracking(2)
                            .foregroundColor(dimmedColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    // Margen de seguridad interno para que el texto nunca pise la línea del anillo
                    .padding(.horizontal, 45)
                )
            }
        }
    
    // MARK: - Header
        struct TopHeaderView: View {
            var isBreak: Bool
            var accentColor: Color
            var noiseName: String
            var focusTime: Int // NUEVO
            var breakTime: Int // NUEVO
            
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
    
    // MARK: - Progreso inferior
        struct BottomProgressView: View {
            var totalSessions: Int
            var currentSession: Int
            var isBreak: Bool
            var accentColor: Color
            var dimmedColor: Color
            var totalTimeLeft: String
            
            // Variables de entorno para detectar la orientación y el tamaño del dispositivo
            @Environment(\.horizontalSizeClass) var horizontalSizeClass
            @Environment(\.verticalSizeClass) var verticalSizeClass
            
            var body: some View {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 20) {
                        leftText
                        sessionsBar
                        rightText
                    }
                    
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
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(dimmedColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            @ViewBuilder
            private var sessionsBar: some View {
                // Lógica de legibilidad: Mac y pantallas apaisadas tienen un límite de x; verticales compactas de 8
                #if os(macOS)
                let limit = 41 // x
                #else
                let limit = (horizontalSizeClass == .regular || verticalSizeClass == .compact) ? 13 : 8
                #endif
                
                let showNumbers = totalSessions <= limit
                
                HStack(alignment: .bottom, spacing: showNumbers ? 4 : 6) {
                    ForEach(0..<totalSessions, id: \.self) { index in
                        let sessionIndex = index + 1
                        
                        HStack(spacing: showNumbers ? 4 : 3) {
                            
                            // Trabajo
                            VStack(spacing: 8) {
                                Capsule()
                                    .fill(sessionIndex <= currentSession ? accentColor : dimmedColor.opacity(0.4))
                                    .frame(minWidth: showNumbers ? 8 : 4, idealWidth: 45, maxWidth: 45, minHeight: 4, maxHeight: 4)
                                
                                if showNumbers {
                                    Text("\(sessionIndex)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(sessionIndex <= currentSession ? accentColor : dimmedColor.opacity(0.4))
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                            }
                            
                            // Descanso
                            if sessionIndex < totalSessions {
                                VStack(spacing: 8) {
                                    Capsule()
                                        .fill((sessionIndex < currentSession) || (sessionIndex == currentSession && isBreak) ? accentColor.opacity(0.7) : dimmedColor.opacity(0.2))
                                        .frame(minWidth: showNumbers ? 3 : 2, idealWidth: 10, maxWidth: 10, minHeight: 4, maxHeight: 4)
                                    
                                    if showNumbers {
                                        Text(" ").font(.system(size: 11))
                                    }
                                }
                            }
                            
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    
    // MARK: - Preview
    
    struct PomodoroMinimalistView_Previews: PreviewProvider {
        static var previews: some View {
            PomodoroMinimalistView()
                .frame(
                    width: 1000,
                    height: 700
                )
        }
    }
}
