import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    @Binding var currentWebView: WKWebView?
    var onShowToast: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // 1. Lấy session đã lưu trước đó và app version để tiêm đồng bộ vào JS
        let savedSession = UserDefaults.standard.string(forKey: "saved_user_session") ?? ""
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let userContentController = WKUserContentController()

        // 2. Tiêm NativeBridge JavaScript ngay khi tài liệu bắt đầu nạp (documentStart)
        let scriptSource = BridgeScript.generateInjectionScript(savedSession: savedSession, appVersion: appVersion)
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userContentController.addUserScript(userScript)

        // 3. Đăng ký nhận thông điệp qua messageHandler: window.webkit.messageHandlers.nativeApp
        let bridgeHandler = NativeBridgeHandler(onShowToast: onShowToast)
        userContentController.add(bridgeHandler, name: "nativeApp")
        configuration.userContentController = userContentController

        // 4. Cấu hình hỗ trợ đa phương tiện
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .white
        webView.isOpaque = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        bridgeHandler.webView = webView
        context.coordinator.bridgeHandler = bridgeHandler

        // 5. Nạp file web index.html cục bộ từ bundle ứng dụng
        loadWebContent(into: webView)

        DispatchQueue.main.async {
            self.currentWebView = webView
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func loadWebContent(into webView: WKWebView) {
        if let webPath = Bundle.main.path(forResource: "index", ofType: "html", inDirectory: "Web") {
            let indexUrl = URL(fileURLWithPath: webPath)
            let directoryUrl = indexUrl.deletingLastPathComponent()
            webView.loadFileURL(indexUrl, allowingReadAccessTo: directoryUrl)
        } else if let fallbackPath = Bundle.main.path(forResource: "index", ofType: "html") {
            let indexUrl = URL(fileURLWithPath: fallbackPath)
            let directoryUrl = indexUrl.deletingLastPathComponent()
            webView.loadFileURL(indexUrl, allowingReadAccessTo: directoryUrl)
        } else {
            print("[SoOiWeb] Không tìm thấy file index.html trong Bundle.")
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewContainer
        var bridgeHandler: NativeBridgeHandler?

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        // Hỗ trợ hiển thị Alert, Confirm, Prompt từ JavaScript
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: "Sổ Ơi", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Đồng ý", style: .default) { _ in completionHandler() })

            if let rootVC = topViewController() {
                rootVC.present(alert, animated: true)
            } else {
                completionHandler()
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "Xác nhận", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "Đồng ý", style: .default) { _ in completionHandler(true) })

            if let rootVC = topViewController() {
                rootVC.present(alert, animated: true)
            } else {
                completionHandler(false)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: "Sổ Ơi", message: prompt, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = defaultText
            }
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "Đồng ý", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })

            if let rootVC = topViewController() {
                rootVC.present(alert, animated: true)
            } else {
                completionHandler(nil)
            }
        }

        // Tự động cấp quyền Camera & Microphone nếu WebView yêu cầu
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        private func topViewController() -> UIViewController? {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
                return nil
            }
            var top = window.rootViewController
            while let presented = top?.presentedViewController {
                top = presented
            }
            return top
        }
    }
}
