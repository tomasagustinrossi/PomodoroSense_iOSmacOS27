import SwiftUI

// MARK: - Modelo de Dominio (DTO)

struct SavedPresetsView: View {
    // MARK: - Inyección de Dependencia para Navegación
    var onNavigate: ((AppScreen, PomodoroConfigDTO?) -> Void)? = nil
    
    // MARK: - Estado de Datos
        @State private var savedConfigs: [PomodoroConfigDTO] = [
            PomodoroConfigDTO(
                name: "MORNING CODING", focus: 52, breakTime: 17, sessions: 4,
                audio: AudioConfigDTO(presetId: 1, noiseId: 1, freqId: 1)
            ),
            PomodoroConfigDTO(
                name: "QUICK READ", focus: 25, breakTime: 5, sessions: 2,
                audio: AudioConfigDTO(presetId: 2, noiseId: 2, freqId: 3)
            ),
            PomodoroConfigDTO(
                name: "HEAVY DEBUGGING", focus: 90, breakTime: 20, sessions: 3,
                audio: AudioConfigDTO(presetId: 1, noiseId: 1, freqId: 1)
            )
        ]
    
    @State private var selectedConfigId: UUID? = nil
    
    // MARK: - Estado de Búsqueda
    @State private var isSearchActive: Bool = false
    @State private var searchQuery: String = ""
    @FocusState private var isSearchFocused: Bool
    
    // MARK: - Paleta de Colores
    let workBackground = Color(red: 0.11, green: 0.12, blue: 0.13)
    let workAccent = Color(red: 0.95, green: 0.77, blue: 0.62)
    let textDimmedWork = Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.4)
    let destructiveRed = Color(red: 0.90, green: 0.30, blue: 0.30)
    
    // Inicializador sincronizado con el nuevo contrato bidimensional
    init(onNavigate: ((AppScreen, PomodoroConfigDTO?) -> Void)? = nil) {
            self.onNavigate = onNavigate
        }
    
    var filteredConfigs: [PomodoroConfigDTO] {
        if searchQuery.isEmpty {
            return savedConfigs
        } else {
            return savedConfigs.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }
    }
    
    var body: some View {
        ZStack {
            workBackground
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: handleBackgroundTap)
            
            VStack(spacing: 0) {
                // 1. Cabecera Balanceada sin colisiones
                customNavigationBar
                    .padding(.top, 30)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 600)
                
                // 2. Barra de Búsqueda
                if isSearchActive {
                    searchBar
                        .padding(.horizontal, 40)
                        .padding(.top, 15)
                        .frame(maxWidth: 350)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer(minLength: 20)
                
                // 3. Tarjetero Deslizable
                #if os(macOS)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(filteredConfigs) { config in
                            PresetCardView(
                                config: config,
                                isSelected: selectedConfigId == config.id,
                                accentColor: workAccent,
                                dimmedColor: textDimmedWork,
                                destructiveColor: destructiveRed,
                                onSelect: { selectedConfigId = config.id },
                                onEdit: { editConfig(config) },
                                onDelete: { deleteConfig(config) }
                            )
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 160)
                #else
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        ForEach(filteredConfigs) { config in
                            PresetCardView(
                                config: config,
                                isSelected: selectedConfigId == config.id,
                                accentColor: workAccent,
                                dimmedColor: textDimmedWork,
                                destructiveColor: destructiveRed,
                                onSelect: { selectedConfigId = config.id },
                                onEdit: { editConfig(config) },
                                onDelete: { deleteConfig(config) }
                            )
                        }
                    }
                    .padding(.horizontal, 30)
                }
                .frame(maxWidth: 400)
                #endif
                
                Spacer(minLength: 20)
                
                // 4. Botón de Ejecución (Play)
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
                .padding(.bottom, 50)
                .opacity(selectedConfigId == nil ? 0.5 : 1.0)
                .disabled(selectedConfigId == nil)
            }
        }
        .onAppear {
            if selectedConfigId == nil {
                selectedConfigId = savedConfigs.first?.id
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let translation = value.translation
                    #if os(macOS)
                    if abs(translation.height) > 40  { onNavigate?(.mainTimer, nil) }
                    #else
                    if abs(translation.width) > 40 { onNavigate?(.mainTimer, nil) }
                    #endif
                }
        )
    }
    
    // MARK: - Control de Foco
    private func handleBackgroundTap() {
        isSearchFocused = false
        if searchQuery.isEmpty && isSearchActive {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchActive = false
            }
        }
    }
    // MARK: - Enrutadores de Íconos Dinámicos
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
        
        // MARK: - Componentes de Interfaz
        private var customNavigationBar: some View {
            HStack(alignment: .center) {
                
                // Columna Izquierda: Botón de Retorno
                HStack {
                    Button {
                        // Sin acción
                    } label: {
                        Image(systemName: backIconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(textDimmedWork)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain).hidden()
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Columna Central: Título
                Text("SAVED PRESETS")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .tracking(4)
                    .foregroundColor(textDimmedWork)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                
                // Columna Derecha: Lupa, Add y Siguiente
                HStack(spacing: 12) {
                    Spacer()
                    
                    Button(action: toggleSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isSearchActive ? workAccent : textDimmedWork)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: requestNewPreset) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(workAccent)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        onNavigate?(.mainTimer, nil)
                    } label: {
                        Image(systemName: forwardIconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(textDimmedWork)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                
            }
        }
    
    private var searchBar: some View {
        HStack {
            TextField("Search preset...", text: $searchQuery)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .accentColor(workAccent)
                .disableAutocorrection(true)
                .focused($isSearchFocused)
                .textFieldStyle(.plain)
                .onChange(of: searchQuery) { oldValue, newValue in
                                    print("🔍 Intent: ViewModel.filterPresets(by: \"\(newValue)\")")
                                }
            
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(textDimmedWork)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
    
    // MARK: - Despachador Universal de Navegación
    private func executeAndNavigate() {
            guard let id = selectedConfigId, let config = savedConfigs.first(where: { $0.id == id }) else {
                onNavigate?(.mainTimer, nil)
                return
            }
            
            // ¡Magia! Como ya unificamos los modelos, config ya ES un PomodoroConfigDTO
            print("▶️ Despachando DTO nativo al Timer: \(config.name)")
            onNavigate?(.mainTimer, config)
        }
    
    // MARK: - Rutinas Adicionales
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
            print("➕ Intent: Navegar a TimerSetup para crear nueva configuración")
            onNavigate?(.timerSetup, nil)
        }
    private func editConfig(_ config: PomodoroConfigDTO) {
        print("✏ Editar: \(config.name)")
        onNavigate?(.timerSetup, nil)
    }
    
    private func deleteConfig(_ config: PomodoroConfigDTO) {
        withAnimation {
            savedConfigs.removeAll { $0.id == config.id }
            if selectedConfigId == config.id {
                selectedConfigId = savedConfigs.first?.id
            }
        }
        print("🗑️ Intent: ViewModel.deleteConfig(id: \(config.id))")
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? destructiveColor.opacity(0.8) : dimmedColor.opacity(0.3))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? accentColor : dimmedColor.opacity(0.15), lineWidth: 1.5)
                .background(isSelected ? accentColor.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .frame(width: 250)
    }
    
    private func decodeNoise(_ id: Int) -> String {
        switch id {
        case 1: return "BROWN NOISE"
        case 2: return "PINK NOISE"
        case 3: return "WHITE NOISE"
        case 4: return "VIOLET NOISE"
        default: return "NO NOISE"
        }
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

// Previsualización
struct SavedPresetsView_Previews: PreviewProvider {
    static var previews: some View {
        SavedPresetsView(onNavigate: { destination, payload in
            // Extraemos el nombre si existe, de lo contrario mostramos "Ninguno"
            let payloadInfo = payload?.name ?? "Ninguno"
            print("Preview navegando a \(destination) con Payload:\n\(payloadInfo)")
        })
        .frame(width: 400, height: 800)
    }
}
