import AVFoundation
import Foundation

/// Genera tonos binaurales y ruido de color estéreo en un único nodo de audio.
@MainActor
final class BinauralManager {
    private let audioEngine = AVAudioEngine()
    private let renderer = AmbientAudioRenderer()

    private var sourceNode: AVAudioSourceNode?
    private var graphSampleRate: Double = 0
    private var pauseTask: Task<Void, Never>?

    private(set) var isPlaying = false

    func play(
        noiseId: Int,
        brainwaveDifference: Float?,
        noiseVolume: Float,
        toneVolume: Float
    ) {
        pauseTask?.cancel()

        renderer.requestedNoiseId = noiseId
        renderer.targetNoiseGain = safeNoiseGain(for: noiseVolume)
        renderer.targetToneGain = safeToneGain(for: toneVolume)
        renderer.targetToneDifference = brainwaveDifference ?? 0

        guard startEngineIfNeeded() else { return }

        // Fade in más largo y perceptible al arrancar.
        renderer.setMasterFadeDuration(AudioBalance.fadeInDuration)
        renderer.targetMasterGain = 1
        isPlaying = true
    }

    func setNoiseVolume(_ volume: Float) {
        renderer.targetNoiseGain = safeNoiseGain(for: volume)
    }

    func setToneVolume(_ volume: Float) {
        renderer.targetToneGain = safeToneGain(for: volume)
    }

    func pause() {
        guard isPlaying else { return }

        // Fade out perceptible al pausar.
        renderer.setMasterFadeDuration(AudioBalance.pauseFadeDuration)
        renderer.targetMasterGain = 0
        isPlaying = false
        scheduleEnginePause(after: 1.3)
    }

    func stop() {
        renderer.setMasterFadeDuration(AudioBalance.stopFadeDuration)   // Fade out largo al terminar sesión.
        renderer.targetMasterGain = 0
        renderer.targetNoiseGain = 0
        renderer.targetToneGain = 0
        renderer.requestedNoiseId = 0
        isPlaying = false
        scheduleEnginePause(after: 2.0)
    }

    /// Detiene todo sin fade perceptible. Se usa cuando en el mismo ciclo se va a
    /// arrancar otro sonido (p. ej. cambio de preset con autoarranque), para evitar
    /// que el fade-out del anterior se solape con el fade-in del nuevo.
    func stopImmediate() {
        pauseTask?.cancel()
        renderer.setMasterFadeDuration(AudioBalance.quickFadeDuration)
        renderer.targetMasterGain = 0
        renderer.targetNoiseGain = 0
        renderer.targetToneGain = 0
        renderer.requestedNoiseId = 0
        isPlaying = false
        scheduleEnginePause(after: 0.5)
    }

    private func startEngineIfNeeded() -> Bool {
        pauseTask?.cancel()

        do {
            try buildGraphIfNeeded()
            guard !audioEngine.isRunning else { return true }

            audioEngine.prepare()
            try audioEngine.start()
            return true
        } catch {
            print("Error al iniciar el motor ambiental: \(error.localizedDescription)")
            return false
        }
    }

    private func buildGraphIfNeeded() throws {
        let outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100

        guard sourceNode == nil || graphSampleRate != sampleRate else {
            return
        }

        if let sourceNode {
            audioEngine.disconnectNodeOutput(sourceNode)
            audioEngine.detach(sourceNode)
        }

        renderer.configure(sampleRate: sampleRate)

        let stereoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!
        let newSourceNode = renderer.makeSourceNode(format: stereoFormat)

        audioEngine.attach(newSourceNode)
        try audioEngine.connectNode( 
            newSourceNode,
            to: audioEngine.mainMixerNode,
            format: stereoFormat
        )

        sourceNode = newSourceNode
        graphSampleRate = sampleRate
    }

    /// Pausa el motor de audio después de un fade-out.
    /// Usa `stop()` en vez de `pause()` porque `stop()` libera más
    /// recursos (buffers, threads internos). El engine se reconstruye
    /// on-demand en `startEngineIfNeeded`.
    private func scheduleEnginePause(after seconds: TimeInterval) {
        pauseTask?.cancel()

        pauseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

            guard !Task.isCancelled, let self, !self.isPlaying else {
                return
            }

            self.audioEngine.stop()
            // Nota: NO desactivamos la sesión acá. Si hay otra fuente de
            // audio activa (ej: ambience file-based), desactivarla mataría
            // el audio de fondo. La sesión se libera cuando la app cierra.
        }
    }

    // Curva exponencial: más resolución cerca de 0, comprimida cerca de 1.
    // Parámetros en `AudioBalance.swift`.
    private func safeToneGain(for sliderValue: Float) -> Float {
        let normalized = min(max(sliderValue, 0), 1)
        return powf(normalized, AudioBalance.toneCurveExponent) * AudioBalance.maxToneGain
    }

    // Curva exponencial simétrica con la del tono.
    // Parámetros en `AudioBalance.swift`.
    private func safeNoiseGain(for sliderValue: Float) -> Float {
        let normalized = min(max(sliderValue, 0), 1)
        return powf(normalized, AudioBalance.noiseCurveExponent) * AudioBalance.maxNoiseGain
    }
}

// MARK: - Filtro rosa (Paul Kellet)

nonisolated private struct PinkFilter {
    private var b0: Float = 0
    private var b1: Float = 0
    private var b2: Float = 0
    private var b3: Float = 0
    private var b4: Float = 0
    private var b5: Float = 0
    private var b6: Float = 0

    @inline(__always)
    mutating func process(_ white: Float) -> Float {
        b0 = (0.99886 * b0) + (white * 0.0555179)
        b1 = (0.99332 * b1) + (white * 0.0750759)
        b2 = (0.96900 * b2) + (white * 0.1538520)
        b3 = (0.86650 * b3) + (white * 0.3104856)
        b4 = (0.55000 * b4) + (white * 0.5329522)
        b5 = (-0.7616 * b5) - (white * 0.0168980)

        let output = b0 + b1 + b2 + b3 + b4 + b5 + b6 + (white * 0.5362)
        b6 = white * 0.115926
        return output * 0.11
    }
}

// MARK: - Renderer

/// El bloque de render se ejecuta en el hilo de audio y no reserva memoria,
/// bloquea ni accede a APIs de UI.
nonisolated final class AmbientAudioRenderer: @unchecked Sendable {
    // Parámetros escritos desde el main actor. El renderer los lee una vez por bloque.
    var targetToneDifference: Float = 0
    var targetToneGain: Float = 0
    var targetNoiseGain: Float = 0
    var targetMasterGain: Float = 0
    var requestedNoiseId = 0

    private var sampleRate: Float = 44_100
    private var toneDifference: Float = 0
    private var toneGain: Float = 0
    private var noiseGain: Float = 0
    private var masterGain: Float = 0
    private var noiseFade: Float = 0
    private var activeNoiseId = 0

    private var leftPhase: Float = 0
    private var rightPhase: Float = 0
    private var randomLeft: UInt32 = 0x1234_ABCD
    private var randomRight: UInt32 = 0x9E37_79B9
    private var pinkLeft = PinkFilter()
    private var pinkRight = PinkFilter()
    private var brownLeft: Float = 0
    private var brownRight: Float = 0
    private var previousWhiteLeft: Float = 0
    private var previousWhiteRight: Float = 0
    private var filteredLeft: Float = 0
    private var filteredRight: Float = 0

    private var parameterSmoothing: Float = 0
    private var masterSmoothing: Float = 0
    private var noiseSmoothing: Float = 0

    /// Duración actual del fade del master gain (en segundos). Cambia dinámicamente
    /// desde play/pause/stop para lograr transiciones largas y audibles.
    private var masterFadeDuration: Float = 0.10

    /// Constante de tiempo del filtro de suavizado del ruido blanco/violeta.
    private let smoothingCoefficient: Float = 0.3

    // MARK: - Configuración

    /// ÚNICO `configure(sampleRate:)`. Recalcula los tres coeficientes de suavizado
    /// en función del sample rate actual.
    func configure(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)
        recalculateSmoothings()
    }

    /// Permite cambiar la constante de tiempo del master gain dinámicamente.
    /// Se usa desde play/pause/stop para lograr fades largos y audibles.
    func setMasterFadeDuration(_ seconds: Float) {
        masterFadeDuration = max(0.05, seconds)
        masterSmoothing = 1 - expf(-1 / (masterFadeDuration * sampleRate))
    }

    private func recalculateSmoothings() {
        parameterSmoothing = 1 - expf(-1 / (AudioBalance.parameterSmoothingSeconds * sampleRate))
        masterSmoothing    = 1 - expf(-1 / (masterFadeDuration * sampleRate))
        noiseSmoothing     = 1 - expf(-1 / (AudioBalance.noiseSmoothingSeconds * sampleRate))
    }

    // MARK: - Nodo de audio

    func makeSourceNode(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, bufferList in
            render(
                frameCount: Int(frameCount),
                bufferList: bufferList
            )
        }
    }

    // MARK: - Render

    private func render(
        frameCount: Int,
        bufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let audioBuffers = UnsafeMutableAudioBufferListPointer(bufferList)

        guard audioBuffers.count >= 2,
              let leftOutput = audioBuffers[0].mData?.assumingMemoryBound(to: Float.self),
              let rightOutput = audioBuffers[1].mData?.assumingMemoryBound(to: Float.self) else {
            return 0
        }

        let requestedNoise = requestedNoiseId
        let targetDifference = targetToneDifference
        let targetTone = targetToneGain
        let targetNoise = targetNoiseGain
        let targetMaster = targetMasterGain

        var difference = toneDifference
        var tone = toneGain
        var noise = noiseGain
        var master = masterGain
        var fade = noiseFade
        var activeNoise = activeNoiseId
        var phaseLeft = leftPhase
        var phaseRight = rightPhase
        var rngLeft = randomLeft
        var rngRight = randomRight
        var pinkL = pinkLeft
        var pinkR = pinkRight
        var brownL = brownLeft
        var brownR = brownRight
        var previousL = previousWhiteLeft
        var previousR = previousWhiteRight
        var filteredL = filteredLeft
        var filteredR = filteredRight

        let shouldRenderTone = tone > 0.0001 || targetTone > 0.0001
        let radiansPerSample = (2 * Float.pi) / sampleRate
        // Frecuencia portadora a 432 Hz (afinación relajante).
        let leftIncrement = AudioBalance.carrierFrequency * radiansPerSample
        let rightBaseFrequency: Float = AudioBalance.carrierFrequency

        for frame in 0..<frameCount {
            difference += (targetDifference - difference) * parameterSmoothing
            tone += (targetTone - tone) * parameterSmoothing
            noise += (targetNoise - noise) * parameterSmoothing
            master += (targetMaster - master) * masterSmoothing

            let wantsCurrentNoise: Float = activeNoise == requestedNoise && requestedNoise != 0 ? 1 : 0
            fade += (wantsCurrentNoise - fade) * noiseSmoothing

            if activeNoise != requestedNoise && fade < 0.001 {
                activeNoise = requestedNoise
                pinkL = PinkFilter()
                pinkR = PinkFilter()
                brownL = 0
                brownR = 0
                previousL = 0
                previousR = 0
                filteredL = 0
                filteredR = 0
            }

            var noiseLeft: Float = 0
            var noiseRight: Float = 0

            if activeNoise != 0 && fade > 0.0001 {
                let whiteLeft = Self.nextWhite(&rngLeft)
                let whiteRight = Self.nextWhite(&rngRight)

                switch activeNoise {
                case 1: // Marrón — constante de tiempo y ganancia reducidas.
                    brownL = (brownL + (0.015 * whiteLeft)) / 1.015
                    brownR = (brownR + (0.015 * whiteRight)) / 1.015
                    noiseLeft = brownL * 2.8
                    noiseRight = brownR * 2.8
                case 2: // Rosa — ganancia ligeramente reducida.
                    noiseLeft = pinkL.process(whiteLeft) * 0.9
                    noiseRight = pinkR.process(whiteRight) * 0.9
                case 3: // Blanco suavizado — filtro de paso bajo más agresivo.
                    filteredL += smoothingCoefficient * (whiteLeft - filteredL)
                    filteredR += smoothingCoefficient * (whiteRight - filteredR)
                    noiseLeft = filteredL * 0.5
                    noiseRight = filteredR * 0.5
                case 4: // Violeta suavizado — filtro de paso bajo más agresivo.
                    let derivativeLeft = (whiteLeft - previousL) * 0.25
                    let derivativeRight = (whiteRight - previousR) * 0.25
                    previousL = whiteLeft
                    previousR = whiteRight
                    filteredL += smoothingCoefficient * (derivativeLeft - filteredL)
                    filteredR += smoothingCoefficient * (derivativeRight - filteredR)
                    noiseLeft = filteredL * 0.8
                    noiseRight = filteredR * 0.8
                default:
                    break
                }

                let noiseLevel = noise * fade
                noiseLeft *= noiseLevel
                noiseRight *= noiseLevel
            }

            var toneLeft: Float = 0
            var toneRight: Float = 0

            if shouldRenderTone {
                if tone > 0.0001 {
                    toneLeft = sinf(phaseLeft) * tone
                    toneRight = sinf(phaseRight) * tone
                }

                phaseLeft += leftIncrement
                phaseRight += (rightBaseFrequency + difference) * radiansPerSample

                if phaseLeft >= 2 * Float.pi { phaseLeft -= 2 * Float.pi }
                if phaseRight >= 2 * Float.pi { phaseRight -= 2 * Float.pi }
            }

            leftOutput[frame] = Self.softLimit((toneLeft + noiseLeft) * master)
            rightOutput[frame] = Self.softLimit((toneRight + noiseRight) * master)
        }

        toneDifference = difference
        toneGain = tone
        noiseGain = noise
        masterGain = master
        noiseFade = fade
        activeNoiseId = activeNoise
        leftPhase = phaseLeft
        rightPhase = phaseRight
        randomLeft = rngLeft
        randomRight = rngRight
        pinkLeft = pinkL
        pinkRight = pinkR
        brownLeft = brownL
        brownRight = brownR
        previousWhiteLeft = previousL
        previousWhiteRight = previousR
        filteredLeft = filteredL
        filteredRight = filteredR

        return 0
    }

    // MARK: - Helpers

    @inline(__always)
    private static func nextWhite(_ state: inout UInt32) -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(Int32(bitPattern: state)) * (1 / 2_147_483_648)
    }

    @inline(__always)
    private static func softLimit(_ value: Float) -> Float {
        let magnitude = abs(value)

        // Umbral elevado y curva más suave para mayor transparencia.
        guard magnitude > 0.9 else {
            return value
        }

        let limited = 0.9 + (0.1 * ((magnitude - 0.9) / (magnitude - 0.7)))
        return value < 0 ? -limited : limited
    }
}
