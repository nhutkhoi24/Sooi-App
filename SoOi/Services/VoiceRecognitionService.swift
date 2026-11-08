import Foundation
import Speech
import AVFoundation
import UIKit

/// Dịch vụ nhận diện giọng nói tiếng Việt bằng Apple Speech Recognition chính thức
final class VoiceRecognitionService: NSObject, SFSpeechRecognizerDelegate {
    static let shared = VoiceRecognitionService()

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var lastTranscription = ""

    private(set) var isListening = false

    var onReady: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    var onResult: ((String) -> Void)?
    var onEnd: (() -> Void)?
    var onError: ((String) -> Void)?

    private override init() {
        super.init()
        setupSpeechRecognizer()
    }

    private func setupSpeechRecognizer() {
        // Ưu tiên tiếng Việt vi-VN, hỗ trợ vi_VN và fallback ngôn ngữ hệ thống
        if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN")) {
            self.speechRecognizer = recognizer
        } else if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi_VN")) {
            self.speechRecognizer = recognizer
        } else {
            self.speechRecognizer = SFSpeechRecognizer()
        }
        self.speechRecognizer?.delegate = self
    }

    /// Bắt đầu lắng nghe và nhận diện giọng nói tiếng Việt
    func startListening() {
        guard !isListening else { return }

        // Yêu cầu cấp quyền Speech & Microphone trước
        requestPermissions { [weak self] granted, errorMessage in
            guard let self = self else { return }
            guard granted else {
                let msg = errorMessage ?? "Cần cấp quyền Microphone và Nhận diện giọng nói để sử dụng tính năng này."
                self.onError?(msg)
                return
            }

            DispatchQueue.main.async {
                self.startAudioSessionAndRecognition()
            }
        }
    }

    /// Dừng nhận diện và giải phóng tài nguyên âm thanh
    func stopListening(silent: Bool = false) {
        guard isListening || audioEngine.isRunning || recognitionTask != nil else { return }
        isListening = false

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        let finalCandidate = lastTranscription
        lastTranscription = ""

        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        if !silent {
            if !finalCandidate.isEmpty {
                onResult?(finalCandidate)
            }
            onEnd?()
        }
        print("[SoOiVoice] Đã dừng nhận diện giọng nói.")
    }

    private func startAudioSessionAndRecognition() {
        // 1. Dọn dẹp trạng thái cũ
        stopListening(silent: true)

        if speechRecognizer == nil {
            setupSpeechRecognizer()
        }

        guard let recognizer = speechRecognizer else {
            onError?("Thiết bị không hỗ trợ nhận diện giọng nói.")
            return
        }

        // 2. Cấu hình AudioSession cho phép cả thu âm và phát loa
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onError?("Không thể kích hoạt Microphone: \(error.localizedDescription)")
            return
        }

        // 3. Chuẩn bị Recognition Request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        // 4. Cấu hình Audio Engine Input Node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            onError?("Microphone chưa sẵn sàng. Vui lòng thử lại sau giây lát.")
            stopListening()
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            let localeName = recognizer.locale.identifier.contains("vi") ? "Apple Speech (Tiếng Việt)" : "Apple Speech (\(recognizer.locale.identifier))"
            onReady?(localeName)
            print("[SoOiVoice] Bắt đầu lắng nghe giọng nói trên iPhone...")
        } catch {
            onError?("Không thể khởi động bộ thu âm: \(error.localizedDescription)")
            stopListening()
            return
        }

        // 5. Khởi chạy Recognition Task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcription = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastTranscription = transcription

                if result.isFinal {
                    self.onResult?(transcription)
                    self.stopListening()
                } else if !transcription.isEmpty {
                    self.onPartial?(transcription)
                }
            }

            if let error = error {
                let nsError = error as NSError
                // Tránh báo lỗi khi tác vụ bị hủy thông thường (code 216 hoặc 209 hoặc 301)
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 209 || nsError.code == 301) {
                    self.stopListening()
                    return
                }
                if self.isListening {
                    self.onError?("Lỗi nhận diện giọng nói: \(error.localizedDescription)")
                    self.stopListening()
                }
            }
        }
    }

    /// Yêu cầu cấp quyền theo đúng chuẩn iOS 16/17/18
    private func requestPermissions(completion: @escaping (Bool, String?) -> Void) {
        // Bước 1: Kiểm tra quyền Speech Recognition
        let speechStatus = SFSpeechRecognizer.authorizationStatus()

        switch speechStatus {
        case .authorized:
            self.requestMicrophonePermission(completion: completion)

        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        self.requestMicrophonePermission(completion: completion)
                    } else {
                        completion(false, "Vui lòng cho phép quyền 'Nhận diện giọng nói' để ra lệnh bằng giọng nói.")
                    }
                }
            }

        case .denied, .restricted:
            completion(false, "Quyền Nhận diện giọng nói đang bị tắt. Vui lòng mở Cài đặt iPhone -> Sổ Ơi -> Bật 'Nhận diện giọng nói'.")

        @unknown default:
            completion(false, "Trạng thái nhận diện giọng nói không xác định.")
        }
    }

    /// Kiểm tra & yêu cầu cấp quyền Microphone (tương thích iOS 17/18 và các bản cũ hơn)
    private func requestMicrophonePermission(completion: @escaping (Bool, String?) -> Void) {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                completion(true, nil)

            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            completion(true, nil)
                        } else {
                            completion(false, "Vui lòng cho phép quyền 'Microphone' để nói với Sổ Ơi.")
                        }
                    }
                }

            case .denied:
                completion(false, "Quyền Micro đang bị tắt. Vui lòng mở Cài đặt iPhone -> Sổ Ơi -> Bật 'Micro'.")

            @unknown default:
                completion(false, "Trạng thái Microphone không xác định.")
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted:
                completion(true, nil)

            case .undetermined:
                session.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            completion(true, nil)
                        } else {
                            completion(false, "Vui lòng cho phép quyền 'Microphone' để nói với Sổ Ơi.")
                        }
                    }
                }

            case .denied:
                completion(false, "Quyền Micro đang bị tắt. Vui lòng mở Cài đặt iPhone -> Sổ Ơi -> Bật 'Micro'.")

            @unknown default:
                completion(false, "Trạng thái Microphone không xác định.")
            }
        }
    }

    // MARK: - SFSpeechRecognizerDelegate
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available && isListening {
            print("[SoOiVoice] Speech recognizer tạm thời không khả dụng.")
        }
    }
}
