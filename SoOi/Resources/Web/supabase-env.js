(function () {
  'use strict';
  // Bảo vệ cấu hình môi trường - Chống dịch ngược và chống can thiệp (Anti-Tampering)
  const _d = function (s) {
    try {
      return atob(s);
    } catch (e) {
      return '';
    }
  };

  const config = {
    SUPABASE_URL: _d("aHR0cHM6Ly9ub2Fqa3Nuamxid3RjYnRqeXpwby5zdXBhYmFzZS5jbw=="),
    SUPABASE_ANON_KEY: _d("c2JfcHVibGlzaGFibGVfUEZHMEREczVMbzY5dzRVbHJpRDNXUV9qZXA4ck9tWQ=="),
    AUTO_SYNC: true
  };

  // Đóng băng bất biến window.ENV
  Object.defineProperty(window, 'ENV', {
    value: Object.freeze(config),
    writable: false,
    configurable: false,
    enumerable: true
  });
})();
