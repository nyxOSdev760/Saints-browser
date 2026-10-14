import Foundation
import WebKit
import UIKit

// MARK: - Storage

/// Per-extension key/value storage for `browser.storage.*` and `GM_*Value`. Stored locally as JSON.
final class ExtensionStorage {
    static let shared = ExtensionStorage()
    private var cache: [String: [String: [String: Any]]] = [:]   // extID → area → values
    private let queue = DispatchQueue(label: "saints.ext.storage")

    private func url(_ extID: String) -> URL {
        ExtensionManager.shared.dataDir.appendingPathComponent("\(extID).json")
    }

    private func areas(_ extID: String) -> [String: [String: Any]] {
        if let c = cache[extID] { return c }
        var loaded: [String: [String: Any]] = [:]
        if let data = try? Data(contentsOf: url(extID)),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            loaded = obj
        }
        cache[extID] = loaded
        return loaded
    }

    private func persist(_ extID: String) {
        guard let value = cache[extID] else { return }
        // Session storage is memory-only.
        var copy = value
        copy.removeValue(forKey: "session")
        let target = url(extID)
        queue.async {
            if let data = try? JSONSerialization.data(withJSONObject: jsonSafe(copy)) {
                try? data.write(to: target, options: .atomic)
            }
        }
    }

    func get(extID: String, area: String, keys: Any?) -> [String: Any] {
        let values = areas(extID)[area] ?? [:]
        guard let keys, !(keys is NSNull) else { return values }
        switch keys {
        case let key as String: return values[key].map { [key: $0] } ?? [:]
        case let list as [String]:
            var out: [String: Any] = [:]
            for k in list { if let v = values[k] { out[k] = v } }
            return out
        case let defaults as [String: Any]:
            var out = defaults
            for k in defaults.keys { if let v = values[k] { out[k] = v } }
            return out
        default: return values
        }
    }

    /// Returns a `changes` object in WebExtension format.
    @discardableResult
    func set(extID: String, area: String, items: [String: Any]) -> [String: Any] {
        var all = areas(extID)
        var values = all[area] ?? [:]
        var changes: [String: Any] = [:]
        for (k, v) in items {
            var change: [String: Any] = ["newValue": v]
            if let old = values[k] { change["oldValue"] = old }
            changes[k] = change
            values[k] = v
        }
        all[area] = values
        cache[extID] = all
        persist(extID)
        return changes
    }

    @discardableResult
    func remove(extID: String, area: String, keys: Any?) -> [String: Any] {
        var all = areas(extID)
        var values = all[area] ?? [:]
        let list: [String] = (keys as? [String]) ?? ((keys as? String).map { [$0] } ?? [])
        var changes: [String: Any] = [:]
        for k in list {
            if let old = values.removeValue(forKey: k) { changes[k] = ["oldValue": old] }
        }
        all[area] = values
        cache[extID] = all
        persist(extID)
        return changes
    }

    @discardableResult
    func clear(extID: String, area: String) -> [String: Any] {
        var all = areas(extID)
        let old = all[area] ?? [:]
        all[area] = [:]
        cache[extID] = all
        persist(extID)
        return old.mapValues { ["oldValue": $0] } as [String: Any]
    }

    func drop(extID: String) { cache.removeValue(forKey: extID) }
}

/// Makes arbitrary bridged JS values JSON-serialisable (dates → ms timestamps, unknown → string).
func jsonSafe(_ value: Any) -> Any {
    switch value {
    case let d as [String: Any]: return d.mapValues(jsonSafe)
    case let a as [Any]: return a.map(jsonSafe)
    case let date as Date: return date.timeIntervalSince1970 * 1000
    case is NSNull, is String, is NSNumber: return value
    default: return String(describing: value)
    }
}

// MARK: - saints-ext:// scheme

final class ExtensionSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "saints-ext"
    static let shared = ExtensionSchemeHandler()

    static let mimeTypes: [String: String] = [
        "html": "text/html", "htm": "text/html", "js": "text/javascript", "mjs": "text/javascript",
        "css": "text/css", "json": "application/json", "png": "image/png", "jpg": "image/jpeg",
        "jpeg": "image/jpeg", "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp",
        "ico": "image/x-icon", "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf",
        "otf": "font/otf", "txt": "text/plain", "wasm": "application/wasm", "xml": "application/xml"
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let extID = url.host?.lowercased(),
              let ext = ExtensionManager.shared.extensionWith(id: extID) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let path = url.path.isEmpty ? "/" : url.path
        var data: Data?
        var mime = "application/octet-stream"

        if path == "/_generated_background.html" {
            data = Data(Self.backgroundHTML(for: ext).utf8)
            mime = "text/html"
        } else if let fileURL = ExtensionManager.shared.fileURL(extID: extID, path: path) {
            data = try? Data(contentsOf: fileURL)
            mime = Self.mimeTypes[fileURL.pathExtension.lowercased()] ?? mime
        }

        guard let body = data else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let headers = [
            "Content-Type": mime.hasPrefix("text/") || mime.hasSuffix("json") || mime.hasSuffix("javascript") ? "\(mime); charset=utf-8" : mime,
            "Content-Length": "\(body.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store"
        ]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static func backgroundHTML(for ext: WebExtension) -> String {
        if let page = ext.backgroundPage {
            return "<!doctype html><meta charset=utf-8><script>location.replace('/\(page)')</script>"
        }
        let type = ext.backgroundIsModule ? " type=\"module\"" : ""
        let tags = ext.backgroundScripts.map { "<script\(type) src=\"/\($0.trimmingCharacters(in: CharacterSet(charactersIn: "/")))\"></script>" }
        return "<!doctype html><html><head><meta charset=\"utf-8\"></head><body>\(tags.joined())</body></html>"
    }
}

// MARK: - Message handler

/// One handler instance per extension per context, so the extension identity is fixed at registration
/// time and cannot be spoofed by web content.
final class ExtensionMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    let extID: String
    let context: String

    init(extID: String, context: String) {
        self.extID = extID
        self.context = context
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
            replyHandler(nil, "Malformed message")
            return
        }
        let payload = body["payload"] as? [String: Any] ?? [:]
        ExtensionHost.shared.handle(action: action, payload: payload, extID: extID, context: context,
                                    message: message) { result, error in
            replyHandler(result.map(jsonSafe), error)
        }
    }
}

// MARK: - Host

final class ExtensionHost: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = ExtensionHost()

    private var backgrounds: [String: WKWebView] = [:]
    private var popups: [String: WeakWebView] = [:]

    /// Set by the UI to present popups / options pages.
    @Published var presentedPage: ExtensionPage?

    struct ExtensionPage: Identifiable {
        let id = UUID()
        let ext: WebExtension
        let path: String
        let context: String
    }

    final class WeakWebView { weak var webView: WKWebView?; init(_ w: WKWebView) { webView = w } }

    // MARK: Configurations

    /// Installs Saints' extension runtime into a tab's content controller.
    func install(into controller: WKUserContentController, isPrivate: Bool) {
        for ext in ExtensionManager.shared.activeExtensions where !isPrivate || ext.allowPrivate {
            let world = WKContentWorld.world(name: "saints-ext-\(ext.id)")
            let config = ExtensionManager.shared.runtimeConfig(for: ext, context: "content", incognito: isPrivate)
            controller.addScriptMessageHandler(ExtensionMessageHandler(extID: ext.id, context: "content"),
                                               contentWorld: world, name: "saintsExt")
            controller.addUserScript(WKUserScript(source: ExtensionRuntimeJS.shim(config: config),
                                                  injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
            for script in ExtensionManager.shared.contentScripts(for: ext) {
                controller.addUserScript(WKUserScript(source: script.source, injectionTime: script.time,
                                                      forMainFrameOnly: script.mainFrameOnly,
                                                      in: script.pageWorld ? .page : world))
            }
        }
    }

    func world(for extID: String) -> WKContentWorld { .world(name: "saints-ext-\(extID)") }

    /// Configuration for an extension's own pages (background, popup, options).
    func pageConfiguration(for ext: WebExtension, context: String) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ExtensionSchemeHandler.shared, forURLScheme: ExtensionSchemeHandler.scheme)
        config.websiteDataStore = .default()
        let controller = WKUserContentController()
        controller.addScriptMessageHandler(ExtensionMessageHandler(extID: ext.id, context: context),
                                           contentWorld: .page, name: "saintsExt")
        let runtime = ExtensionManager.shared.runtimeConfig(for: ext, context: context, incognito: false)
        controller.addUserScript(WKUserScript(source: ExtensionRuntimeJS.shim(config: runtime),
                                              injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        config.userContentController = controller
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return config
    }

    // MARK: Backgrounds

    func refreshBackgrounds() {
        let wanted = Dictionary(uniqueKeysWithValues: ExtensionManager.shared.activeExtensions
            .filter(\.hasBackground).map { ($0.id, $0) })
        for (id, webView) in backgrounds where wanted[id] == nil {
            webView.stopLoading()
            backgrounds.removeValue(forKey: id)
        }
        for (id, ext) in wanted where backgrounds[id] == nil {
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480),
                                    configuration: pageConfiguration(for: ext, context: "background"))
            webView.navigationDelegate = self
            webView.isInspectable = BrowserSettings.shared.data.webInspector
            backgrounds[id] = webView
            if let url = URL(string: "\(ext.baseURL)_generated_background.html") {
                webView.load(URLRequest(url: url))
            }
        }
    }

    func reloadBackground(_ id: String) {
        backgrounds[id]?.removeFromSuperview()
        backgrounds.removeValue(forKey: id)
        refreshBackgrounds()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let id = backgrounds.first(where: { $0.value === webView })?.key else { return }
        let reason = ExtensionManager.shared.pendingInstallEvents.remove(id) != nil ? "install" : nil
        if let reason {
            fire("runtime.onInstalled", args: [["reason": reason]], in: webView)
        } else {
            fire("runtime.onStartup", args: [], in: webView)
        }
    }

    func registerPopup(_ webView: WKWebView, extID: String) {
        popups[extID] = WeakWebView(webView)
    }

    private func fire(_ event: String, args: [Any], in webView: WKWebView, world: WKContentWorld = .page) {
        webView.callAsyncJavaScript("return globalThis.__saintsFire && __saintsFire(name, args);",
                                    arguments: ["name": event, "args": args], in: nil, in: world, completionHandler: nil)
    }

    /// Fires an event in every page of an extension (used for action clicks and tab updates).
    func broadcastEvent(_ event: String, args: [Any], extID: String) {
        if let bg = backgrounds[extID] { fire(event, args: args, in: bg) }
    }

    func tabUpdated(_ tab: BrowserTab) {
        let info = tabInfo(tab)
        for id in backgrounds.keys {
            if let bg = backgrounds[id] {
                let change: [String: Any] = ["status": "complete", "url": tab.url?.absoluteString ?? ""]
                fire("tabs.onUpdated", args: [tab.numericID, change, info], in: bg)
            }
        }
    }

    /// Toolbar / menu tap on an extension.
    func activate(_ ext: WebExtension) {
        if let popup = ext.popupPath {
            presentedPage = ExtensionPage(ext: ext, path: popup, context: "popup")
        } else if let tab = TabManager.shared.selectedTab {
            broadcastEvent("action.onClicked", args: [tabInfo(tab)], extID: ext.id)
        }
    }

    func openOptions(_ ext: WebExtension) {
        guard let path = ext.optionsPath else { return }
        presentedPage = ExtensionPage(ext: ext, path: path, context: "options")
    }

    // MARK: Tabs helpers

    func tabInfo(_ tab: BrowserTab) -> [String: Any] {
        let manager = TabManager.shared
        let list = manager.tabs(isPrivate: tab.isPrivate)
        return [
            "id": tab.numericID,
            "index": list.firstIndex(where: { $0 === tab }) ?? 0,
            "windowId": 1,
            "active": manager.selectedTab === tab,
            "highlighted": manager.selectedTab === tab,
            "pinned": false,
            "audible": false,
            "discarded": false,
            "incognito": tab.isPrivate,
            "status": tab.isLoading ? "loading" : "complete",
            "url": tab.url?.absoluteString ?? "",
            "title": tab.title,
            "favIconUrl": ""
        ]
    }

    private func resolveTab(_ value: Any?) -> BrowserTab? {
        if let n = value as? Int { return TabManager.shared.tab(numericID: n) }
        if let n = value as? NSNumber { return TabManager.shared.tab(numericID: n.intValue) }
        return TabManager.shared.selectedTab
    }

    private func senderInfo(extID: String, context: String, message: WKScriptMessage) -> [String: Any] {
        var sender: [String: Any] = ["id": extID, "frameId": message.frameInfo.isMainFrame ? 0 : 1]
        if let url = message.frameInfo.request.url?.absoluteString { sender["url"] = url }
        if context == "content", let webView = message.webView, let tab = TabManager.shared.tab(for: webView) {
            sender["tab"] = tabInfo(tab)
            sender["origin"] = "\(message.frameInfo.securityOrigin.protocol)://\(message.frameInfo.securityOrigin.host)"
        }
        return sender
    }

    // MARK: Dispatch

    typealias Reply = (Any?, String?) -> Void

    func handle(action: String, payload: [String: Any], extID: String, context: String,
                message: WKScriptMessage, reply: @escaping Reply) {
        guard let ext = ExtensionManager.shared.extensionWith(id: extID) else { reply(nil, "Extension not installed"); return }
        let storage = ExtensionStorage.shared
        let area = (payload["area"] as? String) ?? "local"

        switch action {
        case "storage.get":
            reply(storage.get(extID: extID, area: area, keys: payload["keys"]), nil)
        case "storage.set":
            let changes = storage.set(extID: extID, area: area, items: (payload["items"] as? [String: Any]) ?? [:])
            notifyStorage(extID: extID, changes: changes, area: area)
            reply(nil, nil)
        case "storage.remove":
            notifyStorage(extID: extID, changes: storage.remove(extID: extID, area: area, keys: payload["keys"]), area: area)
            reply(nil, nil)
        case "storage.clear":
            notifyStorage(extID: extID, changes: storage.clear(extID: extID, area: area), area: area)
            reply(nil, nil)

        case "runtime.sendMessage":
            let msg = payload["message"] ?? NSNull()
            let sender = senderInfo(extID: extID, context: context, message: message)
            var targets: [WKWebView] = []
            if context != "background", let bg = backgrounds[extID] { targets.append(bg) }
            if context != "popup" && context != "options", let popup = popups[extID]?.webView { targets.append(popup) }
            deliver(msg, sender: sender, to: targets, world: .page, reply: reply)
        case "runtime.openOptionsPage":
            DispatchQueue.main.async { self.openOptions(ext) }
            reply(nil, nil)
        case "action.openPopup":
            DispatchQueue.main.async { self.activate(ext) }
            reply(nil, nil)

        case "tabs.query":
            reply(queryTabs(payload), nil)
        case "tabs.get":
            reply(resolveTab(payload["tabId"]).map(tabInfo), nil)
        case "tabs.getCurrent":
            if context == "content", let webView = message.webView, let tab = TabManager.shared.tab(for: webView) {
                reply(tabInfo(tab), nil)
            } else { reply(nil, nil) }
        case "tabs.create":
            guard let s = payload["url"] as? String else { reply(nil, "url required"); return }
            let url = URL(string: s, relativeTo: URL(string: ext.baseURL))?.absoluteURL
            let active = (payload["active"] as? Bool) ?? true
            let tab = TabManager.shared.newTab(url: url, isPrivate: false, select: active)
            if context == "popup" && active { presentedPage = nil }
            reply(tabInfo(tab), nil)
        case "tabs.update":
            let tab = resolveTab(payload["tabId"])
            if let props = payload["props"] as? [String: Any], let s = props["url"] as? String,
               let url = URL(string: s, relativeTo: URL(string: ext.baseURL))?.absoluteURL {
                tab?.load(url)
            }
            reply(tab.map(tabInfo), nil)
        case "tabs.remove":
            for id in (payload["tabIds"] as? [Any]) ?? [] {
                if let tab = resolveTab(id) { TabManager.shared.close(tab) }
            }
            reply(nil, nil)
        case "tabs.reload":
            resolveTab(payload["tabId"])?.webView.reload()
            reply(nil, nil)
        case "tabs.sendMessage":
            guard let tab = resolveTab(payload["tabId"]) else { reply(nil, "No tab with that id"); return }
            let sender = senderInfo(extID: extID, context: context, message: message)
            deliver(payload["message"] ?? NSNull(), sender: sender, to: [tab.webView], world: world(for: extID), reply: reply)
        case "tabs.executeScript":
            guard let tab = resolveTab(payload["tabId"]) else { reply(nil, "No tab"); return }
            var code = payload["code"] as? String ?? ""
            if let file = payload["file"] as? String, let text = ExtensionManager.shared.readText(extID: extID, path: file) { code = text }
            tab.webView.evaluateJavaScript(code, in: nil, in: world(for: extID)) { result in
                switch result {
                case .success(let v): reply([v], nil)
                case .failure(let e): reply(nil, e.localizedDescription)
                }
            }
        case "tabs.insertCSS":
            guard let tab = resolveTab(payload["tabId"]) else { reply(nil, "No tab"); return }
            var css = payload["code"] as? String ?? ""
            if let file = payload["file"] as? String, let text = ExtensionManager.shared.readText(extID: extID, path: file) { css = text }
            tab.webView.callAsyncJavaScript(
                "const s = document.createElement('style'); s.textContent = css; (document.head || document.documentElement).appendChild(s);",
                arguments: ["css": css], in: nil, in: world(for: extID)) { _ in reply(nil, nil) }
        case "tabs.captureVisibleTab":
            guard let tab = TabManager.shared.selectedTab else { reply(nil, "No tab"); return }
            tab.webView.takeSnapshot(with: nil) { image, _ in
                let data = image?.jpegData(compressionQuality: 0.8)
                reply(data.map { "data:image/jpeg;base64," + $0.base64EncodedString() }, nil)
            }
        case "scripting.executeScript":
            executeScripting(payload, extID: extID, reply: reply)

        case "notifications.create":
            let title = payload["title"] as? String ?? ext.name
            let body = payload["message"] as? String ?? ""
            DispatchQueue.main.async { ToastCenter.shared.show(body.isEmpty ? title : "\(title): \(body)", symbol: "puzzlepiece.extension") }
            reply(nil, nil)
        case "clipboard.set":
            UIPasteboard.general.string = payload["text"] as? String
            reply(nil, nil)
        case "gm.xhr":
            performXHR(payload, reply: reply)
        default:
            reply(nil, "Unsupported API: \(action)")
        }
    }

    private func queryTabs(_ q: [String: Any]) -> [[String: Any]] {
        let manager = TabManager.shared
        var list = manager.allTabs
        if let active = q["active"] as? Bool {
            list = list.filter { (manager.selectedTab === $0) == active }
        }
        if let patterns = (q["url"] as? [String]) ?? (q["url"] as? String).map({ [$0] }) {
            let regexes = patterns.compactMap(MatchPattern.regex(fromMatch:)).compactMap { try? NSRegularExpression(pattern: $0) }
            list = list.filter { tab in
                let s = tab.url?.absoluteString ?? ""
                return regexes.contains { $0.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
            }
        }
        return list.map(tabInfo)
    }

    private func executeScripting(_ p: [String: Any], extID: String, reply: @escaping Reply) {
        guard let tab = resolveTab(p["tabId"]) else { reply(nil, "No tab"); return }
        let target: WKContentWorld = (p["world"] as? String)?.uppercased() == "MAIN" ? .page : world(for: extID)
        if let fn = p["func"] as? String {
            tab.webView.callAsyncJavaScript("return await (\(fn)).apply(null, args);",
                                            arguments: ["args": (p["args"] as? [Any]) ?? []], in: nil, in: target) { result in
                switch result {
                case .success(let v): reply([["frameId": 0, "result": v]], nil)
                case .failure(let e): reply(nil, e.localizedDescription)
                }
            }
            return
        }
        let files = (p["files"] as? [String]) ?? []
        let code = files.compactMap { ExtensionManager.shared.readText(extID: extID, path: $0) }.joined(separator: ";\n")
        tab.webView.evaluateJavaScript(code, in: nil, in: target) { result in
            switch result {
            case .success(let v): reply([["frameId": 0, "result": v]], nil)
            case .failure(let e): reply(nil, e.localizedDescription)
            }
        }
    }

    /// Delivers a runtime message to the first target that answers.
    private func deliver(_ msg: Any, sender: [String: Any], to targets: [WKWebView], world: WKContentWorld, reply: @escaping Reply) {
        guard let first = targets.first else { reply(nil, nil); return }
        first.callAsyncJavaScript(
            "return globalThis.__saintsDispatchMessage ? await __saintsDispatchMessage(msg, sender) : null;",
            arguments: ["msg": msg, "sender": sender], in: nil, in: world) { result in
            switch result {
            case .success(let value) where !(value is NSNull):
                reply(value, nil)
            default:
                self.deliver(msg, sender: sender, to: Array(targets.dropFirst()), world: world, reply: reply)
            }
        }
    }

    private func notifyStorage(extID: String, changes: [String: Any], area: String) {
        guard !changes.isEmpty, area != "gm" else { return }
        let args: [String: Any] = ["changes": jsonSafe(changes), "area": area]
        let js = "return globalThis.__saintsStorageChanged && __saintsStorageChanged(changes, area);"
        backgrounds[extID]?.callAsyncJavaScript(js, arguments: args, in: nil, in: .page, completionHandler: nil)
        popups[extID]?.webView?.callAsyncJavaScript(js, arguments: args, in: nil, in: .page, completionHandler: nil)
        for tab in TabManager.shared.allTabs {
            tab.webView.callAsyncJavaScript(js, arguments: args, in: nil, in: world(for: extID), completionHandler: nil)
        }
    }

    private lazy var xhrSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        return URLSession(configuration: c)
    }()

    private func performXHR(_ p: [String: Any], reply: @escaping Reply) {
        guard let s = p["url"] as? String, let url = URL(string: s), url.scheme?.hasPrefix("http") == true else {
            reply(nil, "Invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = (p["method"] as? String)?.uppercased() ?? "GET"
        if let t = p["timeout"] as? Double, t > 0 { request.timeoutInterval = t / 1000 }
        for (k, v) in (p["headers"] as? [String: Any]) ?? [:] { request.setValue("\(v)", forHTTPHeaderField: k) }
        if let body = p["data"] as? String { request.httpBody = Data(body.utf8) }
        xhrSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error { reply(nil, error.localizedDescription); return }
                let http = response as? HTTPURLResponse
                let text = data.flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1) } ?? ""
                let headers = (http?.allHeaderFields ?? [:]).map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
                reply([
                    "status": http?.statusCode ?? 0,
                    "statusText": HTTPURLResponse.localizedString(forStatusCode: http?.statusCode ?? 0),
                    "responseText": text,
                    "responseHeaders": headers,
                    "finalUrl": response?.url?.absoluteString ?? s
                ], nil)
            }
        }.resume()
    }
}
