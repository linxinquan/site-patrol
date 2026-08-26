// Zero-dependency static server for Flutter Web builds.
// Usage: node _serve_web.js [port] [rootDir]
// Features: correct MIME, Cache-Control: no-store (avoid stale builds),
//           SPA fallback to index.html, kill Flutter service worker cache.
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.argv[2], 10) || 8080;
const ROOT = path.resolve(__dirname, process.argv[3] || 'build/web');

const MIME = {
  '.html': 'text/html; charset=utf-8', '.htm': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8', '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.webp': 'image/webp', '.wasm': 'application/wasm', '.ttf': 'font/ttf',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.otf': 'font/otf',
  '.txt': 'text/plain; charset=utf-8', '.map': 'application/json; charset=utf-8',
  '.pdf': 'application/pdf', '.ocf': 'application/octet-stream',
};

// Intercept service worker: purge old caches and unregister itself.
const SW_KILL = `self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.registration.unregister();
  })());
});
`;

const NO_STORE = 'no-store, no-cache, must-revalidate, max-age=0';
const ASSET_RE = /\.(html?|js|mjs|css|json|png|jpe?g|gif|svg|ico|webp|wasm|ttf|woff2?|otf|txt|map|pdf|ocf)$/i;

http.createServer((req, res) => {
  let rel;
  try {
    rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch (e) {
    rel = req.url.split('?')[0];
  }

  // Flutter service worker -> uninstall script
  if (rel.endsWith('/flutter_service_worker.js')) {
    res.writeHead(200, {
      'Content-Type': 'application/javascript; charset=utf-8',
      'Content-Length': Buffer.byteLength(SW_KILL),
      'Cache-Control': NO_STORE,
    });
    res.end(SW_KILL);
    return;
  }

  if (rel === '/') rel = '/index.html';
  let file = path.normalize(path.join(ROOT, rel));
  if (!file.startsWith(ROOT)) { res.writeHead(403); res.end('403 Forbidden'); return; }

  const send = (code, ctype, data) => {
    res.writeHead(code, {
      'Content-Type': ctype,
      'Content-Length': data.length,
      'Cache-Control': NO_STORE,
    });
    res.end(data);
  };

  fs.stat(file, (err, st) => {
    if (!err && st.isDirectory()) file = path.join(file, 'index.html');
    fs.readFile(file, (err2, data) => {
      if (!err2) {
        const ext = path.extname(file).toLowerCase();
        send(200, MIME[ext] || 'application/octet-stream', data);
        return;
      }
      // SPA fallback only for non-asset paths
      if (!ASSET_RE.test(rel)) {
        fs.readFile(path.join(ROOT, 'index.html'), (err3, idx) => {
          if (err3) { send(404, 'text/plain; charset=utf-8', Buffer.from('404 Not Found')); return; }
          send(200, 'text/html; charset=utf-8', idx);
        });
        return;
      }
      send(404, 'text/plain; charset=utf-8', Buffer.from('404 Not Found: ' + rel));
    });
  });
}).listen(PORT, '0.0.0.0', () => {
  console.log(`serve http://localhost:${PORT}  root=${ROOT}  (no-cache)`);
});
