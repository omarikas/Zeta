const CACHE_NAME = 'zeta-field-pwa-v2';
const APP_SHELL = ['/', '/index.html', '/manifest.webmanifest', '/icon.svg', '/accounts.html', '/accounts.js', '/accounts.css', '/account.html', '/account.js', '/account.css', '/visits.html', '/visits.js', '/visits.css', '/shell.css'];

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((keys) =>
            Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
        ).then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', (event) => {
    const url = new URL(event.request.url);
    if (url.pathname.startsWith('/services/')) {
        // Note: navigator.onLine is unreliable in Capacitor WebView
        // Always try to fetch - let the network failure handle real offline cases
        return;
    }
    if (event.request.method !== 'GET') {
        return;
    }
    event.respondWith(
        caches.match(event.request).then((cached) => {
            if (cached) {
                return cached;
            }
            return fetch(event.request)
                .then((response) => {
                    const copy = response.clone();
                    caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
                    return response;
                })
                .catch(() => cached || Response.error());
        })
    );
});
