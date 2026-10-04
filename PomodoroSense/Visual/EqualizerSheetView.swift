import SwiftUI

// MARK: - Ecualizador conectado al TimerViewModel
//
// Este sheet reemplaza al antiguo. Ahora:
// - Recibe el TimerViewModel y le aplica los cambios en vivo.
// - Cambiar el ruido de color actualiza el tema visual (colores) sin resetear el cronómetro.
// - Cambiar la frecuencia binaural NO toca el tema visual.
// - Los volúmenes se persisten por id en UserDefaults (como ya hacía AudioManager).

struct EqualizerSheetView: View {
    @Environment(\.dismiss) var dismiss

    @ObservedObject var timerViewModel: TimerViewModel

    var accentColor: Color
    var dimmedColor: Color
    var backgroundColor: Color

    // Estado local espejo del TimerViewModel / AudioManager
    @State private var selectedNoiseId: Int = 1
    @State private var selectedFreqId: Int = 1
    @State private var noiseVolume: Double = 0.5
    @State private var freqVolume: Double = 0.5
    @State private var didLoadInitialState = false

    #if os(iOS)
    @Environment(\.verticalSizeClass) var verticalSizeClass
    private var isPortrait: Bool { verticalSizeClass == .regular }
    #else
    private var isPortrait: Bool { false }
    #endif

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 30) {
                header

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 40) { equalizerContent }
                    VStack(spacing: 40) { equalizerContent }
                }
                .padding(.horizontal, 30)

                Spacer()
            }
        }
        .onAppear(perform: loadInitialState)
    }

    // MARK: - Carga inicial y sincronización

    private func loadInitialState() {
        guard !didLoadInitialState else { return }
        didLoadInitialState = true

        let audio = timerViewModel.activeConfig.audio
        selectedNoiseId = audio.noiseId == 0 ? 1 : audio.noiseId
        selectedFreqId  = audio.freqId  == 0 ? 1 : audio.freqId
        noiseVolume = Double(AudioManager.shared.getNoiseVolume(id: selectedNoiseId))
        freqVolume  = Double(AudioManager.shared.getFreqVolume(id: selectedFreqId))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("AUDIO EQUALIZER")
                .font(.system(size: 14, weight: .bold))
                .tracking(4)
                .foregroundColor(dimmedColor)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(dimmedColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.top, 30)
    }

    // MARK: - Contenido

    @ViewBuilder
    private var equalizerContent: some View {
        noisePanel
        freqPanel
    }

    // MARK: - Panel de ruidos

    private var noisePanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("NOISE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundColor(dimmedColor)

            // Fila de botones para seleccionar el ruido (tap directo, sin picker)
            noiseSelector

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

    private var noiseSelector: some View {
        HStack(spacing: 8) {
            noiseButton(id: 1, label: "BROWN")
            noiseButton(id: 2, label: "PINK")
            noiseButton(id: 3, label: "WHITE")
            noiseButton(id: 4, label: "VIOLET")
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
        guard selectedNoiseId != id else { return }
        selectedNoiseId = id
        noiseVolume = Double(AudioManager.shared.getNoiseVolume(id: id))
        // Aplica en vivo: cambia el tema visual SIN resetear el cronómetro
        timerViewModel.updateNoiseId(id)
    }

    // MARK: - Panel de frecuencias

    private var freqPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("FREQUENCY")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundColor(dimmedColor)

            freqSelector

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

    private var freqSelector: some View {
        HStack(spacing: 8) {
            freqButton(id: 1, label: "40 Hz")
            freqButton(id: 2, label: "15 Hz")
            freqButton(id: 3, label: "10 Hz")
            freqButton(id: 4, label: "6 Hz")
        }
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
        guard selectedFreqId != id else { return }
        selectedFreqId = id
        freqVolume = Double(AudioManager.shared.getFreqVolume(id: id))
        // Aplica en vivo SIN tocar el tema visual
        timerViewModel.updateFreqId(id)
    }
}

// MARK: - Slider fluido (idéntico al que ya tenías)

struct AppleFluidSlider: View {
    @Binding var value: Double // 0.0 a 1.0
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