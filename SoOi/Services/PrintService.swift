import UIKit
import WebKit

/// Dịch vụ in ấn hóa đơn và xuất file PDF hỗ trợ AirPrint / máy in nhiệt trên iOS
final class PrintService {
    static let shared = PrintService()

    private init() {}

    /// Mở hộp thoại in ấn tiêu chuẩn của iOS (AirPrint / Xuất PDF) từ WKWebView
    func printWebView(webView: WKWebView, title: String) {
        DispatchQueue.main.async {
            guard UIPrintInteractionController.isPrintingAvailable else {
                print("[SoOiPrint] Thiết bị không hỗ trợ in ấn.")
                return
            }

            let printController = UIPrintInteractionController.shared

            let printInfo = UIPrintInfo(dictionary: nil)
            printInfo.outputType = .general
            printInfo.jobName = "\(title)_\(Int(Date().timeIntervalSince1970))"
            printInfo.duplex = .none

            printController.printInfo = printInfo
            printController.showsPageRange = false
            printController.printFormatter = webView.viewPrintFormatter()

            guard let rootVC = self.getTopViewController() else {
                print("[SoOiPrint] Không tìm thấy ViewController để hiển thị in ấn.")
                return
            }

            // Hiển thị hộp thoại in phù hợp cho iPhone (modal) và iPad (popover)
            if UIDevice.current.userInterfaceIdiom == .pad {
                let centerRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                printController.present(from: centerRect, in: rootVC.view, animated: true) { _, completed, error in
                    if let error = error {
                        print("[SoOiPrint] Lỗi khi in: \(error.localizedDescription)")
                    }
                }
            } else {
                printController.present(animated: true) { _, completed, error in
                    if let error = error {
                        print("[SoOiPrint] Lỗi khi in: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func getTopViewController() -> UIViewController? {
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
