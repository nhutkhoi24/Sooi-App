import UIKit
import WebKit

/// Lớp tiếp nhận và điều phối mọi thông điệp từ JavaScript (WKScriptMessageHandler)
final class NativeBridgeHandler: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    var onShowToast: ((String) -> Void)?

    init(webView: WKWebView? = nil, onShowToast: ((String) -> Void)? = nil) {
        self.webView = webView
        self.onShowToast = onShowToast
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "nativeApp",
              let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else {
            return
        }

        switch action {
        case "saveAuthSession":
            if let sessionStr = dict["data"] as? String {
                UserDefaults.standard.set(sessionStr, forKey: "saved_user_session")
                print("[SoOiBridge] Đã lưu session vào UserDefaults thành công.")
            }

        case "clearAuthSession":
            UserDefaults.standard.removeObject(forKey: "saved_user_session")
            print("[SoOiBridge] Đã xóa session trong UserDefaults.")

        case "showToast":
            if let msg = dict["data"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.onShowToast?(msg)
                }
            }

        case "vibrate":
            DispatchQueue.main.async {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred()
            }

        case "speakPaymentSuccess":
            if let text = dict["data"] as? String {
                SpeechSynthesizerService.shared.speak(text: text)
            }

        case "startVoiceRecognition":
            startSpeechRecognition()

        case "stopVoiceRecognition":
            VoiceRecognitionService.shared.stopListening()

        case "printDocument":
            let title = (dict["title"] as? String) ?? "Hoa_Don_SoOi"
            if let wv = webView {
                PrintService.shared.printWebView(webView: wv, title: title)
            }

        case "exitApp":
            DispatchQueue.main.async {
                UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
            }

        default:
            print("[SoOiBridge] Không nhận diện được action: \(action)")
        }
    }

    private func startSpeechRecognition() {
        let voiceService = VoiceRecognitionService.shared

        voiceService.onReady = { [weak self] engine in
            let escaped = self?.escapeForJS(engine) ?? "\"\(engine)\""
            self?.evaluateJS("if (typeof window.onNativeSpeechReady === 'function') window.onNativeSpeechReady(\(escaped));")
        }

        voiceService.onPartial = { [weak self] partialText in
            let escaped = self?.escapeForJS(partialText) ?? "\"\""
            self?.evaluateJS("if (typeof window.onNativeSpeechPartial === 'function') window.onNativeSpeechPartial(\(escaped));")
        }

        voiceService.onResult = { [weak self] resultText in
            let escaped = self?.escapeForJS(resultText) ?? "\"\""
            self?.evaluateJS("if (typeof window.onNativeSpeechResult === 'function') window.onNativeSpeechResult(\(escaped));")
        }

        voiceService.onEnd = { [weak self] in
            self?.evaluateJS("if (typeof window.onNativeSpeechEnd === 'function') window.onNativeSpeechEnd();")
        }

        voiceService.onError = { [weak self] errorMsg in
            let escaped = self?.escapeForJS(errorMsg) ?? "\"\""
            self?.evaluateJS("if (typeof window.onNativeSpeechError === 'function') window.onNativeSpeechError(\(escaped));")
        }

        voiceService.startListening()
    }

    private func evaluateJS(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func escapeForJS(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let jsonString = String(data: data, encoding: .utf8),
              jsonString.count >= 2 else {
            return "\"\(string)\""
        }
        // Lấy chuỗi đã được escape an toàn chuẩn JSON: ["abc"] -> "abc"
        let startIndex = jsonString.index(after: jsonString.startIndex)
        let endIndex = jsonString.index(before: jsonString.endIndex)
        return String(jsonString[startIndex..<endIndex])
    }
}
