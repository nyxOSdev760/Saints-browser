import Foundation

/// JavaScript that implements the WebExtension (`browser` / `chrome`) and Greasemonkey (`GM_*` / `GM.*`)
/// APIs on top of the native `saintsExt` message handler. One copy is injected per extension into that
/// extension's isolated content world, and into its background / popup / options pages.
enum ExtensionRuntimeJS {
    static func shim(config: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: config)) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return source.replacingOccurrences(of: "__SAINTS_CONFIG__", with: json)
    }

    private static let source = #"""
(function () {
  'use strict';
  if (globalThis.__saintsRuntime) return;
  const CFG = __SAINTS_CONFIG__;
  const handler = (globalThis.webkit && webkit.messageHandlers && webkit.messageHandlers.saintsExt) || null;
  const post = (action, payload) => {
    if (!handler) return Promise.reject(new Error('Saints extension bridge unavailable'));
    return handler.postMessage({ action: action, payload: payload === undefined ? null : payload });
  };

  let lastError = null;
  function Ev() {
    const ls = new Set();
    return {
      addListener(f) { if (typeof f === 'function') ls.add(f); },
      removeListener(f) { ls.delete(f); },
      hasListener(f) { return ls.has(f); },
      hasListeners() { return ls.size > 0; },
      _fire(...args) { for (const f of Array.from(ls)) { try { f(...args); } catch (e) { console.error('[Saints ext]', e); } } },
      _ls: ls
    };
  }
  // Supports both promise style (browser.*) and callback style (chrome.*).
  function cb(fn) {
    return function (...args) {
      const last = args[args.length - 1];
      if (typeof last === 'function') {
        args.pop();
        Promise.resolve().then(() => fn(...args)).then(
          (r) => { try { last(r); } catch (e) { console.error(e); } },
          (e) => { lastError = { message: String((e && e.message) || e) }; try { last(); } finally { lastError = null; } });
        return undefined;
      }
      return fn(...args);
    };
  }
  const noop = () => Promise.resolve();

  // ---------- runtime ----------
  const onMessage = Ev();
  const onInstalled = Ev();
  const onStartup = Ev();
  const onConnect = Ev();
  const getURL = (p) => CFG.baseURL + String(p || '').replace(/^\/+/, '');

  globalThis.__saintsDispatchMessage = function (msg, sender) {
    return new Promise((resolve) => {
      let done = false;
      const respond = (v) => { if (!done) { done = true; resolve(v === undefined ? null : v); } };
      let pending = false;
      for (const l of Array.from(onMessage._ls)) {
        try {
          const r = l(msg, sender || {}, respond);
          if (r && typeof r.then === 'function') { pending = true; r.then((v) => respond(v), () => respond(null)); }
          else if (r === true) { pending = true; }
        } catch (e) { console.error('[Saints ext] onMessage', e); }
      }
      if (!pending) respond(null);
      else setTimeout(() => respond(null), 30000);
    });
  };
  globalThis.__saintsFire = function (name, args) {
    const ev = EVENTS[name];
    if (ev) ev._fire(...(args || []));
    return true;
  };

  const runtime = {
    id: CFG.id,
    get lastError() { return lastError; },
    getURL,
    getManifest: () => CFG.manifest,
    getPlatformInfo: cb(() => Promise.resolve({ os: 'ios', arch: 'arm64', nacl_arch: 'arm' })),
    getBrowserInfo: cb(() => Promise.resolve({ name: 'Saints', vendor: 'Saints', version: CFG.browserVersion, buildID: '1' })),
    sendMessage: cb(function (...args) {
      if (args.length >= 2 && typeof args[0] === 'string' && args[0] === CFG.id) args.shift();
      return post('runtime.sendMessage', { message: args[0] });
    }),
    connect: function (name) {
      const port = { name: (name && name.name) || '', onMessage: Ev(), onDisconnect: Ev(),
        postMessage(m) { post('runtime.sendMessage', { message: m, port: port.name }).then((r) => { if (r != null) port.onMessage._fire(r, port); }); },
        disconnect() {} };
      return port;
    },
    openOptionsPage: cb(() => post('runtime.openOptionsPage')),
    setUninstallURL: cb(noop),
    reload: () => {},
    requestUpdateCheck: cb(() => Promise.resolve(['no_update'])),
    onMessage, onInstalled, onStartup, onConnect,
    onMessageExternal: Ev(), onConnectExternal: Ev(), onSuspend: Ev(), onUpdateAvailable: Ev()
  };

  // ---------- storage ----------
  const onChanged = Ev();
  const area = (name) => {
    const a = {
      get: cb((keys) => post('storage.get', { area: name, keys: keys === undefined ? null : keys })),
      set: cb((items) => post('storage.set', { area: name, items: items || {} })),
      remove: cb((keys) => post('storage.remove', { area: name, keys })),
      clear: cb(() => post('storage.clear', { area: name })),
      getBytesInUse: cb(() => Promise.resolve(0)),
      setAccessLevel: cb(noop),
      onChanged: Ev(),
      QUOTA_BYTES: 10485760
    };
    return a;
  };
  const storage = { local: area('local'), sync: area('sync'), session: area('session'), managed: area('managed'), onChanged };
  globalThis.__saintsStorageChanged = function (changes, areaName) {
    onChanged._fire(changes, areaName);
    if (storage[areaName]) storage[areaName].onChanged._fire(changes);
    return true;
  };

  // ---------- i18n ----------
  const i18n = {
    getMessage(name, subs) {
      const m = CFG.messages && CFG.messages[String(name).toLowerCase()];
      if (!m) return '';
      let text = m.message || '';
      const list = subs === undefined ? [] : (Array.isArray(subs) ? subs : [subs]);
      if (m.placeholders) {
        for (const k of Object.keys(m.placeholders)) {
          const content = String(m.placeholders[k].content || '').replace(/\$(\d)/g, (_, n) => list[n - 1] ?? '');
          text = text.replace(new RegExp('\\$' + k + '\\$', 'gi'), content);
        }
      }
      return text.replace(/\$(\d)/g, (_, n) => list[n - 1] ?? '').replace(/\$\$/g, '$');
    },
    getUILanguage: () => (navigator.language || 'en-US').replace('-', '_'),
    getAcceptLanguages: cb(() => Promise.resolve(navigator.languages || ['en-US'])),
    detectLanguage: cb(() => Promise.resolve({ isReliable: false, languages: [] }))
  };

  // ---------- tabs / scripting ----------
  const tabs = {
    TAB_ID_NONE: -1,
    query: cb((q) => post('tabs.query', q || {})),
    get: cb((id) => post('tabs.get', { tabId: id })),
    getCurrent: cb(() => post('tabs.getCurrent')),
    create: cb((props) => post('tabs.create', props || {})),
    update: cb((a, b) => post('tabs.update', typeof a === 'number' ? { tabId: a, props: b || {} } : { tabId: null, props: a || {} })),
    remove: cb((ids) => post('tabs.remove', { tabIds: Array.isArray(ids) ? ids : [ids] })),
    reload: cb((id) => post('tabs.reload', { tabId: typeof id === 'number' ? id : null })),
    sendMessage: cb((tabId, message) => post('tabs.sendMessage', { tabId, message })),
    executeScript: cb((a, b) => {
      const d = typeof a === 'number' ? b : a;
      return post('tabs.executeScript', { tabId: typeof a === 'number' ? a : null, code: d && d.code, file: d && d.file, allFrames: !!(d && d.allFrames) });
    }),
    insertCSS: cb((a, b) => {
      const d = typeof a === 'number' ? b : a;
      return post('tabs.insertCSS', { tabId: typeof a === 'number' ? a : null, code: d && d.code, file: d && d.file });
    }),
    removeCSS: cb(noop),
    captureVisibleTab: cb(() => post('tabs.captureVisibleTab')),
    detectLanguage: cb(() => Promise.resolve('und')),
    getZoom: cb(() => Promise.resolve(1)), setZoom: cb(noop),
    onUpdated: Ev(), onActivated: Ev(), onCreated: Ev(), onRemoved: Ev(), onReplaced: Ev(), onHighlighted: Ev(), onMoved: Ev(), onAttached: Ev(), onDetached: Ev()
  };
  const scripting = {
    executeScript: cb((inj) => post('scripting.executeScript', {
      tabId: inj && inj.target ? inj.target.tabId : null,
      allFrames: !!(inj && inj.target && inj.target.allFrames),
      func: inj && inj.func ? String(inj.func) : null,
      args: (inj && inj.args) || [],
      files: (inj && inj.files) || [],
      world: (inj && inj.world) || 'ISOLATED'
    })),
    insertCSS: cb((inj) => post('tabs.insertCSS', { tabId: inj && inj.target ? inj.target.tabId : null, code: inj && inj.css, file: inj && inj.files && inj.files[0] })),
    removeCSS: cb(noop),
    registerContentScripts: cb(noop), unregisterContentScripts: cb(noop), getRegisteredContentScripts: cb(() => Promise.resolve([]))
  };
  const windows = {
    WINDOW_ID_CURRENT: -2, WINDOW_ID_NONE: -1,
    getCurrent: cb(() => Promise.resolve({ id: 1, focused: true, type: 'normal', incognito: false, state: 'fullscreen' })),
    getLastFocused: cb(() => Promise.resolve({ id: 1, focused: true, type: 'normal', incognito: false })),
    getAll: cb(() => Promise.resolve([{ id: 1, focused: true, type: 'normal', incognito: false }])),
    get: cb(() => Promise.resolve({ id: 1, focused: true, type: 'normal', incognito: false })),
    create: cb((d) => post('tabs.create', { url: d && (Array.isArray(d.url) ? d.url[0] : d.url) })),
    update: cb(noop), remove: cb(noop),
    onFocusChanged: Ev(), onCreated: Ev(), onRemoved: Ev()
  };

  // ---------- action / notifications / misc ----------
  const action = {
    setBadgeText: cb(noop), getBadgeText: cb(() => Promise.resolve('')), setBadgeBackgroundColor: cb(noop),
    setBadgeTextColor: cb(noop), setTitle: cb(noop), getTitle: cb(() => Promise.resolve(CFG.actionTitle || '')),
    setIcon: cb(noop), setPopup: cb(noop), getPopup: cb(() => Promise.resolve(CFG.popup || '')),
    enable: cb(noop), disable: cb(noop), openPopup: cb(() => post('action.openPopup')),
    onClicked: Ev()
  };
  const notifications = {
    create: cb((a, b) => {
      const opts = typeof a === 'string' ? b : a;
      const id = typeof a === 'string' ? a : 'n' + Date.now();
      return post('notifications.create', { title: opts && opts.title, message: opts && opts.message }).then(() => id);
    }),
    clear: cb(() => Promise.resolve(true)), getAll: cb(() => Promise.resolve({})), update: cb(() => Promise.resolve(true)),
    onClicked: Ev(), onClosed: Ev(), onButtonClicked: Ev(), onShown: Ev()
  };
  const alarmTimers = {};
  const onAlarm = Ev();
  const alarms = {
    create(name, info) {
      if (typeof name === 'object') { info = name; name = ''; }
      name = name || '';
      info = info || {};
      alarms.clear(name);
      const delay = info.when ? Math.max(0, info.when - Date.now()) : (info.delayInMinutes || info.periodInMinutes || 0) * 60000;
      const alarm = { name, scheduledTime: Date.now() + delay, periodInMinutes: info.periodInMinutes };
      alarmTimers[name] = { alarm, t: setTimeout(function tick() {
        onAlarm._fire(alarm);
        if (info.periodInMinutes) { alarm.scheduledTime = Date.now() + info.periodInMinutes * 60000; alarmTimers[name].t = setTimeout(tick, info.periodInMinutes * 60000); }
        else delete alarmTimers[name];
      }, delay) };
      return Promise.resolve();
    },
    get: cb((name) => Promise.resolve(alarmTimers[name || ''] ? alarmTimers[name || ''].alarm : undefined)),
    getAll: cb(() => Promise.resolve(Object.values(alarmTimers).map((x) => x.alarm))),
    clear: cb((name) => { const x = alarmTimers[name || '']; if (x) { clearTimeout(x.t); delete alarmTimers[name || '']; } return Promise.resolve(!!x); }),
    clearAll: cb(() => { for (const k of Object.keys(alarmTimers)) { clearTimeout(alarmTimers[k].t); delete alarmTimers[k]; } return Promise.resolve(true); }),
    onAlarm
  };
  const contextMenus = {
    create(props, done) { if (typeof done === 'function') setTimeout(done, 0); return (props && props.id) || Date.now(); },
    update: cb(noop), remove: cb(noop), removeAll: cb(noop), onClicked: Ev(), onShown: Ev(), onHidden: Ev(), refresh: () => {}
  };
  const permissions = {
    contains: cb(() => Promise.resolve(true)), request: cb(() => Promise.resolve(true)), remove: cb(() => Promise.resolve(true)),
    getAll: cb(() => Promise.resolve({ permissions: CFG.permissions || [], origins: CFG.hostPermissions || [] })),
    onAdded: Ev(), onRemoved: Ev()
  };
  const stubEvents = (names) => names.reduce((o, n) => { o[n] = Ev(); return o; }, {});
  const webRequest = stubEvents(['onBeforeRequest', 'onBeforeSendHeaders', 'onSendHeaders', 'onHeadersReceived', 'onAuthRequired', 'onResponseStarted', 'onBeforeRedirect', 'onCompleted', 'onErrorOccurred']);
  const webNavigation = Object.assign(stubEvents(['onBeforeNavigate', 'onCommitted', 'onDOMContentLoaded', 'onCompleted', 'onErrorOccurred', 'onHistoryStateUpdated', 'onReferenceFragmentUpdated', 'onCreatedNavigationTarget', 'onTabReplaced']), {
    getFrame: cb(() => Promise.resolve(null)), getAllFrames: cb(() => Promise.resolve([]))
  });
  const declarativeNetRequest = {
    getDynamicRules: cb(() => Promise.resolve([])), updateDynamicRules: cb(noop), getSessionRules: cb(() => Promise.resolve([])),
    updateSessionRules: cb(noop), getEnabledRulesets: cb(() => Promise.resolve(CFG.rulesets || [])), updateEnabledRulesets: cb(noop),
    isRegexSupported: cb(() => Promise.resolve({ isSupported: true })), MAX_NUMBER_OF_DYNAMIC_RULES: 5000, onRuleMatchedDebug: Ev()
  };
  const EVENTS = {
    'runtime.onInstalled': onInstalled, 'runtime.onStartup': onStartup, 'action.onClicked': action.onClicked,
    'tabs.onUpdated': tabs.onUpdated, 'tabs.onActivated': tabs.onActivated, 'tabs.onCreated': tabs.onCreated,
    'tabs.onRemoved': tabs.onRemoved, 'alarms.onAlarm': onAlarm, 'contextMenus.onClicked': contextMenus.onClicked
  };

  const api = {
    runtime, storage, i18n, tabs, scripting, windows, action, browserAction: action, pageAction: action,
    notifications, alarms, contextMenus, menus: contextMenus, permissions, webRequest, webNavigation, declarativeNetRequest,
    extension: { getURL, inIncognitoContext: !!CFG.incognito, isAllowedIncognitoAccess: cb(() => Promise.resolve(!!CFG.allowPrivate)), getBackgroundPage: () => null, getViews: () => [], lastError: null },
    commands: { getAll: cb(() => Promise.resolve([])), onCommand: Ev() },
    cookies: { get: cb(() => Promise.resolve(null)), getAll: cb(() => Promise.resolve([])), set: cb(noop), remove: cb(noop), onChanged: Ev() },
    history: { search: cb(() => Promise.resolve([])), addUrl: cb(noop), deleteUrl: cb(noop), onVisited: Ev() },
    bookmarks: { search: cb(() => Promise.resolve([])), getTree: cb(() => Promise.resolve([])), create: cb(noop), onCreated: Ev() },
    downloads: { download: cb((o) => post('tabs.create', { url: o && o.url })), search: cb(() => Promise.resolve([])), onChanged: Ev() },
    idle: { queryState: cb(() => Promise.resolve('active')), setDetectionInterval: () => {}, onStateChanged: Ev() },
    offscreen: { createDocument: cb(noop), closeDocument: cb(noop), hasDocument: cb(() => Promise.resolve(false)) },
    sidePanel: { setOptions: cb(noop), setPanelBehavior: cb(noop), open: cb(noop) },
    theme: { getCurrent: cb(() => Promise.resolve({})), onUpdated: Ev() }
  };

  globalThis.__saintsRuntime = api;
  if (!globalThis.browser || !globalThis.browser.runtime || !globalThis.browser.runtime.id) globalThis.browser = api;
  if (!globalThis.chrome || !globalThis.chrome.runtime || !globalThis.chrome.runtime.id) globalThis.chrome = api;

  if (CFG.context === 'background') {
    globalThis.importScripts = function (...urls) {
      for (const u of urls) {
        const x = new XMLHttpRequest();
        x.open('GET', new URL(u, location.href).href, false);
        x.send();
        (0, eval)(x.responseText + '\n//# sourceURL=' + u);
      }
    };
  }

  // ---------- Greasemonkey / Tampermonkey API (userscripts) ----------
  if (CFG.kind === 'userScript') {
    let values = {};
    const ready = post('storage.get', { area: 'gm', keys: null }).then((v) => { values = v || {}; }, () => {});
    globalThis.__saintsGMReady = ready;
    const GM_info = { script: { name: CFG.name, version: CFG.version, description: CFG.description, namespace: '' }, scriptHandler: 'Saints', version: CFG.browserVersion, platform: { os: 'ios' } };
    const GM_getValue = (k, d) => (Object.prototype.hasOwnProperty.call(values, k) ? values[k] : d);
    const GM_setValue = (k, v) => { values[k] = v; post('storage.set', { area: 'gm', items: { [k]: v } }); };
    const GM_deleteValue = (k) => { delete values[k]; post('storage.remove', { area: 'gm', keys: k }); };
    const GM_listValues = () => Object.keys(values);
    const GM_addStyle = (css) => {
      const s = document.createElement('style');
      s.textContent = css;
      (document.head || document.documentElement).appendChild(s);
      return s;
    };
    const GM_addElement = (a, b, c) => {
      const parent = typeof a === 'string' ? (document.head || document.documentElement) : a;
      const tag = typeof a === 'string' ? a : b;
      const attrs = (typeof a === 'string' ? b : c) || {};
      const el = document.createElement(tag);
      for (const k of Object.keys(attrs)) { if (k === 'textContent') el.textContent = attrs[k]; else el.setAttribute(k, attrs[k]); }
      parent.appendChild(el);
      return el;
    };
    const GM_xmlhttpRequest = (d) => {
      const p = post('gm.xhr', { method: d.method || 'GET', url: new URL(d.url, location.href).href, headers: d.headers || {}, data: d.data == null ? null : String(d.data), timeout: d.timeout || 0 });
      p.then((r) => {
        const resp = Object.assign({}, r, { readyState: 4, context: d.context });
        if (d.responseType === 'json') { try { resp.response = JSON.parse(r.responseText); } catch (e) { resp.response = null; } }
        else resp.response = r.responseText;
        if (d.onreadystatechange) d.onreadystatechange(resp);
        if (d.onload) d.onload(resp);
        if (d.onloadend) d.onloadend(resp);
      }, (e) => {
        const resp = { status: 0, statusText: String(e), readyState: 4, responseText: '', error: String(e) };
        if (d.onerror) d.onerror(resp);
        if (d.onloadend) d.onloadend(resp);
      });
      return { abort() {} };
    };
    const GM_openInTab = (url, opts) => { post('tabs.create', { url: new URL(url, location.href).href, active: !(opts === true || (opts && opts.active === false)) }); return { close() {}, closed: false }; };
    const GM_setClipboard = (text) => { post('clipboard.set', { text: String(text) }); };
    const GM_notification = (a, b) => { const d = typeof a === 'string' ? { text: a, title: b } : (a || {}); post('notifications.create', { title: d.title || CFG.name, message: d.text || '' }); };
    const GM_registerMenuCommand = (name, fn) => { (globalThis.__saintsMenu = globalThis.__saintsMenu || []).push({ name, fn }); return name; };
    const GM_log = (...a) => console.log('[' + CFG.name + ']', ...a);
    Object.assign(globalThis, {
      GM_info, GM_getValue, GM_setValue, GM_deleteValue, GM_listValues, GM_addStyle, GM_addElement, GM_xmlhttpRequest,
      GM_openInTab, GM_setClipboard, GM_notification, GM_registerMenuCommand, GM_unregisterMenuCommand: () => {}, GM_log,
      GM_getResourceText: () => '', GM_getResourceURL: () => '', unsafeWindow: globalThis,
      GM: {
        info: GM_info,
        getValue: (k, d) => ready.then(() => GM_getValue(k, d)),
        setValue: (k, v) => Promise.resolve(GM_setValue(k, v)),
        deleteValue: (k) => Promise.resolve(GM_deleteValue(k)),
        listValues: () => ready.then(GM_listValues),
        addStyle: (c) => Promise.resolve(GM_addStyle(c)),
        addElement: (a, b, c) => Promise.resolve(GM_addElement(a, b, c)),
        xmlHttpRequest: (d) => new Promise((res, rej) => GM_xmlhttpRequest(Object.assign({}, d, { onload: (r) => { d.onload && d.onload(r); res(r); }, onerror: (r) => { d.onerror && d.onerror(r); rej(r); } }))),
        openInTab: (u, o) => Promise.resolve(GM_openInTab(u, o)),
        setClipboard: (t) => Promise.resolve(GM_setClipboard(t)),
        notification: (a, b) => Promise.resolve(GM_notification(a, b)),
        registerMenuCommand: (n, f) => Promise.resolve(GM_registerMenuCommand(n, f))
      }
    });
  }
})();
"""#

    /// Wraps one content-script entry so it only runs on matching URLs.
    static func contentScript(extID: String, include: [String], exclude: [String], css: String, js: String, waitForGM: Bool) -> String {
        func jsArray(_ items: [String]) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: items)) ?? Data("[]".utf8)
            return String(data: data, encoding: .utf8) ?? "[]"
        }
        func jsString(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
            let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
            return String(arr.dropFirst().dropLast())
        }
        var out = """
        (function () {
          const __href = String(location.href).split('#')[0];
          const __test = (list) => list.some((r) => { try { return new RegExp(r).test(__href); } catch (e) { return false; } });
          if (!__test(\(jsArray(include)))) return;
          if (__test(\(jsArray(exclude)))) return;

        """
        if !css.isEmpty {
            out += """
              (function (css) {
                const add = () => {
                  const s = document.createElement('style');
                  s.setAttribute('data-saints-ext', '\(extID)');
                  s.textContent = css;
                  (document.head || document.documentElement).appendChild(s);
                };
                if (document.documentElement) add(); else document.addEventListener('DOMContentLoaded', add);
              })(\(jsString(css)));

            """
        }
        if !js.isEmpty {
            let start = waitForGM ? "(globalThis.__saintsGMReady || Promise.resolve()).then(() => __run.call(globalThis));"
                                  : "__run.call(globalThis);"
            out += "  const __run = function () {\n" + js + "\n};\n  try { " + start + " } catch (e) { console.error('[Saints ext]', e); }\n"
        }
        out += "})();\n"
        return out
    }
}
