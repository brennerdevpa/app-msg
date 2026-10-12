// Service worker do MyMsg: necessário para notificações no celular e para abrir a conversa ao clicar.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(clients.claim()));
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const chat = e.notification.data && e.notification.data.chat;
  e.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const c of list) { if ('focus' in c) { c.postMessage({ chat }); return c.focus(); } }
    return clients.openWindow('./');
  }));
});
