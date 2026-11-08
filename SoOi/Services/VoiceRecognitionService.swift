import Foundation
import Speech
import AVFoundation

/// Dịch vụ nhận diện giọng nói tiếng Việt bằng Apple Speech Recognition chính thức
final class VoiceRecognitionService: NSObject {
    static let shared = VoiceRecognitionService()

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private(set) var isListening = false

    var onReady: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    var onResult: ((String) -> Void)?
    var onEnd: (() -> Void)?
    var onError: ((String) -> Void)?

    private override init() {
        super.init()
    }

    /// Bắt đầu lắng nghe và nhận diện giọng nói tiếng Việt
    func startListening() {
        guard !isListening else { return }

        // 1. Kiểm tra hỗ trợ của bộ nhận diện
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            onError?("Thiết bị chưa sẵn sàng nhận diện giọng nói tiếng Việt.")
            return
        }

        // 2. Yêu cầu cấp quyền Speech & Microphone
        requestPermissions { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.onError?("Cần cấp quyền Microphone và Nhận diện giọng nói để sử dụng tính năng này.")
                return
            }

            DispatchQueue.main.async {
                self.startAudioSessionAndRecognition()
            }
        }
    }

    /// Dừng nhận diện và giải phóng tài nguyên âm thanh
    func stopListening() {
        guard isListening else { return }
        isListening = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onEnd?()
        print("[SoOiVoice] Đã dừng nhận diện giọng nói.")
    }

    private func startAudioSessionAndRecognition() {
        // Hủy tác vụ cũ nếu còn sót
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onError?("Lỗi khởi tạo Microphone: \(error.localizedDescription)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Ưu tiên xử lý on-device nếu iOS hỗ trợ
        if #available(iOS 13.0, *), speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = false
        }
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            onReady?("Apple Speech Việt Nam")
            print("[SoOiVoice] Bắt đầu lắng nghe giọng nói tiếng Việt...")
        } catch {
            onError?("Không thể khởi động bộ thu âm: \(error.localizedDescription)")
            stopListening()
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcription = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)

                if result.isFinal {
                    self.onResult?(transcription)
                    self.stopListening()
                } else if !transcription.isEmpty {
                    self.onPartial?(transcription)
                }
            }

            if let error = error {
                let nsError = error as NSError
                // Tránh báo lỗi khi tác vụ bị hủy thông thường (code 216 hoặc cancellation)
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 209) {
                    self.stopListening()
                    return
                }
                self.onError?("Lỗi nhận diện giọng nói: \(error.localizedDescription)")
                self.stopListening()
            }
        }
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                completion(false)
                return
            }

            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                completion(granted)
            }
        }
    }
}
