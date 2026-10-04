//
//  PresetsView.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 04/10/2026.
//

import SwiftUI

// MARK: - Modelo de Dominio (DTO de Configuración Guardada)
struct SavedConfigDTO: Identifiable, Equatable {
    let id: UUID = UUID()
    var name: String
    var focus: Int
    var breakTime: Int
    var sessions: Int
    // IDs que mapean a tus enums en el backend
    var presetId: Int
    var noiseId: Int
    var freqId: Int
}

struct SavedPresetsView: View {
    // MARK: - Variables de Estado Simuladas
    @State private var savedConfigs: [SavedConfigDTO] = [
        SavedConfigDTO(name: "MORNING CODING", focus: 52, breakTime: 17, sessions: 4, presetId: 1, noiseId: 1, freqId: 1),
        SavedConfigDTO(name: "QUICK READ", focus: 25, breakTime: 5, sessions: 2, presetId: 2, noiseId: 2, freqId: 3),
        SavedConfigDTO(name: "HEAVY DEBUGGING", focus: 90, breakTime: 20, sessions: 3, presetId: 1, noiseId: 1, freqId: 1)
    ]
    
    // Rastrea la configuración actualmente seleccionada
    @State private var selectedConfigId: UUID? = nil
    
    // MARK: - Definición de Colores
    let workBackground = Color(red: 0.11, green: 0.12, blue: 0.13)
    let workAccent = Color(red: 0.95, green: 0.77, blue: 0.62)
    let textDimmedWork = Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.4)
    
    // Se selecciona la primera por defecto al iniciar
    init() {
        _selectedConfigId = State(initialValue: savedConfigs.first?.id)
    }
    
    var body: some View {
        ZStack {
            // Fondo Base
            workBackground
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Cabecera con Navegación
                headerNavigation
                    .padding(.top, 40)
                
                Spacer(minLength: 20)
                
                // Área Central de Tarjetas (Compilación Condicional)
                #if os(macOS)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 30) {
                        ForEach(savedConfigs) { config in
                            PresetCardView(
                                config: config,
                                isSelected: selectedConfigId == config.id,
                                accentColor: workAccent,
                                dimmedColor: textDimmedWork,
                                onSelect: { selectedConfigId = config.id },
                                onEdit: { editConfig(config) }
                            )
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .frame(maxHeight: 300)
                #else
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 25) {
                        ForEach(savedConfigs) { config in
                            PresetCardView(
                                config: config,
                                isSelected: selectedConfigId == config.id,
                                accentColor: workAccent,
                                dimmedColor: textDimmedWork,
                                onSelect: { selectedConfigId = config.id },
                                onEdit: { editConfig(config) }
                            )
                        }
                    }
                    .padding(.horizontal, 30)
                }
                .frame(maxWidth: 400)
                #endif
                
                Spacer(minLength: 20)
                
                // Botón de Inicio (Play)
                Button(action: sendPayloadToBackend) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 32, weight: .black))
                        .foregroundColor(workBackground)
                        .frame(width: 80, height: 80)
                        .background(workAccent)
                        .clipShape(Circle())
                        .shadow(color: workAccent.opacity(0.25), radius: 15, x: 0, y: 8)
                }
                .padding(.bottom, 60)
                // Evita que se presione si no hay nada seleccionado
                .opacity(selectedConfigId == nil ? 0.5 : 1.0)
                .disabled(selectedConfigId == nil)
            }
        }
        // Reconocedor de Gestos para Deslizamiento (Swipe)
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width > threshold {
                        print("Navigating Left -> To Main Timer View")
                    } else if value.translation.width < -threshold {
                        print("Navigating Right -> To Timer Setup View")
                    }
                }
        )
    }
    
    // MARK: - Subvistas y Funciones
    
    private var headerNavigation: some View {
        HStack(spacing: 30) {
            Button(action: { print("Navigating Left -> To Main Timer View") }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(textDimmedWork)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Text("SAVED PRESETS")
                .font(.system(size: 14, weight: .semibold, design: .default))
                .tracking(4)
                .foregroundColor(textDimmedWork)
            
            Button(action: { print("Navigating Right -> To Timer Setup View") }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(textDimmedWork)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    
    private func editConfig(_ config: SavedConfigDTO) {
        // Aquí enviarías este DTO a la vista de configuración para rellenar los datos
        print("Enviando a Timer Setup para editar: \(config.name)")
    }
    
    private func sendPayloadToBackend() {
        guard let selectedId = selectedConfigId,
              let config = savedConfigs.first(where: { $0.id == selectedId }) else { return }
        
        let jsonPayload = """
        {
            "presetName": "\(config.name)",
            "focus": \(config.focus),
            "break": \(config.breakTime),
            "sessions": \(config.sessions),
            "audio": {
                "presetId": \(config.presetId),
                "noiseId": \(config.noiseId),
                "freqId": \(config.freqId)
            }
        }
        """
        print("▶️ Enviando al backend e iniciando temporizador:\n\(jsonPayload)")
    }
}

// MARK: - Tarjeta de Preset Reutilizable
struct PresetCardView: View {
    var config: SavedConfigDTO
    var isSelected: Bool
    var accentColor: Color
    var dimmedColor: Color
    var onSelect: () -> Void
    var onEdit: () -> Void
    
    var body: some View {
        HStack {
            // Información de la tarjeta
            VStack(alignment: .leading, spacing: 12) {
                Text(config.name)
                    .font(.system(size: 16, weight: .bold, design: .default))
                    .tracking(2)
                    .foregroundColor(isSelected ? accentColor : dimmedColor)
                
                HStack(spacing: 15) {
                    Text("\(config.focus)/\(config.breakTime) MIN")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .monospacedDigit()
                    
                    Text("•")
                    
                    Text("\(config.sessions) SESSIONS")
                        .font(.system(size: 12, weight: .medium, design: .default))
                }
                .foregroundColor(isSelected ? accentColor.opacity(0.8) : dimmedColor.opacity(0.6))
            }
            
            Spacer()
            
            // Botón de Edición (Lápiz)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .medium))
                    // El lápiz siempre se ve un poco apagado hasta que seleccionas la tarjeta
                    .foregroundColor(isSelected ? accentColor : dimmedColor.opacity(0.5))
                    .padding(15)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(25)
        // Fondo sutil para enmarcar la tarjeta
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? accentColor : dimmedColor.opacity(0.2), lineWidth: 1.5)
                .background(isSelected ? accentColor.opacity(0.05) : Color.clear)
        )
        // Hace que toda la tarjeta sea cliqueable para seleccionarla
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        // Límites de ancho para mantener consistencia
        .frame(width: 320)
    }
}

// Previsualización
struct SavedPresetsView_Previews: PreviewProvider {
    static var previews: some View {
        SavedPresetsView()
            .frame(width: 400, height: 800) // Cambia el frame para simular macOS vs iOS
    }
}
