// wa-mobile v5
// Мобильная обёртка WhatsApp Web: одна колонка за раз, как в приложении.
// Режим «список»: только список чатов. Режим «чат»: только открытый чат на весь экран.
// Если открыта панель (инфо о контакте, поиск по чату), на весь экран показывается она.
//
// Раскладка WhatsApp Web (проверено 2026-10): общий flex-контейнер, в нём по порядку
//   HEADER (полоса иконок) | [absolute-слои левых панелей] | колонка #side | колонка чата (#main или заставка)
//   | [absolute-слой] | колонка панели | ... | #wds-toast-container (fixed)
// Absolute-слои перед списком декоративные (pointer-events: none), рисуют рамки по краям десктопных колонок:
// в режиме чата прячем их, в режиме списка убираем рамки. Остальные absolute/fixed не трогаем.
//
// Производительность: WhatsApp меняет DOM десятки раз в секунду. Поэтому
//   - getComputedStyle только когда поменялся состав колонок (кэш по списку детей контейнера);
//   - поиск новых сообщений только когда поменялся заголовок вкладки (счётчик непрочитанных);
//   - все проверки склеиваются в один проход не чаще раза в 60 мс.
(function () {
  if (window.__waMobile) return;

  var post = function (msg) {
    try { window.webkit.messageHandlers.wa.postMessage(msg); } catch (e) {}
  };

  // maximum-scale=1 убирает автозум iOS при фокусе на поле ввода.
  var VIEWPORT = 'width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover';
  function ensureViewport() {
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'viewport';
      (document.head || document.documentElement).appendChild(meta);
    }
    if (meta.content !== VIEWPORT) meta.content = VIEWPORT;
  }

  var css = [
    'html.wa-ready, html.wa-ready body { overflow-x: hidden !important; }',
    '[data-wa-root] { width: 100vw !important; min-width: 0 !important; }',
    '[data-wa-col] { min-width: 0 !important; max-width: none !important; }',
    // список
    'html:not(.wa-chat) [data-wa-col="main"], html:not(.wa-chat) [data-wa-col="panel"] { display: none !important; }',
    'html:not(.wa-chat) [data-wa-col="side"] { flex: 1 1 auto !important; width: auto !important; }',
    // Декоративный слой с рамками по краям десктопных колонок (pointer-events: none): на телефоне это полосы.
    '[data-wa-col="layer"] * { border-left-width: 0 !important; border-right-width: 0 !important; }',
    // Без анимаций WhatsApp Web на телефоне заметно отзывчивее (переключатель в «Управлении»).
    'html.wa-nomotion *, html.wa-nomotion *::before, html.wa-nomotion *::after { animation-duration: 0.001s !important; animation-delay: 0s !important; animation-iteration-count: 1 !important; transition-duration: 0.001s !important; transition-delay: 0s !important; }',
    // чат
    'html.wa-chat [data-wa-col="side"], html.wa-chat [data-wa-col="rail"], html.wa-chat [data-wa-col="layer"] { display: none !important; }',
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

  // ---------- Колонки ----------
  var root = null, sideCol = null, children = [], panels = [];
  var panelOpen = false;

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

  function sameChildren() {
    var list = root.children;
    if (list.length !== children.length) return false;
    for (var i = 0; i < list.length; i++) if (list[i] !== children[i]) return false;
    return true;
  }

  // Дорогая часть (getComputedStyle): только когда поменялся состав колонок.
  function classify() {
    children = Array.prototype.slice.call(root.children);
    panels = [];
    var after = false, mainSeen = false;
    for (var i = 0; i < children.length; i++) {
      var child = children[i];
      if (child === sideCol) { set(child, 'data-wa-col', 'side'); after = true; continue; }
      if (!inFlow(child)) { set(child, 'data-wa-col', after ? null : 'layer'); continue; }
      if (!after) { set(child, 'data-wa-col', 'rail'); continue; }
      if (!mainSeen) { set(child, 'data-wa-col', 'main'); mainSeen = true; continue; }
      set(child, 'data-wa-col', 'panel');
      panels.push(child);
    }
  }

  function tag() {
    var side = document.getElementById('side');
    if (!side) return;
    if (!root || !root.isConnected || !sideCol || !sideCol.contains(side) || sideCol.parentElement !== root) {
      var found = findColumns(side);
      if (!found) return;
      root = found.root;
      sideCol = found.side;
      children = [];
      set(root, 'data-wa-root', '');
      // Вошли в аккаунт: теперь можно запрещать горизонтальную прокрутку (на экране входа она нужна).
      document.documentElement.classList.add('wa-ready');
    }
    if (!sameChildren()) classify();

    // Дешёвая часть каждый проход: открыта ли панель справа от чата.
    panelOpen = false;
    for (var i = 0; i < panels.length; i++) {
      var first = panels[i].firstElementChild;
      var open = !!(first && first.childElementCount > 0);
      set(panels[i], 'data-wa-open', open ? '' : null);
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

  // ---------- Новые сообщения ----------
  // Строка чата с непрочитанными: [role=row] с меткой aria-label «N непрочитанное сообщение».
  // Внутри два span[title]: имя чата и превью последнего сообщения.
  var UNREAD_RE = /(\d+)\s*(непрочит|unread)/i;
  var unreadByChat = null;   // null до первого прохода: при запуске не уведомляем о старом
  var lastTitle = null;

  function scanMessages() {
    var pane = document.getElementById('pane-side');
    if (!pane) return;
    // Счётчик непрочитанных в заголовке не поменялся: новых сообщений нет, список не трогаем.
    if (unreadByChat && document.title === lastTitle) return;
    lastTitle = document.title;
    var current = {};
    var rows = pane.querySelectorAll('[role="row"]');
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      var count = 0;
      var labelled = row.querySelectorAll('[aria-label]');
      for (var j = 0; j < labelled.length; j++) {
        var m = UNREAD_RE.exec(labelled[j].getAttribute('aria-label'));
        if (m) { count = parseInt(m[1], 10); break; }
      }
      var titles = row.querySelectorAll('span[title]');
      var name = titles[0] ? titles[0].getAttribute('title') : '';
      if (!name) continue;
      current[name] = count;
      if (unreadByChat && count > (unreadByChat[name] || 0)) {
        post({ type: 'message', chat: name, preview: titles[1] ? titles[1].getAttribute('title') : '', count: count });
      }
    }
    // Чаты, которые ушли из видимой части списка, помним со старым счётчиком.
    if (unreadByChat) for (var k in unreadByChat) if (!(k in current)) current[k] = unreadByChat[k];
    unreadByChat = current;
  }

  // ---------- Звонки ----------
  // Окно звонка: [role=application] (плавающее окно). Входящий: есть кнопка «Принять».
  // Идёт разговор: есть «Завершить звонок». Заголовок вкладки: «Входящий аудиозвонок от Имя».
  var ACCEPT = ['Принять', 'Accept'];
  var DECLINE = ['Отклонить', 'Decline'];
  var HANGUP = ['Завершить звонок', 'End call'];
  var callState = 'none';

  function findButton(labels) {
    var win = document.querySelector('[role="application"]');
    if (!win) return null;
    var buttons = win.querySelectorAll('button, [role="button"]');
    for (var i = 0; i < buttons.length; i++) {
      var label = buttons[i].getAttribute('aria-label') || buttons[i].getAttribute('title') || '';
      for (var j = 0; j < labels.length; j++) if (label === labels[j]) return buttons[i];
    }
    return null;
  }

  function scanCall() {
    var state = 'none';
    if (document.querySelector('[role="application"]')) {
      if (findButton(ACCEPT)) state = 'incoming';
      else if (findButton(HANGUP)) state = 'active';
    }
    if (state === callState) return;
    var msg = { type: 'call', state: state, from: callState };
    if (state === 'incoming') {
      var t = document.title;
      var m = /от\s+(.+)$/i.exec(t) || /from\s+(.+)$/i.exec(t);
      msg.caller = m ? m[1].trim() : '';
      msg.video = /видео|video/i.test(t);
    }
    callState = state;
    post(msg);
  }

  function press(labels) {
    var b = findButton(labels);
    if (b) b.click();
    return !!b;
  }

  // ---------- Фон ----------
  // Почти беззвучный звук в цикле: пока он играет, iOS не замораживает страницу в свёрнутом приложении.
  var keepAlive = null;
  function silentWav() {
    var rate = 8000, n = rate; // 1 секунда
    var buf = new ArrayBuffer(44 + n * 2), v = new DataView(buf);
    function s(o, str) { for (var i = 0; i < str.length; i++) v.setUint8(o + i, str.charCodeAt(i)); }
    s(0, 'RIFF'); v.setUint32(4, 36 + n * 2, true); s(8, 'WAVE'); s(12, 'fmt ');
    v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
    v.setUint32(24, rate, true); v.setUint32(28, rate * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true);
    s(36, 'data'); v.setUint32(40, n * 2, true);
    for (var i = 0; i < n; i++) v.setInt16(44 + i * 2, (i % 2) ? 1 : -1, true);
    return URL.createObjectURL(new Blob([buf], { type: 'audio/wav' }));
  }
  function setKeepAlive(on) {
    if (on && !keepAlive) {
      keepAlive = new Audio(silentWav());
      keepAlive.loop = true;
      keepAlive.volume = 0.01;
      keepAlive.play().catch(function () {});
    } else if (!on && keepAlive) {
      keepAlive.pause();
      keepAlive = null;
    }
  }

  // ---------- Цикл ----------
  // setTimeout, а не requestAnimationFrame: rAF стоит на паузе в скрытых WebView и фоновых вкладках.
  var scheduled = false;
  function run() {
    scheduled = false;
    ensureStyle();
    tag();
    updateMode();
    scanCall();
    scanMessages();
  }
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(run, 60);
  }
  // Подстраховка, если мутаций нет, а состояние поменялось.
  setInterval(schedule, 2000);

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
  // Viewport WhatsApp ставит один раз при загрузке, следить за ним в каждом проходе незачем.
  setTimeout(ensureViewport, 3000);
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  schedule();
  post({ type: 'ready', version: 5 });

  window.__waMobile = {
    back: back,
    refresh: schedule,
    version: 5,
    acceptCall: function () { return press(ACCEPT); },
    declineCall: function () { return press(DECLINE); },
    endCall: function () { return press(HANGUP) || press(DECLINE); },
    keepAlive: setKeepAlive,
    reduceMotion: function (on) { document.documentElement.classList.toggle('wa-nomotion', !!on); },
    state: function () {
      return { chat: !!document.getElementById('main'), panel: panelOpen, call: callState };
    }
  };
})();
