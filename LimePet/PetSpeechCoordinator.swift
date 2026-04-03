import AVFoundation

@MainActor
final class PetSpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: normalized)
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1.04
        utterance.volume = 1
        utterance.voice =
            AVSpeechSynthesisVoice(language: "zh-CN") ??
            AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "zh-CN")

        synthesizer.speak(utterance)
    }
}
