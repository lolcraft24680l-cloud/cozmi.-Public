import AVFoundation
import Speech

@MainActor
final class Stimme: NSObject, ObservableObject {

    @Published var mitschrift = ""
    @Published var hört = false
    @Published var spricht = false
    /// Zählt bei jedem gesprochenen Wort hoch — das Gesicht wippt darauf.
    @Published var takt = 0

    /// Wird gerufen, sobald ein vollständiger Satz erkannt wurde.
    var beiSatz: ((String) -> Void)?

    private let motor = AVAudioEngine()
    private let erkenner = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var anfrage: SFSpeechAudioBufferRecognitionRequest?
    private var aufgabe: SFSpeechRecognitionTask?
    private var stilleUhr: Timer?

    private let sprecher = AVSpeechSynthesizer()

    override init() {
        super.init()
        sprecher.delegate = self
    }

    // MARK: Erlaubnis

    func erlaubnisHolen() async -> Bool {
        let spracheOK = await withCheckedContinuation { fortsetzen in
            SFSpeechRecognizer.requestAuthorization { status in
                fortsetzen.resume(returning: status == .authorized)
            }
        }
        let mikroOK = await withCheckedContinuation { fortsetzen in
            AVAudioApplication.requestRecordPermission { erlaubt in
                fortsetzen.resume(returning: erlaubt)
            }
        }
        return spracheOK && mikroOK
    }

    // MARK: Zuhören

    func zuhören() {
        guard !hört else { return }
        redenAbbrechen()

        guard let erkenner, erkenner.isAvailable else { return }

        do {
            let sitzung = AVAudioSession.sharedInstance()
            try sitzung.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try sitzung.setActive(true, options: .notifyOthersOnDeactivation)

            let neu = SFSpeechAudioBufferRecognitionRequest()
            neu.shouldReportPartialResults = true
            anfrage = neu

            let eingang = motor.inputNode
            eingang.removeTap(onBus: 0)
            let format = eingang.outputFormat(forBus: 0)
            eingang.installTap(onBus: 0, bufferSize: 1024, format: format) { puffer, _ in
                neu.append(puffer)
            }

            motor.prepare()
            try motor.start()

            mitschrift = ""
            hört = true
            stilleUhrNeu()

            aufgabe = erkenner.recognitionTask(with: neu) { [weak self] ergebnis, fehler in
                Task { @MainActor in
                    guard let self else { return }
                    if let ergebnis {
                        self.mitschrift = ergebnis.bestTranscription.formattedString
                        self.stilleUhrNeu()
                        if ergebnis.isFinal { self.abschließen() }
                    }
                    if fehler != nil { self.abschließen() }
                }
            }
        } catch {
            hört = false
        }
    }

    /// Nach 1,4 Sekunden Stille gilt der Satz als fertig.
    private func stilleUhrNeu() {
        stilleUhr?.invalidate()
        stilleUhr = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.abschließen() }
        }
    }

    private func abschließen() {
        guard hört else { return }
        let text = mitschrift.trimmingCharacters(in: .whitespacesAndNewlines)
        zuhörenBeenden()
        if !text.isEmpty { beiSatz?(text) }
    }

    func zuhörenBeenden() {
        stilleUhr?.invalidate(); stilleUhr = nil
        anfrage?.endAudio()
        aufgabe?.cancel()
        aufgabe = nil
        anfrage = nil
        if motor.isRunning {
            motor.stop()
            motor.inputNode.removeTap(onBus: 0)
        }
        hört = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Reden

    func rede(_ text: String) {
        let sitzung = AVAudioSession.sharedInstance()
        try? sitzung.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? sitzung.setActive(true)

        let äußerung = AVSpeechUtterance(string: text)
        äußerung.voice = besteStimme()
        äußerung.rate = 0.52
        äußerung.pitchMultiplier = 1.14
        äußerung.postUtteranceDelay = 0.1

        spricht = true
        sprecher.speak(äußerung)
    }

    func redenAbbrechen() {
        if sprecher.isSpeaking { sprecher.stopSpeaking(at: .immediate) }
        spricht = false
    }

    private func besteStimme() -> AVSpeechSynthesisVoice? {
        let deutsche = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("de") }
        return deutsche.first(where: { $0.quality == .premium })
            ?? deutsche.first(where: { $0.quality == .enhanced })
            ?? deutsche.first
            ?? AVSpeechSynthesisVoice(language: "de-DE")
    }
}

extension Stimme: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in self.takt &+= 1 }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.spricht = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.spricht = false }
    }
}
