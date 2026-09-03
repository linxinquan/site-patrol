#!/usr/bin/env python3
"""Flutter Web 构建后处理：

1. 删除 flutter_service_worker.js（构建用 --pwa-strategy=none 时它已是 0 字节，
   但残留文件仍会被浏览器尝试注册）。
2. 向 build/web/index.html 注入一段自清理脚本：自动注销所有已注册的 service worker、
   清空 Cache Storage，并自动 reload 一次（用 sessionStorage 防止死循环）。

用途：WorkBuddy 内置浏览器没有 DevTools，无法手动 Unregister / Clear site data，
     靠这段脚本让"刷新一下"就能看到最新构建。

用法：flutter build web ... 之后执行  python3 tools/post_build_web.py
"""
import os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(BASE, 'build', 'web')

SNIPPET = """<script>
// 自动清理旧 service worker 与缓存（内置浏览器无 DevTools 时的兜底）
(function () {
  if (!('serviceWorker' in navigator)) return;
  navigator.serviceWorker.getRegistrations().then(function (regs) {
    var had = regs.length > 0;
    regs.forEach(function (r) { r.unregister(); });
    if (window.caches && caches.keys) {
      caches.keys().then(function (keys) {
        keys.forEach(function (k) { caches.delete(k); });
      });
    }
    if (had && !sessionStorage.getItem('__sw_cleared')) {
      sessionStorage.setItem('__sw_cleared', '1');
      setTimeout(function () { location.reload(); }, 200);
    }
  });
})();
</script>
"""

def main():
    if not os.path.isdir(WEB):
        print('build/web not found:', WEB)
        return

    # 1) 删除 service worker 文件
    sw = os.path.join(WEB, 'flutter_service_worker.js')
    if os.path.exists(sw):
        os.remove(sw)
        print('removed flutter_service_worker.js')
    else:
        print('flutter_service_worker.js not present')

    # 2) 注入自清理脚本
    idx = os.path.join(WEB, 'index.html')
    with open(idx, encoding='utf-8') as f:
        s = f.read()

    if '__sw_cleared' in s:
        print('cleanup script already injected')
    else:
        if '</body>' in s:
            s = s.replace('</body>', SNIPPET + '\n</body>')
        else:
            s += '\n' + SNIPPET
        with open(idx, 'w', encoding='utf-8') as f:
            f.write(s)
        print('injected sw-cleanup script into index.html')


if __name__ == '__main__':
    main()
