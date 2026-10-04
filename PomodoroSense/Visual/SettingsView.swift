//
//  PomodoroSettingsView.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 04/10/2026.
import SwiftUI

// MARK: - Modelos de Dominio (Listos para Backend)

enum AudioPreset: String, CaseIterable {
    case custom = "NONE (CUSTOM)"
    case deepWork = "DEEP WORK"
    case creative = "CREATIVE"
    
    var backendId: Int {
        switch self {
        case .custom: return 0
        case .deepWork: return 1
        case .creative: return 2
        }
    }
}

enum BackgroundNoise: String, CaseIterable {
    case none = "NONE"
    case brown = "BROWN NOISE"
    case pink = "PINK NOISE"
    case white = "WHITE NOISE"
    case purple = "VIOLET NOISE"
    
    var backendId: Int {
        switch self {
        case .none: return 0
        case .brown: return 1
        case .pink: return 2
        case .white: return 3
        case .purple: return 4
        }
    }
}

enum BrainwaveFreq: String, CaseIterable {
    case none = "NONE"
    case gamma40 = "40 HZ (GAMMA)"
    case beta15 = "15 HZ (BETA)"
    case alpha10 = "10 HZ (ALPHA)"
    case theta6 = "6 HZ (THETA)"
    
    var backendId: Int {
        switch self {
        case .none: return 0
        case .gamma40: return 1
        case .beta15: return 2
        case .alpha10: return 3
        case .theta6: return 4
        }
    }
}

// MARK: - Vista Principal de Configuración

struct PomodoroSettingsView: View {
    // Ahora enviamos el objeto DTO directamente, no un String JSON
    // MARK: - Contratos de Comunicación
    var onNavigate: ((AppScreen, PomodoroConfigDTO?) -> Void)?
    var onSave: ((PomodoroConfigDTO) -> Void)?
        
    // Constructor explícito para evitar el error "Extra argument"
    init(
        onNavigate: ((AppScreen, PomodoroConfigDTO?) -> Void)? = nil,
        onSave: ((PomodoroConfigDTO) -> Void)? = nil
    ) {
        self.onNavigate = onNavigate
        self.onSave = onSave
    }
    
    @State private var focusTime: Int = 52
    @State private var breakTime: Int = 17
    @State private var sessions: Int = 7
    
    // Variables de Audio
    @State private var selectedPreset: AudioPreset = .custom
    @State private var selectedNoise: BackgroundNoise = .none
    @State private var selectedFreq: BrainwaveFreq = .none
    
    // Bandera de control para evitar bucles reactivos
    @State private var isProgrammaticChange = false
    
    // Colores
    let workBackground = Color(red: 0.11, green: 0.12, blue: 0.13)
    let workAccent = Color(red: 0.95, green: 0.77, blue: 0.62)
    let textDimmedWork = Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.4)
    
    
    
    var body: some View {
        ZStack {
            workBackground.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("TIMER SETUP")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(4)
                    .foregroundColor(textDimmedWork)
                    .padding(.top, 40)
                
                Spacer()
                
                // MARK: Compilación Condicional de Layout (macOS vs iOS)
                #if os(macOS)
                HStack(spacing: 60) {
                    timeSettingsBlock
                        .frame(width: 320)
                    
                    Divider()
                        .background(textDimmedWork.opacity(0.3))
                        .frame(height: 180)
                    
                    audioSettingsBlock
                        .frame(width: 350)
                }
                .frame(maxWidth: 800)
                #else
                VStack(spacing: 40) {
                    timeSettingsBlock
                        // 1. Restringe cuánto puede expandirse el resorte (acerca los textos)
                        .frame(maxWidth: 300)
                        // 2. Empuja el bloque hacia adentro para despegarlo de los bordes del iPhone
                        .padding(.horizontal, 30)
                    
                    Divider()
                        .background(textDimmedWork.opacity(0.3))
                        .padding(.horizontal, 40)
                    
                    audioSettingsBlock
                        .frame(maxWidth: 300)
                        .padding(.horizontal, 30)
                }
                #endif
                
                Spacer()
                
                // Botón de Inicio
                Button(action: saveConfiguration) {
                    Image(systemName: "recordingtape")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(workBackground)
                        .frame(width: 80, height: 80)
                        .background(workAccent)
                        .clipShape(Circle())
                        .shadow(
                            color: workAccent.opacity(0.25),
                            radius: 15,
                            x: 0,
                            y: 8
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 60)
            }
        }
        // MARK: Lógica Reactiva
        .onChange(of: selectedPreset) { oldValue, newValue in
            guard !isProgrammaticChange else { return }

            isProgrammaticChange = true
            
            switch newValue {
            case .deepWork:
                selectedNoise = .brown
                selectedFreq = .gamma40
            case .creative:
                selectedNoise = .pink
                selectedFreq = .alpha10
            case .custom:
                // No ejecuta acciones. Mantiene los valores existentes en pantalla.
                break
            }
            
            isProgrammaticChange = false
        }
        .onChange(of: selectedNoise) {
            checkCustomState()
        }
        .onChange(of: selectedFreq) {
            checkCustomState()
        }

    }
    
    // MARK: Bloques Modulares de Interfaz
    
    @ViewBuilder
    private var timeSettingsBlock: some View {
        VStack(spacing: 30) {
            SettingRow(title: "FOCUS", value: $focusTime, range: 1...120, accentColor: workAccent, dimmedColor: textDimmedWork)
            SettingRow(title: "BREAK", value: $breakTime, range: 1...60, accentColor: workAccent, dimmedColor: textDimmedWork)
            SettingRow(title: "SESSIONS", value: $sessions, range: 1...20, accentColor: workAccent, dimmedColor: textDimmedWork)
        }
    }
    
    @ViewBuilder
    private var audioSettingsBlock: some View {
        VStack(spacing: 30) {
            CyclicPickerRow(
                title: "PRESET",
                selectedOption: $selectedPreset,
                options: AudioPreset.allCases,
                accentColor: workAccent,
                dimmedColor: textDimmedWork
            )
            
            CyclicPickerRow(
                title: "SOUND",
                selectedOption: $selectedNoise,
                options: BackgroundNoise.allCases,
                accentColor: workAccent,
                dimmedColor: textDimmedWork
            )
            
            CyclicPickerRow(
                title: "WAVES",
                selectedOption: $selectedFreq,
                options: BrainwaveFreq.allCases,
                accentColor: workAccent,
                dimmedColor: textDimmedWork
            )
        }
    }
    
    // Trabaja para el envío del DTO nativo
        private func saveConfiguration() {
            let configuration = PomodoroConfigDTO(
                name: "CUSTOM SETUP", // O el nombre que le des
                focus: focusTime,
                breakTime: breakTime,
                sessions: sessions,
                audio: AudioConfigDTO(
                    presetId: selectedPreset.backendId,
                    noiseId: selectedNoise.backendId,
                    freqId: selectedFreq.backendId
                )
            )
            
            // 1. Emitimos el objeto nativo para que la lógica (ViewModel/Router) lo guarde
            onSave?(configuration)
            
            // 2. Cambiamos de pantalla
            onNavigate?(.savedPresets, nil)
    }
    
    // Evalúa si la combinación manual rompe el preset activo
    private func checkCustomState() {
        guard !isProgrammaticChange else { return }
        
        let isDeepWork = (selectedNoise == .brown && selectedFreq == .gamma40)
        let isCreative = (selectedNoise == .pink && selectedFreq == .alpha10)
        
        isProgrammaticChange = true
        if isDeepWork {
            selectedPreset = .deepWork
        } else if isCreative {
            selectedPreset = .creative
        } else {
            selectedPreset = .custom
        }
        isProgrammaticChange = false
    }
}

// MARK: - Subvistas Reutilizables

struct SettingRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var accentColor: Color
    var dimmedColor: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .default))
                .tracking(2)
                .foregroundColor(dimmedColor)
            
            Spacer(minLength: 10)
            
            HStack(spacing: 12) {
                Button(action: { if value > range.lowerBound { value -= 1 } }) {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(value > range.lowerBound ? accentColor : dimmedColor.opacity(0.2))
                        .padding(10)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                
                Text("\(value)")
                    .font(.system(size: 32, weight: .light, design: .default))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .frame(width: 60, alignment: .center)
                
                Button(action: { if value < range.upperBound { value += 1 } }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(value < range.upperBound ? accentColor : dimmedColor.opacity(0.2))
                        .padding(10)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}

// Componente Genérico para cualquier tipo de Enum
struct CyclicPickerRow<T: Equatable & RawRepresentable>: View where T.RawValue == String {
    var title: String
    @Binding var selectedOption: T
    var options: [T]
    var accentColor: Color
    var dimmedColor: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .default))
                .tracking(2)
                .foregroundColor(dimmedColor)
            
            Spacer(minLength: 10)
            
            HStack(spacing: 0) {
                Button(action: cycleLeft) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accentColor)
                        .padding(10)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                
                Text(selectedOption.rawValue)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .tracking(1)
                    .foregroundColor(.white)
                    .frame(width: 140, alignment: .center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .animation(.easeInOut(duration: 0.2), value: selectedOption.rawValue)
                
                Button(action: cycleRight) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accentColor)
                        .padding(10)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
    
    private func cycleLeft() {
        let currentIndex = options.firstIndex(of: selectedOption) ?? 0
        let previousIndex = currentIndex == 0 ? options.count - 1 : currentIndex - 1
        selectedOption = options[previousIndex]
    }
    
    private func cycleRight() {
        let currentIndex = options.firstIndex(of: selectedOption) ?? 0
        let nextIndex = currentIndex == options.count - 1 ? 0 : currentIndex + 1
        selectedOption = options[nextIndex]
    }
}

// Previsualización
struct PomodoroSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroSettingsView()
            // Simulación visual en Xcode (cambiar altura/ancho no altera la compilación condicional)
            .frame(width: 800, height: 600)
    }
}
