// wa-mobile v2
// Мобильная обёртка WhatsApp Web: одна колонка за раз, как в приложении.
// Режим «список»: только список чатов. Режим «чат»: только открытый чат на весь экран.
// Если открыта панель (инфо о контакте, поиск по чату), на весь экран показывается она.
//
// Раскладка WhatsApp Web (проверено 2026-10): общий flex-контейнер, в нём по порядку
//   HEADER (полоса иконок) | [absolute-слои] | колонка #side | колонка чата (#main или заставка)
//   | [absolute-слой] | колонка панели | ... | #wds-toast-container (fixed)
// Absolute и fixed слои (меню, просмотр медиа, тосты) не трогаем.
(function () {
  if (window.__waMobile) return;

  var post = function (msg) {
    try { window.webkit.messageHandlers.wa.postMessage(msg); } catch (e) {}
  };

  // maximum-scale=1 убирает автозум iOS при фокусе на поле ввода.
  function ensureViewport() {
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'viewport';
      (document.head || document.documentElement).appendChild(meta);
    }
    var want = 'width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover';
    if (meta.content !== want) meta.content = want;
  }

  var css = [
    'html, body { overflow-x: hidden !important; }',
    '[data-wa-root] { width: 100vw !important; min-width: 0 !important; }',
    '[data-wa-col] { min-width: 0 !important; max-width: none !important; }',
    // список
    'html:not(.wa-chat) [data-wa-col="main"], html:not(.wa-chat) [data-wa-col="panel"] { display: none !important; }',
    'html:not(.wa-chat) [data-wa-col="side"] { flex: 1 1 auto !important; width: auto !important; }',
    // чат
    'html.wa-chat [data-wa-col="side"], html.wa-chat [data-wa-col="rail"] { display: none !important; }',
    'html.wa-chat:not(.wa-panel) [data-wa-col="panel"] { display: none !important; }',
    'html.wa-chat:not(.wa-panel) [data-wa-col="main"] { flex: 1 1 auto !important; width: 100% !important; }',
    // панель поверх чата
    'html.wa-chat.wa-panel [data-wa-col="main"] { display: none !important; }',
    'html.wa-chat.wa-panel [data-wa-col="panel"][data-wa-open] { flex: 1 1 auto !important; width: 100% !important; }',
    'html.wa-chat.wa-panel [data-wa-col="panel"]:not([data-wa-open]) { display: none !important; }',
    'html.wa-chat.wa-panel [data-wa-col="panel"][data-wa-open] > * { width: 100% !important; max-width: none !important; }'
  ].join('\n');

  function ensureStyle() {
    if (document.getElementById('wa-mobile-style')) return;
    var style = document.createElement('style');
    style.id = 'wa-mobile-style';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }

  function inFlow(el) {
    var p = getComputedStyle(el).position;
    return p !== 'absolute' && p !== 'fixed';
  }

  function set(el, name, value) {
    if (value === null) { if (el.hasAttribute(name)) el.removeAttribute(name); }
    else if (el.getAttribute(name) !== value) el.setAttribute(name, value);
  }

  // Общий контейнер колонок: ближайший предок #side, у которого после колонки списка
  // есть ещё колонка в потоке (чат или заставка).
  function findColumns(side) {
    var col = side;
    while (col.parentElement && col.parentElement !== document.body) {
      var parent = col.parentElement;
      for (var next = col.nextElementSibling; next; next = next.nextElementSibling) {
        if (inFlow(next)) return { root: parent, side: col };
      }
      col = parent;
    }
    return null;
  }

  var panelOpen = false;

  function tag() {
    var side = document.getElementById('side');
    if (!side) return;
    var found = findColumns(side);
    if (!found) return;
    var root = found.root;
    set(root, 'data-wa-root', '');

    var after = false, mainSeen = false;
    panelOpen = false;
    for (var i = 0; i < root.children.length; i++) {
      var child = root.children[i];
      if (child === found.side) { set(child, 'data-wa-col', 'side'); after = true; continue; }
      if (!inFlow(child)) { set(child, 'data-wa-col', null); continue; }
      if (!after) { set(child, 'data-wa-col', 'rail'); continue; }
      if (!mainSeen) { set(child, 'data-wa-col', 'main'); mainSeen = true; continue; }
      set(child, 'data-wa-col', 'panel');
      // Закрытая панель: пустой первый ребёнок. Открытая: в нём есть содержимое.
      var first = child.firstElementChild;
      var open = !!(first && first.childElementCount > 0);
      set(child, 'data-wa-open', open ? '' : null);
      if (open) panelOpen = true;
    }
  }

  var lastChat = null;
  function updateMode() {
    var chat = !!document.getElementById('main');
    var html = document.documentElement;
    html.classList.toggle('wa-chat', chat);
    html.classList.toggle('wa-panel', chat && panelOpen);
    if (chat !== lastChat) {
      lastChat = chat;
      post({ type: 'mode', chat: chat });
    }
  }

  // setTimeout, а не requestAnimationFrame: rAF стоит на паузе в скрытых WebView и фоновых вкладках.
  var scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(function () {
      scheduled = false;
      ensureViewport();
      ensureStyle();
      tag();
      updateMode();
    }, 30);
  }

  // Штатное закрытие в WhatsApp Web: Escape закрывает панель, потом чат.
  function back() {
    var target = document.activeElement || document.body;
    ['keydown', 'keyup'].forEach(function (type) {
      target.dispatchEvent(new KeyboardEvent(type, {
        key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true, cancelable: true
      }));
    });
  }

  ensureViewport();
  ensureStyle();
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  schedule();

  window.__waMobile = {
    back: back,
    refresh: schedule,
    version: 2,
    state: function () {
      return { chat: !!document.getElementById('main'), panel: panelOpen };
    }
  };
})();
