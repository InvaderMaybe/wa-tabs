// wa-mobile v1
// Мобильная обёртка WhatsApp Web: одна колонка за раз, как в приложении.
// Режим «список»: только список чатов. Режим «чат»: только открытый чат на весь экран.
// Опирается на стабильные id (#side, #main), а не на обфусцированные классы.
(function () {
  if (window.__waMobile) return;

  var post = function (msg) {
    try { window.webkit.messageHandlers.wa.postMessage(msg); } catch (e) {}
  };

  // Без viewport WebKit верстает страницу шириной 980px. maximum-scale=1 убирает автозум при фокусе на поле ввода.
  function ensureViewport() {
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'viewport';
      (document.head || document.documentElement).appendChild(meta);
    }
    meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover';
  }

  var css = [
    'html, body { overflow-x: hidden !important; }',
    '[data-wa-root] { display: flex !important; flex-direction: row !important; width: 100vw !important; min-width: 0 !important; }',
    '[data-wa-col] { min-width: 0 !important; max-width: none !important; }',
    'html:not(.wa-chat) [data-wa-col="main"] { display: none !important; }',
    'html:not(.wa-chat) [data-wa-col="side"] { flex: 1 1 auto !important; width: auto !important; }',
    'html.wa-chat [data-wa-col="side"], html.wa-chat [data-wa-col="rail"] { display: none !important; }',
    'html.wa-chat [data-wa-col="main"] { flex: 1 1 auto !important; width: 100% !important; }',
    // Если рядом с чатом открыта панель (инфо о контакте, поиск), показываем только её.
    'html.wa-chat.wa-panel [data-wa-col="main"]:not([data-wa-last]) { display: none !important; }'
  ].join('\n');

  function ensureStyle() {
    if (document.getElementById('wa-mobile-style')) return;
    var style = document.createElement('style');
    style.id = 'wa-mobile-style';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }

  var root = null;

  // Поднимаемся от #side до контейнера, где справа есть видимая колонка (чат или заставка).
  function findRoot(side) {
    var col = side;
    while (col.parentElement && col.parentElement !== document.body) {
      var parent = col.parentElement;
      var next = col.nextElementSibling;
      while (next && next.getBoundingClientRect().width < 100) next = next.nextElementSibling;
      if (next) return { root: parent, side: col };
      col = parent;
    }
    return null;
  }

  function tag() {
    var side = document.getElementById('side');
    if (!side) return;

    if (!root || !root.isConnected || !root.contains(side)) {
      var found = findRoot(side);
      if (!found) return;
      root = found.root;
    }
    root.setAttribute('data-wa-root', '');

    var sideCol = null;
    for (var i = 0; i < root.children.length; i++) {
      if (root.children[i].contains(side)) { sideCol = root.children[i]; break; }
    }
    if (!sideCol) return;

    var mains = [];
    var before = true;
    for (var j = 0; j < root.children.length; j++) {
      var child = root.children[j];
      if (child === sideCol) { before = false; set(child, 'side'); continue; }
      if (before) { set(child, 'rail'); } else { set(child, 'main'); mains.push(child); }
    }

    // Колонки справа от чата, в которых что-то есть, это открытые панели.
    var withContent = mains.filter(function (el) { return el.childElementCount > 0; });
    mains.forEach(function (el) { el.removeAttribute('data-wa-last'); });
    var panelOpen = withContent.length > 1;
    if (panelOpen) withContent[withContent.length - 1].setAttribute('data-wa-last', '');
    document.documentElement.classList.toggle('wa-panel', panelOpen);
  }

  function set(el, value) {
    if (el.getAttribute('data-wa-col') !== value) el.setAttribute('data-wa-col', value);
  }

  var lastChat = null;
  function updateMode() {
    var chat = !!document.getElementById('main');
    document.documentElement.classList.toggle('wa-chat', chat);
    if (chat !== lastChat) {
      lastChat = chat;
      post({ type: 'mode', chat: chat });
    }
  }

  var scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(function () {
      scheduled = false;
      ensureStyle();
      tag();
      updateMode();
    });
  }

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

  window.__waMobile = { back: back, refresh: schedule, version: 1 };
})();
