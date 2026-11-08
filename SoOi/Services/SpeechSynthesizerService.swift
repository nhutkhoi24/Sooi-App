import Foundation
import AVFoundation
import AudioToolbox

/// Quản lý hệ thống loa đọc thông báo thanh toán tiếng Việt (TTS) trên iOS
final class SpeechSynthesizerService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechSynthesizerService()

    private let synthesizer = AVSpeechSynthesizer()
    private var isConfigured = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Đọc thông báo thanh toán kèm chuông BEEP thông báo trước
    func speak(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 1. Cấu hình AudioSession để ưu tiên phát qua loa ngoài với âm lượng rõ ràng
            self.configureAudioSession()

            // 2. Phát âm thanh Beep ngân vang báo hiệu trước (tương tự ToneGenerator trên Android)
            AudioServicesPlaySystemSound(1057)

            // Đợi 250ms sau tiếng Beep để bắt đầu đọc câu thoại
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // Dừng câu đọc dở trước đó nếu có
                if self.synthesizer.isSpeaking {
                    self.synthesizer.stopSpeaking(at: .immediate)
                }

                let utterance = AVSpeechUtterance(string: text)
                // Tìm giọng đọc tiếng Việt (vi-VN), hỗ trợ fallback đa tầng
                if let vietnameseVoice = AVSpeechSynthesisVoice(language: "vi-VN") ??
                                         AVSpeechSynthesisVoice(language: "vi_VN") ??
                                         AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.starts(with: "vi") }) ??
                                         AVSpeechSynthesisVoice(language: Locale.current.identifier) ??
                                         AVSpeechSynthesisVoice(language: "en-US") {
                    utterance.voice = vietnameseVoice
                }

                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
                utterance.pitchMultiplier = 1.0
                utterance.volume = 1.0

                self.synthesizer.speak(utterance)
                print("[SoOiTTS] Đang đọc thông báo: \(text)")
            }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[SoOiTTS] Lỗi cấu hình AVAudioSession: \(error.localizedDescription)")
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Cho phép các app khác tiếp tục phát âm thanh sau khi đọc xong
        DispatchQueue.global(qos: .background).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
