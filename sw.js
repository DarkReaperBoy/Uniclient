"use strict";
var VER = "b7ad867ed046";
var CACHE = "uniclient-shell-" + VER;
var SHELL = ["./", "index.html", "wasm_exec.js"];
self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) {
    return c.addAll(SHELL);
  }).then(function () { return self.skipWaiting(); }));
});
self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) {
      return k.indexOf("uniclient-shell-") === 0 && k !== CACHE;
    }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});
self.addEventListener("fetch", function (e) {
  var url = new URL(e.request.url);
  if (url.origin !== location.origin || e.request.method !== "GET") return;
  if (url.pathname.slice(-15) === "uniclient.wasm") return;
  e.respondWith((async function () {
    try {
      var resp = await fetch(e.request);
      if (resp && resp.ok) {
        var c = await caches.open(CACHE);
        c.put(e.request, resp.clone());
      }
      return resp;
    } catch (err) {
      var hit = await caches.match(e.request, { ignoreSearch: true });
      if (hit) return hit;
      throw err;
    }
  })());
});
