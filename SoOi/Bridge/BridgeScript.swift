import Foundation

enum BridgeScript {
    /// Tạo script JavaScript được tiêm vào WKWebView tại thời điểm documentStart.
    /// Thiết lập đối tượng `window.AndroidBridge`, `window.iOSBridge`, `window.NativeBridge`
    /// để code web gọi trực tiếp mà không cần sửa bất kỳ dòng code nào.
    static func generateInjectionScript(savedSession: String, savedDb: String = "", appVersion: String) -> String {
        // Mã hóa an toàn 100% bằng JSONSerialization để ngăn chặn mọi lỗi cú pháp ký tự đặc biệt
        let jsonSession: String
        if let data = try? JSONSerialization.data(withJSONObject: [savedSession]),
           let str = String(data: data, encoding: .utf8), str.count >= 2 {
            let inner = str[str.index(after: str.startIndex)..<str.index(before: str.endIndex)]
            jsonSession = String(inner)
        } else {
            jsonSession = "\"\""
        }

        let jsonDb: String
        if let data = try? JSONSerialization.data(withJSONObject: [savedDb]),
           let str = String(data: data, encoding: .utf8), str.count >= 2 {
            let inner = str[str.index(after: str.startIndex)..<str.index(before: str.endIndex)]
            jsonDb = String(inner)
        } else {
            jsonDb = "\"\""
        }

        return """
        (function() {
            if (window.AndroidBridge && window.AndroidBridge.__isNative) return;

            var _session = \(jsonSession);
            var _dbBackup = \(jsonDb);
            var _version = "\(appVersion)";

            // Cung cấp biến toàn cục ngay lập tức tại documentStart
            window.__INITIAL_SOOI_SESSION__ = _session;
            window.__INITIAL_SOOI_DB__ = _dbBackup;

            var bridge = {
                __isNative: true,
                platform: 'ios',

                // 1. Quản lý phiên đăng nhập (Native Auth Session bền vững 100% trên iOS)
                saveAuthSession: function(sessionJson) {
                    try {
                        _session = (typeof sessionJson === 'string') ? sessionJson : JSON.stringify(sessionJson);
                        window.__INITIAL_SOOI_SESSION__ = _session;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'saveAuthSession', data: _session });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] saveAuthSession error:', e);
                    }
                },
                getAuthSession: function() {
                    return _session || window.__INITIAL_SOOI_SESSION__ || '';
                },
                clearAuthSession: function() {
                    _session = '';
                    window.__INITIAL_SOOI_SESSION__ = '';
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'clearAuthSession' });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] clearAuthSession error:', e);
                    }
                },

                // 1.1 Lưu trữ dữ liệu hệ thống (Local-first Mirror qua iOS UserDefaults)
                saveAppData: function(key, data) {
                    try {
                        var str = (typeof data === 'string') ? data : JSON.stringify(data);
                        if (key === 'saved_app_db' || key === 'sooi_db_backup') {
                            _dbBackup = str;
                            window.__INITIAL_SOOI_DB__ = str;
                        }
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'saveAppData', key: key, data: str });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] saveAppData error:', e);
                    }
                },
                getAppData: function(key) {
                    if (key === 'saved_app_db' || key === 'sooi_db_backup') {
                        return _dbBackup || window.__INITIAL_SOOI_DB__ || '';
                    }
                    return '';
                },

                // 2. Nhận diện giọng nói (Speech Recognition)
                getSpeechStatusJson: function() {
                    return JSON.stringify({
                        hasGoogleSpeech: true,
                        hasAppleSpeech: true,
                        hasInternet: (typeof navigator !== 'undefined' && navigator.onLine !== false),
                        isVoskReady: true,
                        isChinaDevice: false
                    });
                },
                isNativeVoiceSupported: function() {
                    return true;
                },
                startVoiceRecognition: function() {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'startVoiceRecognition' });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] startVoiceRecognition error:', e);
                    }
                },
                startVoiceRecognitionWithEngine: function(engine) {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'startVoiceRecognition', engine: engine });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] startVoiceRecognitionWithEngine error:', e);
                    }
                },
                stopVoiceRecognition: function() {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'stopVoiceRecognition' });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] stopVoiceRecognition error:', e);
                    }
                },
                openGoogleSpeechDownload: function() {
                    if (typeof window.showToast === 'function') {
                        window.showToast('iOS đã tích hợp sẵn nhận diện giọng nói tiếng Việt chuẩn của Apple.');
                    }
                },

                // 3. Loa đọc thông báo thanh toán tiếng Việt (TTS)
                speakPaymentSuccess: function(message) {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'speakPaymentSuccess', data: message });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] speakPaymentSuccess error:', e);
                    }
                },

                // 4. Phản hồi xúc giác & Thông báo (Haptics & Toast)
                vibrate: function(ms) {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'vibrate', data: ms });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] vibrate error:', e);
                    }
                },
                showToast: function(msg) {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'showToast', data: msg });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] showToast error:', e);
                    }
                },

                // 5. In ấn hóa đơn / Xuất PDF (AirPrint)
                printDocument: function(title) {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'printDocument', title: title });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] printDocument error:', e);
                    }
                },

                // 6. Tiện ích hệ thống
                isNetworkAvailable: function() {
                    return (typeof navigator !== 'undefined' && navigator.onLine !== false);
                },
                getAppVersion: function() {
                    return _version;
                },
                exitApp: function() {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeApp) {
                            window.webkit.messageHandlers.nativeApp.postMessage({ action: 'exitApp' });
                        }
                    } catch (e) {
                        console.error('[SoOi-iOS] exitApp error:', e);
                    }
                }
            };

            // Gán đồng thời vào AndroidBridge, iOSBridge, NativeBridge để tương thích 100%
            window.AndroidBridge = bridge;
            window.iOSBridge = bridge;
            window.NativeBridge = bridge;

            console.log('[SoOi-iOS] Đã khởi tạo NativeBridge iOS cho Sổ Ơi thành công (Kèm bộ nhớ đệm Native Session & DB).');
        })();
        """
    }
}
