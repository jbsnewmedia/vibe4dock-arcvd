/* arcvd service worker (no-op).
 * Deliberately does NOT intercept fetch(): with HTTP basic auth the SW's
 * fetches would lose the document credentials and subresources would fail.
 * The SW exists only to make the app installable as a PWA. */
var CACHE = 'arcvd-v1';

self.addEventListener('install', function (e) {
    self.skipWaiting();
});

self.addEventListener('activate', function (e) {
    e.waitUntil(
        caches.keys().then(function (keys) {
            return Promise.all(keys.map(function (k) { return caches.delete(k); }));
        }).then(function () { return self.clients.claim(); })
    );
});
