//
//  PomodoroSettingsView.swift
//  PomodoroSense
//

import SwiftUI

// MARK: - Modelos de Dominio

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

private var settingsBlockSpacing: CGFloat {
    #if os(iOS)
    return 16
    #else
    return 20
    #endif
}

enum BackgroundNoise: String, CaseIterable {
    case none = "NONE"
    case brown = "BROWN NOISE"
    case pink = "PINK NOISE"
    case white = "WHITE NOISE"
    case purple = "VIOLET NOISE"
    case nature = "NATURE"

    var backendId: Int {
        switch self {
        case .none: return 0
        case .brown: return 1
        case .pink: return 2
        case .white: return 3
        case .purple: return 4
        case .nature: return 5
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

enum NumberField: Int, Hashable {
    case focus = 0
    case breakTime = 1
    case sessions = 2
}

// MARK: - Vista Principal

struct PomodoroSettingsView: View {

    // MARK: - Props inyectadas
    var onNavigate: ((AppScreen, PomodoroConfigDTO?) -> Void)?
    var onSave: ((PomodoroConfigDTO) -> Void)?

    // MARK: - Estado persistente
    private let editingId: UUID
    @State private var presetName: String
    @State private var focusTime: Int
    @State private var breakTime: Int
    @State private var sessions: Int

    @State private var selectedPreset: AudioPreset
    @State private var selectedFreq: BrainwaveFreq
    @State private var selectedNoise: AmbientSound

    @State private var isProgrammaticChange = false

    // MARK: - Foco y teclado (macOS)
    @State private var activeZone: TimerSetupZone = .name
    @FocusState private var isNameFocused: Bool

    /// Draft del número que se está tipeando. Compartido por el padre:
    /// el monitor NSEvent escribe acá y el `SettingRow` lo muestra.
    /// Cuando no hay edición, es "".
    @State private var numberDraft: String = ""

    /// Qué campo numérico está en modo edición ahora mismo, o `nil`.
    @State private var editingNumberField: NumberField? = nil

    @State private var showDiscardConfirm: Bool = false
    @State private var initialSnapshot: PomodoroConfigDTO? = nil
    // Señales de shake por campo. Se incrementan desde el padre cuando
    // un Enter no produjo cambios, disparando una micro-animación de
    // "shake" horizontal en el `SettingRow` correspondiente.
    @State private var focusShakeSignal: Int = 0
    @State private var breakShakeSignal: Int = 0
    @State private var sessionsShakeSignal: Int = 0

    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif

    // MARK: - Paleta
    let workBackground = Color(red: 0.11, green: 0.12, blue: 0.13)
    let workAccent = Color(red: 0.95, green: 0.77, blue: 0.62)
    let textDimmedWork = Color(red: 0.95, green: 0.77, blue: 0.62).opacity(0.4)

    // MARK: - Init

    init(
        initialConfig: PomodoroConfigDTO? = nil,
        onNavigate: ((AppScreen, PomodoroConfigDTO?) -> Void)? = nil,
        onSave: ((PomodoroConfigDTO) -> Void)? = nil
    ) {
        self.onNavigate = onNavigate
        self.onSave = onSave

        self.editingId = initialConfig?.id ?? UUID()

        _presetName = State(initialValue: initialConfig?.name ?? "")
        _focusTime = State(initialValue: initialConfig?.focus ?? 30)
        _breakTime = State(initialValue: initialConfig?.breakTime ?? 10)
        _sessions = State(initialValue: initialConfig?.sessions ?? 5)

        let initialPreset = AudioPreset.allCases
            .first(where: { $0.backendId == initialConfig?.audio.presetId }) ?? .custom
        let initialNoise = AmbientSound.from(id: initialConfig?.audio.noiseId ?? 0)
        let initialFreq = BrainwaveFreq.allCases
            .first(where: { $0.backendId == initialConfig?.audio.freqId }) ?? .none

        _selectedPreset = State(initialValue: initialPreset)
        _selectedNoise = State(initialValue: initialNoise)
        _selectedFreq = State(initialValue: initialFreq)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            workBackground
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                    activeZone = .name
                    isNameFocused = false
                }

            VStack(spacing: 0) {
                headerBar
                scrollContent
                saveButton
            }
        }
        .onAppear(perform: onViewAppear)
        .onDisappear(perform: onViewDisappear)
        .onChange(of: activeZone) { _, newZone in
            syncFocusToZone(newZone)
        }
        .onChange(of: selectedPreset) { _, newValue in
            applyPresetSideEffects(for: newValue)
        }
        .onChange(of: selectedNoise) { _, _ in checkCustomState() }
        .onChange(of: selectedFreq) { _, _ in checkCustomState() }
        .alert("Discard changes?", isPresented: $showDiscardConfirm) {
            Button("Keep editing", role: .cancel) { }
            Button("Discard", role: .destructive) {
                onNavigate?(.savedPresets, nil)
            }
        } message: {
            Text("You have unsaved changes. If you leave now, they will be lost.")
        }
    }

    // MARK: - Sub-vistas

    private var headerBar: some View {
        HStack {
            Button(action: { attemptClose() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(textDimmedWork)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()

            Text("TIMER SETUP")
                .font(.system(size: 14, weight: .semibold, design: .default))
                .tracking(4)
                .foregroundColor(textDimmedWork)

            Spacer()

            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 40) {
                nameInput

                #if os(macOS)
                HStack(spacing: 60) {
                    timeSettingsBlock.frame(width: 320)
                    Divider()
                        .background(textDimmedWork.opacity(0.3))
                        .frame(height: 180)
                    audioSettingsBlock.frame(width: 350)
                }
                .frame(maxWidth: 800)
                #else
                VStack(spacing: 24) { // <-- Reducido de 40 a 24
                    timeSettingsBlock
                        .frame(maxWidth: 300)
                        .padding(.horizontal, 20) // <-- Reducido de 30 a 20

                    Divider()
                        .background(textDimmedWork.opacity(0.3))
                        .padding(.horizontal, 30) // <-- Reducido de 40 a 30

                    audioSettingsBlock
                        .frame(maxWidth: 300)
                        .padding(.horizontal, 20) // <-- Reducido de 30 a 20
                }
                #endif
            }
            .padding(.bottom, 12) // <-- Reducido de 20 a 12
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
    }

    private var nameInput: some View {
        VStack(spacing: 6) {
            Text("PRESET NAME")
                .font(.system(size: 10, weight: .bold, design: .default))
                .tracking(2)
                .foregroundColor(workAccent)
                .opacity(isNameFocused ? 1.0 : 0.0)
                .offset(y: isNameFocused ? 0 : 5)
                .animation(.easeOut(duration: 0.2), value: isNameFocused)

            TextField("UNTITLED PRESET", text: $presetName)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .light, design: .default)) // <-- Reducido de 16 a 15
                .tracking(3)
                .foregroundColor(isNameFocused ? workAccent : .white)
                .multilineTextAlignment(.center)
                .autocorrectionDisabled(true)
                .focused($isNameFocused)
                .submitLabel(.next)
                .onSubmit {
                    isNameFocused = false
                    activeZone = .focus
                }
                .padding(.vertical, 12) // <-- Reducido de 16 a 12
                .padding(.horizontal, 16) // <-- Reducido de 20 a 16
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isNameFocused ? workAccent : textDimmedWork.opacity(0.3),
                            lineWidth: isNameFocused ? 1.5 : 0.5
                        )
                )
                .scaleEffect(isNameFocused ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isNameFocused)
                .frame(maxWidth: 350)
        }
        .padding(.top, 12) // <-- Reducido de 20 a 12
    }

    private var saveButton: some View {
        Button(action: saveConfiguration) {
            CustomFloppyIcon(color: workBackground)
                #if os(iOS)
                .frame(width: 60, height: 60) // <-- Solo iOS
                #else
                .frame(width: 80, height: 80) // <-- Mac se queda igual
                #endif
                .background(workAccent)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(workAccent, lineWidth: activeZone == .save ? 3 : 0)
                        .padding(-4)
                )
                .shadow(
                    color: workAccent.opacity(activeZone == .save ? 0.55 : 0.25),
                    radius: activeZone == .save ? 22 : 15,
                    x: 0, y: 8
                )
                .scaleEffect(isNameFocused ? 0.9 : 1.0)
                .animation(.spring(), value: isNameFocused)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: activeZone)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .padding(.bottom, 16) // <-- Solo iOS
        #else
        .padding(.bottom, 40) // <-- Mac se queda igual
        #endif
        .accessibilityLabel("Save preset")
    }

    // MARK: - Bloques de settings

    @ViewBuilder
    private var timeSettingsBlock: some View {
        VStack(spacing: settingsBlockSpacing) {
            SettingRow(
                title: "FOCUS",
                value: $focusTime,
                range: 1...60,
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                isActive: activeZone == .focus,
                isEditing: editingNumberField == .focus,
                draft: $numberDraft,
                onTapActivate: { activateZone(.focus) },
                onCommit: { _ = commitNumberEditing() },
                shakeSignal: focusShakeSignal
            )
            SettingRow(
                title: "BREAK",
                value: $breakTime,
                range: 1...60,
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                isActive: activeZone == .breakTime,
                isEditing: editingNumberField == .breakTime,
                draft: $numberDraft,
                onTapActivate: { activateZone(.breakTime) },
                onCommit: { _ = commitNumberEditing() },
                shakeSignal: breakShakeSignal
            )
            SettingRow(
                title: "SESSIONS",
                value: $sessions,
                range: 1...40,
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                isActive: activeZone == .sessions,
                isEditing: editingNumberField == .sessions,
                draft: $numberDraft,
                onTapActivate: { activateZone(.sessions) },
                onCommit: { _ = commitNumberEditing() },
                shakeSignal: sessionsShakeSignal
            )
        }
    }

    @ViewBuilder
    private var audioSettingsBlock: some View {
        VStack(spacing: settingsBlockSpacing) {
            CyclicPickerRow(
                title: "PRESET",
                selectedOption: $selectedPreset,
                options: AudioPreset.allCases,
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                label: { $0.rawValue },
                isActive: activeZone == .preset,
                onTapActivate: { activeZone = .preset }
            )

            CyclicPickerRow(
                title: "SOUND",
                selectedOption: $selectedNoise,
                options: AmbientSound.allCases,
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                label: { $0.displayName },
                isActive: activeZone == .sound,
                onTapActivate: { activeZone = .sound }
            )

            CyclicPickerRow(
                title: "WAVES",
                selectedOption: $selectedFreq,
                options: BrainwaveFreq.allCases,
                accentColor: workAccent,
                dimmedColor: textDimmedWork,
                label: { $0.rawValue },
                isActive: activeZone == .waves,
                onTapActivate: { activeZone = .waves }
            )
        }
    }

    // MARK: - Lifecycle

    private func onViewAppear() {
        initialSnapshot = currentConfigSnapshot()

        #if os(macOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isNameFocused = true
        }
        installKeyMonitor()
        #endif
    }

    private func onViewDisappear() {
        #if os(macOS)
        removeKeyMonitor()
        #endif
    }

    private func syncFocusToZone(_ zone: TimerSetupZone) {
        // Cambiar de zona cancela cualquier edición numérica en curso.
        // Si había un draft, se descarta (no se commitea) para evitar
        // sorpresas al navegar rápido.
        if editingNumberField != nil && numberField(for: zone) != editingNumberField {
            editingNumberField = nil
            numberDraft = ""
        }

        switch zone {
        case .name:
            isNameFocused = true
        case .focus, .breakTime, .sessions, .preset, .sound, .waves, .save:
            isNameFocused = false
        }
    }

    private func activateZone(_ zone: TimerSetupZone) {
        #if os(iOS)
        // Si veníamos editando otro campo numérico, commitearlo antes de
        // cambiar de zona. En macOS el commit lo maneja el key monitor.
        if editingNumberField != nil, numberField(for: zone) != editingNumberField {
            _ = commitNumberEditing()
        }
        #endif

        activeZone = zone

        #if os(iOS)
        if let field = numberField(for: zone), editingNumberField != field {
            // Bajar foco del nombre y abrir el campo numérico con el
            // teclado. Draft vacío para que el placeholder muestre
            // el valor actual sin tener que borrarlo a mano.
            isNameFocused = false
            numberDraft = ""
            editingNumberField = field
        }
        #endif
    }

    private func currentConfigSnapshot() -> PomodoroConfigDTO {
        PomodoroConfigDTO(
            id: editingId,
            name: presetName,
            focus: focusTime,
            breakTime: breakTime,
            sessions: sessions,
            audio: AudioConfigDTO(
                presetId: selectedPreset.backendId,
                noiseId: selectedNoise.rawValue,
                freqId: selectedFreq.backendId
            )
        )
    }

    // MARK: - Edición

    private func dismissKeyboard() {
        #if os(iOS)
        // Tap fuera del campo = "terminé de escribir" → commitear.
        // En macOS, Escape cancela y Enter commitea; el tap fuera
        // nunca edita un número (no hay keyboard monitor activo).
        if editingNumberField != nil {
            _ = commitNumberEditing()
        }
        #endif
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isNameFocused = false
            editingNumberField = nil
            numberDraft = ""
        }
    }

    private func saveConfiguration() {
        commitNumberEditing()
        dismissKeyboard()

        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmedName.isEmpty ? "CUSTOM PRESET" : trimmedName

        let configuration = PomodoroConfigDTO(
            id: editingId,
            name: safeName.uppercased(),
            focus: focusTime,
            breakTime: breakTime,
            sessions: sessions,
            audio: AudioConfigDTO(
                presetId: selectedPreset.backendId,
                noiseId: selectedNoise.rawValue,
                freqId: selectedFreq.backendId
            )
        )
        onSave?(configuration)
    }

    private func attemptClose() {
        handleEscape()
    }

    private func applyPresetSideEffects(for newValue: AudioPreset) {
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
            break
        }
        isProgrammaticChange = false
    }

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

    // MARK: - Helpers de draft numérico

    private func numberField(for zone: TimerSetupZone) -> NumberField? {
        switch zone {
        case .focus: return .focus
        case .breakTime: return .breakTime
        case .sessions: return .sessions
        default: return nil
        }
    }

    private func range(for field: NumberField) -> ClosedRange<Int> {
        switch field {
        case .focus, .breakTime: return 1...60
        case .sessions: return 1...40
        }
    }

    private func value(for field: NumberField) -> Int {
        switch field {
        case .focus: return focusTime
        case .breakTime: return breakTime
        case .sessions: return sessions
        }
    }

    private func setValue(_ newValue: Int, for field: NumberField) {
        switch field {
        case .focus: focusTime = newValue
        case .breakTime: breakTime = newValue
        case .sessions: sessions = newValue
        }
    }

    /// Confirma el draft actual: parsea, clampea y escribe el valor.
    /// Limpia `editingNumberField` y `numberDraft`.
    /// Confirma el draft actual: parsea, clampea y escribe el valor.
    /// Devuelve `true` si el valor NO cambió (para disparar el shake).
    @discardableResult
    private func commitNumberEditing() -> Bool {
        guard let field = editingNumberField else { return false }

        let before = value(for: field)

        if !numberDraft.isEmpty, let parsed = Int(numberDraft) {
            let clamped = min(max(parsed, range(for: field).lowerBound),
                              range(for: field).upperBound)
            setValue(clamped, for: field)
        }

        editingNumberField = nil
        numberDraft = ""

        return value(for: field) == before
    }

    // MARK: - Teclado

    private func handleEnterKey() {
        if activeZone == .save {
            saveConfiguration()
            return
        }

        if let field = numberField(for: activeZone) {
            if editingNumberField == field {
                let unchanged = commitNumberEditing()
                if unchanged {
                    // Enter sin cambios → shake sutil y avanzamos igual.
                    triggerShake(for: field)
                }
                activeZone = TimerSetupKeyboard.cycle(from: activeZone, forward: true)
            } else {
                editingNumberField = field
                numberDraft = ""
            }
            return
        }

        activeZone = TimerSetupKeyboard.cycle(from: activeZone, forward: true)
    }

    private func triggerShake(for field: NumberField) {
        switch field {
        case .focus:      focusShakeSignal += 1
        case .breakTime:  breakShakeSignal += 1
        case .sessions:   sessionsShakeSignal += 1
        }
    }

    private func handleArrow(offset: Int) {
        // Si estamos editando el numérico de esta misma zona, las
        // flechas mueven el valor en vivo (sobrescriben el draft).
        if let field = numberField(for: activeZone), editingNumberField == field {
            let current = Int(numberDraft) ?? value(for: field)
            let next = TimerSetupKeyboard.clampNumeric(
                value: current, offset: offset, range: range(for: field))
            numberDraft = "\(next)"
            return
        }

        switch activeZone {
        case .focus:
            focusTime = TimerSetupKeyboard.clampNumeric(
                value: focusTime, offset: offset, range: 1...60)
        case .breakTime:
            breakTime = TimerSetupKeyboard.clampNumeric(
                value: breakTime, offset: offset, range: 1...60)
        case .sessions:
            sessions = TimerSetupKeyboard.clampNumeric(
                value: sessions, offset: offset, range: 1...40)
        case .preset:
            let options = AudioPreset.allCases
            let idx = options.firstIndex(of: selectedPreset) ?? 0
            selectedPreset = options[TimerSetupKeyboard.movePickerIndex(
                current: idx, count: options.count, offset: offset)]
        case .sound:
            let options = AmbientSound.allCases
            let idx = options.firstIndex(of: selectedNoise) ?? 0
            selectedNoise = options[TimerSetupKeyboard.movePickerIndex(
                current: idx, count: options.count, offset: offset)]
        case .waves:
            let options = BrainwaveFreq.allCases
            let idx = options.firstIndex(of: selectedFreq) ?? 0
            selectedFreq = options[TimerSetupKeyboard.movePickerIndex(
                current: idx, count: options.count, offset: offset)]
        case .name, .save:
            break
        }
    }

    private func handleVerticalArrow(forward: Bool) {
        // Igual que Tab: commitea el draft y mueve zona.
        commitNumberEditing()
        activeZone = TimerSetupKeyboard.cycle(from: activeZone, forward: forward)
    }

    private func handleEscape() {
        // Escape cancela la edición en curso sin commitear.
        if editingNumberField != nil {
            editingNumberField = nil
            numberDraft = ""
            return
        }

        // Fallback: si por algún motivo `initialSnapshot` no se seteó,
        // lo calculamos ahora para no saltear la confirmación.
        let snapshot = initialSnapshot ?? currentConfigSnapshot()

        if isDirty(against: snapshot) {
            showDiscardConfirm = true
        } else {
            onNavigate?(.savedPresets, nil)
        }
    }
    
    private func isDirty(against snapshot: PomodoroConfigDTO) -> Bool {
        let current = currentConfigSnapshot()
        return current.name != snapshot.name
            || current.focus != snapshot.focus
            || current.breakTime != snapshot.breakTime
            || current.sessions != snapshot.sessions
            || current.audio != snapshot.audio
    }

    #if os(macOS)
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if showDiscardConfirm { return event }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let blocked: NSEvent.ModifierFlags = [.command, .option, .control]
            let hasBlocked = !mods.intersection(blocked).isEmpty

            // ── Manejo prioritario: si la zona activa es numérica. ──
            // Capturamos dígitos y backspace ACÁ para que el tipeo
            // funcione sin necesidad de activar un TextField con foco.
            if let field = numberField(for: activeZone), !hasBlocked {
                let chars = event.charactersIgnoringModifiers ?? ""

                // Dígito 0-9
                if chars.count == 1,
                   let scalar = chars.unicodeScalars.first,
                   CharacterSet.decimalDigits.contains(scalar) {

                    // Arrancar edición si no estaba activa.
                    if editingNumberField != field {
                        editingNumberField = field
                        numberDraft = ""
                    }
                    // Cap defensivo: no dejar crecer sin límite.
                    if numberDraft.count < 4 {
                        numberDraft.append(chars)
                    }
                    return nil
                }

                // Backspace (keyCode 51 = delete, 117 = forward delete)
                if event.keyCode == 51 {
                    if editingNumberField == field {
                        if !numberDraft.isEmpty {
                            numberDraft.removeLast()
                        }
                        return nil
                    }
                    // Si no estaba editando, no hacemos nada — que
                    // pase el evento por si el usuario está en el name.
                    return event
                }
            }

            // ── Navegación y comandos. ──

            // Tab / Shift+Tab
            if event.keyCode == 48 && !hasBlocked {
                commitNumberEditing()
                let forward = !mods.contains(.shift)
                activeZone = TimerSetupKeyboard.cycle(from: activeZone, forward: forward)
                return nil
            }

            // Return / Enter
            if (event.keyCode == 36 || event.keyCode == 76) && !hasBlocked {
                handleEnterKey()
                return nil
            }

            // ← / →
            if event.keyCode == 123 && !hasBlocked {
                handleArrow(offset: -1)
                return nil
            }
            if event.keyCode == 124 && !hasBlocked {
                handleArrow(offset: 1)
                return nil
            }

            // ↑ / ↓
            if event.keyCode == 126 && !hasBlocked {
                handleVerticalArrow(forward: false)
                return nil
            }
            if event.keyCode == 125 && !hasBlocked {
                handleVerticalArrow(forward: true)
                return nil
            }

            // Escape
            if event.keyCode == 53 && !hasBlocked {
                handleEscape()
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }
    #endif
}

// MARK: - Diseño Vectorial de Disquete Puro

struct CustomFloppyIcon: View {
    var color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(color, lineWidth: 2.5)
                .frame(width: 32, height: 32)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 20, height: 12)
                .offset(y: 8)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .stroke(color, lineWidth: 2)
                .frame(width: 16, height: 10)
                .offset(y: -11)

            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 6)
                .offset(x: 3, y: -11)
        }
    }
}

// MARK: - ContinuousButtonStyle

struct ContinuousButtonStyle: ButtonStyle {
    var isAtLimit: Bool
    var accentColor: Color
    var action: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        ContinuousButtonBody(
            configuration: configuration,
            isAtLimit: isAtLimit,
            accentColor: accentColor,
            action: action
        )
    }
}

private struct ContinuousButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isAtLimit: Bool
    let accentColor: Color
    let action: () -> Void

    @State private var timer: Timer?

    var body: some View {
        configuration.label
            .foregroundColor(isAtLimit ? .black.opacity(0.8) : accentColor)
            .scaleEffect(configuration.isPressed && !isAtLimit ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    if isAtLimit { return }
                    action()
                    startRepeating()
                } else {
                    stopRepeating()
                }
            }
            .onChange(of: isAtLimit) { _, atLimit in
                if atLimit { stopRepeating() }
            }
            .onDisappear { stopRepeating() }
    }

    private func startRepeating() {
        stopRepeating()
        let action = self.action
        let newTimer = Timer(timeInterval: 0.12, repeats: true) { _ in
            DispatchQueue.main.async {
                action()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopRepeating() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Fila de Ajustes

struct SettingRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var accentColor: Color
    var dimmedColor: Color
    var isActive: Bool
    var isEditing: Bool
    @Binding var draft: String
    var onTapActivate: () -> Void
    var onCommit: () -> Void = {}
    var shakeSignal: Int = 0

    @FocusState private var isFieldFocused: Bool

    // MARK: - Estilos dinámicos (Mac se mantiene, iOS se achica)
    private var titleFontSize: CGFloat {
        #if os(iOS)
        return 13
        #else
        return 14
        #endif
    }
    
    private var hStackSpacing: CGFloat {
        #if os(iOS)
        return 8
        #else
        return 12
        #endif
    }
    
    private var paddingVertical: CGFloat {
        #if os(iOS)
        return 4
        #else
        return 6
        #endif
    }
    
    private var paddingHorizontal: CGFloat {
        #if os(iOS)
        return 8
        #else
        return 10
        #endif
    }
    
    private var valueFontSize: CGFloat {
        #if os(iOS)
        return 26
        #else
        return 32
        #endif
    }
    
    private var valueFrameWidth: CGFloat {
        #if os(iOS)
        return 50
        #else
        return 60
        #endif
    }
    
    private var valueFrameHeight: CGFloat {
        #if os(iOS)
        return 36
        #else
        return 44
        #endif
    }
    
    private var buttonFontSize: CGFloat {
        #if os(iOS)
        return 16
        #else
        return 18
        #endif
    }
    
    private var buttonPadding: CGFloat {
        #if os(iOS)
        return 8
        #else
        return 10
        #endif
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: titleFontSize, weight: .medium, design: .default))
                .tracking(2)
                .foregroundColor(dimmedColor)
            
            Spacer(minLength: 10)
            
            HStack(spacing: hStackSpacing) {
                minusButton
                valueDisplay
                plusButton
            }
        }
        .padding(.vertical, paddingVertical)
        .padding(.horizontal, paddingHorizontal)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTapActivate()
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { isFieldFocused = false }
        }
    }

    private var displayText: String {
        if isEditing, !draft.isEmpty { return draft }
        return "\(value)"
    }

    @ViewBuilder
    private var valueDisplay: some View {
        #if os(iOS)
        if isEditing {
            iosEditingField
        } else {
            displayButton
        }
        #else
        displayButton
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var iosEditingField: some View {
        TextField("\(value)", text: $draft)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: valueFontSize, weight: .light, design: .default))
            .monospacedDigit()
            .foregroundColor(accentColor)
            .tint(accentColor)
            .frame(width: valueFrameWidth, height: valueFrameHeight)
            .focused($isFieldFocused)
            .onAppear {
                // Delay corto: asegura que el TextField esté en el
                // view tree antes de pedir foco (si no, iOS no abre
                // el teclado).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFieldFocused = true
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFieldFocused = false
                        onCommit()
                    }
                    .foregroundColor(accentColor)
                    .fontWeight(.semibold)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(accentColor)
                    .frame(height: 1)
                    .offset(y: 6)
            }
    }
    #endif

    private var displayButton: some View {
        Button(action: onTapActivate) {
            Text(displayText)
                .font(.system(size: valueFontSize, weight: .light, design: .default))
                .monospacedDigit()
                .foregroundColor(isEditing ? accentColor : .white)
                .frame(width: valueFrameWidth, alignment: .center)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.10), value: displayText)
                .animation(.easeInOut(duration: 0.12), value: isEditing)
                .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeSignal) { view, offset in
                    view.offset(x: offset)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0, duration: 0.0)
                        LinearKeyframe(-5, duration: 0.06)
                        LinearKeyframe(5, duration: 0.06)
                        LinearKeyframe(-3, duration: 0.05)
                        LinearKeyframe(3, duration: 0.05)
                        LinearKeyframe(0, duration: 0.07)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: valueFrameWidth, height: valueFrameHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accentColor)
                .frame(height: 1)
                .offset(y: 6)
                .opacity(isEditing ? 1 : 0)
                .scaleEffect(x: isEditing ? 1 : 0.55, anchor: .center)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isEditing)
        }
        .accessibilityLabel("\(title) value \(value)")
    }

    private var minusButton: some View {
        Button(action: {}) {
            Image(systemName: "minus")
                .font(.system(size: buttonFontSize, weight: .bold))
                .padding(buttonPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(ContinuousButtonStyle(
            isAtLimit: value <= range.lowerBound,
            accentColor: accentColor,
            action: { if value > range.lowerBound { value -= 1 } }
        ))
        .accessibilityLabel("Decrease \(title)")
    }

    private var plusButton: some View {
        Button(action: {}) {
            Image(systemName: "plus")
                .font(.system(size: buttonFontSize, weight: .bold))
                .padding(buttonPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(ContinuousButtonStyle(
            isAtLimit: value >= range.upperBound,
            accentColor: accentColor,
            action: { if value < range.upperBound { value += 1 } }
        ))
        .accessibilityLabel("Increase \(title)")
    }
}

// MARK: - Selector Cíclico

struct CyclicPickerRow<T: Equatable & CaseIterable>: View {
    var title: String
    @Binding var selectedOption: T
    var options: [T]
    var accentColor: Color
    var dimmedColor: Color
    var label: (T) -> String = { String(describing: $0) }
    var isActive: Bool = false
    var onTapActivate: (() -> Void)? = nil

    // MARK: - Estilos dinámicos (Mac se mantiene, iOS se achica)
    private var titleFontSize: CGFloat {
        #if os(iOS)
        return 13
        #else
        return 14
        #endif
    }
    
    private var chevronFontSize: CGFloat {
        #if os(iOS)
        return 12
        #else
        return 14
        #endif
    }
    
    private var chevronPadding: CGFloat {
        #if os(iOS)
        return 8
        #else
        return 10
        #endif
    }
    
    private var labelFontSize: CGFloat {
        #if os(iOS)
        return 11
        #else
        return 13
        #endif
    }
    
    private var labelFrameWidth: CGFloat {
        #if os(iOS)
        return 120
        #else
        return 140
        #endif
    }
    
    private var paddingVertical: CGFloat {
        #if os(iOS)
        return 4
        #else
        return 6
        #endif
    }
    
    private var paddingHorizontal: CGFloat {
        #if os(iOS)
        return 8
        #else
        return 10
        #endif
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: titleFontSize, weight: .medium, design: .default))
                .tracking(2)
                .foregroundColor(dimmedColor)

            Spacer(minLength: 10)

            HStack(spacing: 0) {
                Button(action: cycleLeft) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: chevronFontSize, weight: .bold))
                        .foregroundColor(accentColor)
                        .padding(chevronPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(label(selectedOption))
                    .font(.system(size: labelFontSize, weight: .medium, design: .default))
                    .tracking(1)
                    .foregroundColor(.white)
                    .frame(width: labelFrameWidth, alignment: .center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .animation(.easeInOut(duration: 0.2), value: label(selectedOption))

                Button(action: cycleRight) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: chevronFontSize, weight: .bold))
                        .foregroundColor(accentColor)
                        .padding(chevronPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, paddingVertical)
        .padding(.horizontal, paddingHorizontal)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTapActivate?()
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

// MARK: - Preview

struct PomodoroSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroSettingsView()
            .frame(width: 800, height: 600)
    }
}
