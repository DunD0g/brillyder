const CACHE_NAME = 'brillyder-v1';
const CORE_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './icon.svg',
  './apple-touch-icon.png',
  './icon-192.png',
  './icon-512.png',
  './stockfish.js',
  './stockfish.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(CORE_ASSETS).catch(() => undefined)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (url.pathname.endsWith('stockfish.wasm') || url.pathname.endsWith('stockfish.js')) {
    event.respondWith(
      caches.match(request).then((cached) => cached || fetch(request).then((res) => {
        if (res.ok) caches.open(CACHE_NAME).then((c) => c.put(request, res.clone()));
        return res;
      }))
    );
    return;
  }

  event.respondWith(
    fetch(request).then((res) => {
      if (res.ok) caches.open(CACHE_NAME).then((c) => c.put(request, res.clone()));
      return res;
    }).catch(() => caches.match(request).then((c) => c || caches.match('./index.html')))
  );
});
