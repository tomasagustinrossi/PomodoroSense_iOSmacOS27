import SwiftUI

// MARK: - Ecualizador conectado al TimerViewModel
//
// - Recibe el TimerViewModel y le aplica los cambios en vivo.
// - Cambiar noiseId actualiza el tema visual (colores) sin resetear el cronómetro.
// - Cambiar freqId NO toca el tema visual.
// - Al cerrarse, llama a `onSave` para persistir en el repositorio de presets.
// - Ahora es una vista overlay (no sheet) para permitir dismiss al tocar fuera en macOS.

import SwiftUI

struct EqualizerSheetView: View {
    var initialNoiseId: Int
    var initialFreqId: Int

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color

    /// Se dispara cada vez que el usuario cambia ruido o frecuencia.
    var onNoiseChanged: (Int) -> Void
    var onFreqChanged: (Int) -> Void

    /// Se dispara al cerrar (para persistir si aplica).
    var onSave: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var selectedNoiseId: Int
    @State private var selectedFreqId: Int
    @State private var noiseVolume: Double
    @State private var freqVolume: Double
    @State private var didLoadInitialState = false

    init(
        initialNoiseId: Int,
        initialFreqId: Int,
        accentColor: Color,
        dimmedColor: Color,
        backgroundColor: Color,
        onNoiseChanged: @escaping (Int) -> Void,
        onFreqChanged: @escaping (Int) -> Void,
        onSave: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.initialNoiseId = initialNoiseId
        self.initialFreqId = initialFreqId
        self.accentColor = accentColor
        self.dimmedColor = dimmedColor
        self.backgroundColor = backgroundColor
        self.onNoiseChanged = onNoiseChanged
        self.onFreqChanged = onFreqChanged
        self.onSave = onSave
        self.onDismiss = onDismiss

        _selectedNoiseId = State(initialValue: initialNoiseId)
        _selectedFreqId  = State(initialValue: initialFreqId)
        _noiseVolume = State(initialValue: Double(AudioManager.shared.getNoiseVolume(id: initialNoiseId)))
        _freqVolume  = State(initialValue: Double(AudioManager.shared.getFreqVolume(id: initialFreqId)))
    }

    var body: some View {
        ZStack {
            backgroundColor

            VStack(spacing: 24) {
                header

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 30) { equalizerContent }
                    VStack(spacing: 30) { equalizerContent }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .padding(.bottom, 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        #if os(macOS)
        .onExitCommand { dismissWithSave() }
        #endif
    }

    private func dismissWithSave() {
        onSave?()
        onDismiss?()
    }

    private var header: some View {
        HStack {
            Text("AUDIO EQUALIZER")
                .font(.system(size: 13, weight: .bold))
                .tracking(4)
                .foregroundColor(dimmedColor)

            Spacer()

            Button(action: dismissWithSave) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(dimmedColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    @ViewBuilder
    private var equalizerContent: some View {
        noisePanel
        freqPanel
    }

    // MARK: - Noise

    private var noisePanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SOUND")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundColor(dimmedColor)

            noiseSelector

            if selectedNoiseId != 0 {
                AppleFluidSlider(
                    value: Binding(
                        get: { noiseVolume },
                        set: { newValue in
                            noiseVolume = newValue
                            AudioManager.shared.setNoiseVolume(
                                id: selectedNoiseId,
                                volume: Float(newValue)
                            )
                        }
                    ),
                    accentColor: accentColor,
                    icon: "waveform"
                )
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedNoiseId)
    }

    private var noiseSelector: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(AmbientSound.selectable) { sound in
                noiseButton(id: sound.rawValue, label: sound.shortName)
            }
        }
    }

    private func noiseButton(id: Int, label: String) -> some View {
        let isSelected = selectedNoiseId == id
        return Button {
            selectNoise(id: id)
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? accentColor.opacity(0.15) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? accentColor : Color.white.opacity(0.1), lineWidth: 1)
                )
                .foregroundColor(isSelected ? accentColor : dimmedColor)
        }
        .buttonStyle(.plain)
    }

    private func selectNoise(id: Int) {
        if selectedNoiseId == id {
            selectedNoiseId = 0
            noiseVolume = Double(AudioManager.shared.getNoiseVolume(id: 0))
            onNoiseChanged(0)
            return
        }
        selectedNoiseId = id
        noiseVolume = Double(AudioManager.shared.getNoiseVolume(id: id))
        onNoiseChanged(id)
    }

    // MARK: - Freq

    private var freqPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("FREQUENCY")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundColor(dimmedColor)

            HStack(spacing: 8) {
                freqButton(id: 1, label: "40 Hz")
                freqButton(id: 2, label: "15 Hz")
                freqButton(id: 3, label: "10 Hz")
                freqButton(id: 4, label: "6 Hz")
            }

            if selectedFreqId != 0 {
                AppleFluidSlider(
                    value: Binding(
                        get: { freqVolume },
                        set: { newValue in
                            freqVolume = newValue
                            AudioManager.shared.setFreqVolume(
                                id: selectedFreqId,
                                volume: Float(newValue)
                            )
                        }
                    ),
                    accentColor: accentColor,
                    icon: "waveform.path.ecg"
                )
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedFreqId)
    }

    private func freqButton(id: Int, label: String) -> some View {
        let isSelected = selectedFreqId == id
        return Button {
            selectFreq(id: id)
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? accentColor.opacity(0.15) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? accentColor : Color.white.opacity(0.1), lineWidth: 1)
                )
                .foregroundColor(isSelected ? accentColor : dimmedColor)
        }
        .buttonStyle(.plain)
    }

    private func selectFreq(id: Int) {
        if selectedFreqId == id {
            selectedFreqId = 0
            freqVolume = Double(AudioManager.shared.getFreqVolume(id: 0))
            onFreqChanged(0)
            return
        }
        selectedFreqId = id
        freqVolume = Double(AudioManager.shared.getFreqVolume(id: id))
        onFreqChanged(id)
    }
}

// MARK: - Slider fluido

struct AppleFluidSlider: View {
    @Binding var value: Double
    var accentColor: Color
    var icon: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(accentColor)
                    .frame(width: max(44, geo.size.width * CGFloat(value)))

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(value > 0.15 ? .white : accentColor.opacity(0.8))
                    .padding(.leading, 14)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let percent = drag.location.x / geo.size.width
                        value = min(max(0, Double(percent)), 1.0)
                    }
            )
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: value)
        }
        .frame(height: 44)
    }
}
