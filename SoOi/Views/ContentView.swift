import SwiftUI
import WebKit

struct ContentView: View {
    @State private var currentWebView: WKWebView?
    @State private var toastMessage: String?
    @State private var toastDismissWorkItem: DispatchWorkItem?

    // Mã màu chủ đạo thương hiệu Sổ Ơi: #0B7A60
    private let primaryBrandColor = Color(red: 11 / 255.0, green: 122 / 255.0, blue: 96 / 255.0)

    var body: some View {
        ZStack {
            // Nền trắng tràn viền phủ trọn vẹn màn hình trên mọi dòng máy iPhone, iPad
            Color.white
                .ignoresSafeArea()

            // Web container tràn viền toàn bộ khung hình (Edge-to-Edge)
            WebViewContainer(currentWebView: $currentWebView) { message in
                showToast(message)
            }
            .ignoresSafeArea()

            // Toast thông báo góc dưới, nằm an toàn trên thanh điều hướng & home indicator
            if let message = toastMessage {
                VStack {
                    Spacer()
                    ToastView(message: message)
                        .padding(.bottom, 48)
                }
                .zIndex(10)
            }
        }
        .preferredColorScheme(.light)
    }

    private func showToast(_ message: String) {
        toastDismissWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            self.toastMessage = message
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.toastMessage = nil
            }
        }
        self.toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }
}
