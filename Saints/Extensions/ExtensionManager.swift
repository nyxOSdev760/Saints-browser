import Foundation
import WebKit
import UIKit

enum ExtensionInstallError: LocalizedError {
    case noManifest
    case badManifest(String)
    case download(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .noManifest: return "No manifest.json was found in the archive."
        case .badManifest(let why): return "The manifest could not be read: \(why)"
        case .download(let why): return "Download failed: \(why)"
        case .unsupported(let why): return why
        }
    }
}

/// An extension that has been unpacked and parsed but not yet confirmed by the user.
struct PendingInstall: Identifiable {
    let id = UUID()
    var ext: WebExtension
    let stagingDir: URL
    var replacing: WebExtension?
}

final class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()

    @Published private(set) var extensions: [WebExtension] = []

    let rootDir: URL
    let dataDir: URL
    private let indexURL: URL
    private var scriptCache: [String: [CachedScript]] = [:]
    private var messagesCache: [String: [String: Any]] = [:]
    private var manifestCache: [String: [String: Any]] = [:]
    var pendingInstallEvents: Set<String> = []

    struct CachedScript {
        let source: String
        let time: WKUserScriptInjectionTime
        let mainFrameOnly: Bool
        let pageWorld: Bool
    }

    private let downloadSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootDir = support.appendingPathComponent("Saints/Extensions", isDirectory: true)
        dataDir = support.appendingPathComponent("Saints/ExtensionData", isDirectory: true)
        indexURL = support.appendingPathComponent("Saints/extensions.json")
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([WebExtension].self, from: data) else { return }
        extensions = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(extensions) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    func directory(for ext: WebExtension) -> URL { rootDir.appendingPathComponent(ext.id, isDirectory: true) }
    func extensionWith(id: String) -> WebExtension? { extensions.first { $0.id == id } }

    func fileURL(extID: String, path: String) -> URL? {
        let base = rootDir.appendingPathComponent(extID, isDirectory: true).standardizedFileURL
        let clean = path.removingPercentEncoding ?? path
        let target = base.appendingPathComponent(clean.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        guard target.path.hasPrefix(base.path + "/") else { return nil }
        return target
    }

    func readText(extID: String, path: String) -> String? {
        guard let url = fileURL(extID: extID, path: path), let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    func icon(for ext: WebExtension) -> UIImage? {
        guard let path = ext.iconPath, let url = fileURL(extID: ext.id, path: path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: Enable / remove

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let i = extensions.firstIndex(where: { $0.id == id }) else { return }
        extensions[i].enabled = enabled
        save()
        changed(id)
    }

    func setAllowPrivate(_ allow: Bool, for id: String) {
        guard let i = extensions.firstIndex(where: { $0.id == id }) else { return }
        extensions[i].allowPrivate = allow
        save()
        changed(id)
    }

    func uninstall(_ id: String) {
        guard let ext = extensionWith(id: id) else { return }
        extensions.removeAll { $0.id == id }
        save()
        try? FileManager.default.removeItem(at: directory(for: ext))
        try? FileManager.default.removeItem(at: dataDir.appendingPathComponent("\(id).json"))
        ExtensionStorage.shared.drop(extID: id)
        ContentBlocker.shared.remove(identifier: "dnr.\(id)")
        changed(id)
    }

    private func changed(_ id: String) {
        scriptCache.removeValue(forKey: id)
        messagesCache.removeValue(forKey: id)
        manifestCache.removeValue(forKey: id)
        ExtensionHost.shared.refreshBackgrounds()
        compileRulesets()
        DispatchQueue.main.async { TabManager.shared.refreshUserContent() }
    }

    // MARK: Install sources

    /// Accepts a direct file URL, an addons.mozilla.org listing, or a Chrome Web Store listing.
    func stage(fromURL input: String, completion: @escaping (Result<PendingInstall, Error>) -> Void) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            completion(.failure(ExtensionInstallError.download("Enter a valid http(s) link.")))
            return
        }
        let host = url.host?.lowercased() ?? ""

        if host.hasSuffix("addons.mozilla.org"), let slug = Self.amoSlug(from: url) {
            resolveAMO(slug: slug) { result in
                switch result {
                case .success(let fileURL): self.download(fileURL, sourceURL: url.absoluteString, completion: completion)
                case .failure(let e): completion(.failure(e))
                }
            }
            return
        }
        if host.contains("chromewebstore.google.com") || host.contains("chrome.google.com"),
           let id = Self.chromeID(from: url) {
            let crx = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=130.0&acceptformat=crx2,crx3&x=id%3D\(id)%26uc"
            download(URL(string: crx)!, sourceURL: url.absoluteString, filenameHint: "\(id).crx", completion: completion)
            return
        }
        download(url, sourceURL: url.absoluteString, completion: completion)
    }

    static func amoSlug(from url: URL) -> String? {
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "addon"), i + 1 < parts.count else { return nil }
        return parts[i + 1]
    }

    static func chromeID(from url: URL) -> String? {
        url.pathComponents.first { $0.count == 32 && $0.allSatisfy { ("a"..."p").contains($0) } }
    }

    static func isStoreListing(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return false }
        if host.hasSuffix("addons.mozilla.org") { return amoSlug(from: url) != nil }
        if host.contains("chromewebstore.google.com") || host == "chrome.google.com" { return chromeID(from: url) != nil }
        return false
    }

    private func resolveAMO(slug: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let api = URL(string: "https://addons.mozilla.org/api/v5/addons/addon/\(slug)/")!
        downloadSession.dataTask(with: api) { data, _, error in
            DispatchQueue.main.async {
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let version = json["current_version"] as? [String: Any],
                      let file = version["file"] as? [String: Any],
                      let urlString = file["url"] as? String,
                      let url = URL(string: urlString) else {
                    completion(.failure(ExtensionInstallError.download(error?.localizedDescription ?? "Add-on not found on addons.mozilla.org")))
                    return
                }
                completion(.success(url))
            }
        }.resume()
    }

    private func download(_ url: URL, sourceURL: String, filenameHint: String? = nil,
                          completion: @escaping (Result<PendingInstall, Error>) -> Void) {
        downloadSession.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                guard let data, error == nil else {
                    completion(.failure(ExtensionInstallError.download(error?.localizedDescription ?? "No data")))
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    completion(.failure(ExtensionInstallError.download("HTTP \(http.statusCode)")))
                    return
                }
                let name = filenameHint ?? response?.suggestedFilename ?? url.lastPathComponent
                completion(Result { try self.stage(data: data, filename: name, sourceURL: sourceURL) })
            }
        }.resume()
    }

    /// Detects the package type and stages it for confirmation.
    func stage(data: Data, filename: String, sourceURL: String?) throws -> PendingInstall {
        let lower = filename.lowercased()
        let text = String(data: data.prefix(4096), encoding: .utf8) ?? ""
        if lower.hasSuffix(".user.js") || text.contains("==UserScript==") {
            guard let source = String(data: data, encoding: .utf8) else { throw ExtensionInstallError.unsupported("Script is not UTF-8 text.") }
            return try stageUserScript(source: source, sourceURL: sourceURL)
        }
        if lower.hasSuffix(".user.css") || lower.hasSuffix(".css") || text.contains("==UserStyle==") {
            guard let source = String(data: data, encoding: .utf8) else { throw ExtensionInstallError.unsupported("Style is not UTF-8 text.") }
            return try stageUserStyle(source: source, sourceURL: sourceURL)
        }
        if lower.hasSuffix(".js") {
            guard let source = String(data: data, encoding: .utf8) else { throw ExtensionInstallError.unsupported("Script is not UTF-8 text.") }
            return try stageUserScript(source: source, sourceURL: sourceURL)
        }
        return try stageArchive(data: data, sourceURL: sourceURL)
    }

    private func newStagingDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("saints-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func newID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: Userscripts & userstyles

    func stageUserScript(source: String, sourceURL: String?, existingID: String? = nil) throws -> PendingInstall {
        let meta = UserScriptParser.parse(source)
        let dir = try newStagingDir()
        var jsFiles: [String] = []
        for (i, req) in meta.requires.enumerated() {
            guard let url = URL(string: req), let data = try? Data(contentsOf: url) else { continue }
            let name = "require_\(i).js"
            try data.write(to: dir.appendingPathComponent(name))
            jsFiles.append(name)
        }
        try Data(source.utf8).write(to: dir.appendingPathComponent("script.user.js"))
        jsFiles.append("script.user.js")

        let grants = meta.grants.filter { $0 != "none" }
        let pageWorld = grants.isEmpty || meta.injectInto == "page"
        var matches = meta.matches
        if matches.isEmpty && meta.includes.isEmpty { matches = ["<all_urls>"] }
        let cs = WebExtension.ContentScript(
            matches: matches,
            excludeMatches: [],
            includeGlobs: meta.includes,
            excludeGlobs: meta.excludes,
            js: jsFiles,
            css: [],
            runAt: meta.runAt,
            allFrames: !meta.noFrames,
            world: pageWorld ? "MAIN" : "ISOLATED")

        var ext = WebExtension(id: existingID ?? Self.newID(), kind: .userScript, name: meta.name, version: meta.version,
                               summary: meta.description)
        ext.author = meta.author
        ext.homepage = meta.homepage
        ext.sourceURL = sourceURL
        ext.contentScripts = [cs]
        ext.grants = meta.grants
        ext.permissions = grants
        ext.hostPermissions = matches + meta.includes
        return PendingInstall(ext: ext, stagingDir: dir, replacing: existingID.flatMap(extensionWith(id:)))
    }

    func stageUserStyle(source: String, sourceURL: String?, existingID: String? = nil) throws -> PendingInstall {
        let dir = try newStagingDir()
        var name = "Untitled Style", version = "1.0", summary = "", author = ""
        if let start = source.range(of: "==UserStyle=="), let end = source.range(of: "==/UserStyle==") , start.upperBound < end.lowerBound {
            for line in source[start.upperBound..<end.lowerBound].split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("@") else { continue }
                let parts = t.dropFirst().split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count == 2 else { continue }
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                switch parts[0].lowercased() {
                case "name": name = value
                case "version": version = value
                case "description": summary = value
                case "author": author = value
                default: break
                }
            }
        }

        var scripts: [WebExtension.ContentScript] = []
        let sections = Self.mozDocumentSections(source)
        if sections.isEmpty {
            try Data(source.utf8).write(to: dir.appendingPathComponent("style0.css"))
            scripts.append(.init(matches: ["<all_urls>"], css: ["style0.css"], runAt: "document_start", allFrames: true))
        } else {
            for (i, section) in sections.enumerated() {
                let file = "style\(i).css"
                try Data(section.css.utf8).write(to: dir.appendingPathComponent(file))
                scripts.append(.init(matches: section.matches, includeGlobs: section.globs, css: [file],
                                     runAt: "document_start", allFrames: true))
            }
        }
        var ext = WebExtension(id: existingID ?? Self.newID(), kind: .userStyle, name: name, version: version, summary: summary)
        ext.author = author
        ext.sourceURL = sourceURL
        ext.contentScripts = scripts
        ext.hostPermissions = scripts.flatMap { $0.matches + $0.includeGlobs }
        try Data(source.utf8).write(to: dir.appendingPathComponent("source.user.css"))
        return PendingInstall(ext: ext, stagingDir: dir, replacing: existingID.flatMap(extensionWith(id:)))
    }

    /// Splits `@-moz-document domain(...), url-prefix(...) { ... }` blocks into matchable sections.
    static func mozDocumentSections(_ css: String) -> [(matches: [String], globs: [String], css: String)] {
        var result: [(matches: [String], globs: [String], css: String)] = []
        let chars = Array(css)
        var i = 0
        let marker = Array("@-moz-document")
        while i < chars.count {
            guard i + marker.count <= chars.count, Array(chars[i..<(i + marker.count)]) == marker else { i += 1; continue }
            var j = i + marker.count
            while j < chars.count && chars[j] != "{" { j += 1 }
            guard j < chars.count else { break }
            let condition = String(chars[(i + marker.count)..<j])
            var depth = 0
            var k = j
            repeat {
                if chars[k] == "{" { depth += 1 } else if chars[k] == "}" { depth -= 1 }
                k += 1
            } while k < chars.count && depth > 0
            let body = String(chars[(j + 1)..<max(j + 1, k - 1)])

            var matches: [String] = [], globs: [String] = []
            let pattern = #"(domain|url-prefix|url|regexp)\(\s*["']?([^"')]*)["']?\s*\)"#
            if let re = try? NSRegularExpression(pattern: pattern) {
                let ns = condition as NSString
                for m in re.matches(in: condition, range: NSRange(location: 0, length: ns.length)) {
                    let fn = ns.substring(with: m.range(at: 1))
                    let arg = ns.substring(with: m.range(at: 2))
                    switch fn {
                    case "domain": matches.append("*://*.\(arg)/*")
                    case "url-prefix": globs.append(arg + "*")
                    case "url": globs.append(arg)
                    case "regexp": globs.append("/^(?:\(arg.replacingOccurrences(of: "\\\\", with: "\\")))$/")
                    default: break
                    }
                }
            }
            if !matches.isEmpty || !globs.isEmpty {
                result.append((matches, globs, body))
            }
            i = k
        }
        return result
    }

    // MARK: WebExtension archives

    private func stageArchive(data: Data, sourceURL: String?) throws -> PendingInstall {
        let zip = try ZipArchive(data: data)
        let dir = try newStagingDir()
        try zip.extractAll(to: dir)

        var root = dir
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("manifest.json").path) {
            let children = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            guard let inner = children.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }) else {
                throw ExtensionInstallError.noManifest
            }
            root = inner
        }
        let ext = try parseManifest(at: root, id: Self.newID(), sourceURL: sourceURL)
        let replacing = extensions.first { $0.kind == .webExtension && $0.name == ext.name }
        return PendingInstall(ext: ext, stagingDir: root, replacing: replacing)
    }

    static func loadJSON(_ url: URL) -> Any? {
        guard var data = try? Data(contentsOf: url) else { return nil }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) { return obj }
        // Chrome tolerates // comments in manifests and messages.
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let stripped = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("//") ? "" : String(line)
        }.joined(separator: "\n")
        return try? JSONSerialization.jsonObject(with: Data(stripped.utf8), options: [.fragmentsAllowed])
    }

    static func loadMessages(root: URL, defaultLocale: String?) -> [String: Any] {
        var locales: [String] = []
        let lang = Locale.preferredLanguages.first ?? "en"
        locales.append(lang.replacingOccurrences(of: "-", with: "_"))
        if let base = lang.split(separator: "-").first { locales.append(String(base)) }
        if let d = defaultLocale { locales.append(d) }
        locales.append(contentsOf: ["en", "en_US", "en_GB"])
        var merged: [String: Any] = [:]
        // Lowest priority first so preferred locales overwrite.
        for loc in locales.reversed() {
            let url = root.appendingPathComponent("_locales/\(loc)/messages.json")
            if let dict = loadJSON(url) as? [String: Any] {
                for (k, v) in dict { merged[k.lowercased()] = v }
            }
        }
        return merged
    }

    static func localize(_ value: String, messages: [String: Any]) -> String {
        guard value.hasPrefix("__MSG_"), value.hasSuffix("__") else { return value }
        let key = String(value.dropFirst(6).dropLast(2)).lowercased()
        return ((messages[key] as? [String: Any])?["message"] as? String) ?? value
    }

    func parseManifest(at root: URL, id: String, sourceURL: String?) throws -> WebExtension {
        guard let manifest = Self.loadJSON(root.appendingPathComponent("manifest.json")) as? [String: Any] else {
            throw ExtensionInstallError.badManifest("manifest.json is not valid JSON")
        }
        let defaultLocale = manifest["default_locale"] as? String
        let messages = Self.loadMessages(root: root, defaultLocale: defaultLocale)
        let str: (String) -> String = { Self.localize((manifest[$0] as? String) ?? "", messages: messages) }

        let name = str("name")
        guard !name.isEmpty else { throw ExtensionInstallError.badManifest("missing name") }
        var ext = WebExtension(id: id, kind: .webExtension, name: name,
                               version: (manifest["version"] as? String) ?? "0", summary: str("description"))
        ext.defaultLocale = defaultLocale
        ext.sourceURL = sourceURL
        ext.manifestVersion = (manifest["manifest_version"] as? Int) ?? 2
        ext.homepage = (manifest["homepage_url"] as? String) ?? ""
        if let a = manifest["author"] as? String { ext.author = a } else if let a = manifest["author"] as? [String: Any] { ext.author = (a["email"] as? String) ?? "" }

        let perms = (manifest["permissions"] as? [Any])?.compactMap { $0 as? String } ?? []
        ext.permissions = perms.filter { !$0.contains("://") && $0 != "<all_urls>" }
        ext.hostPermissions = perms.filter { $0.contains("://") || $0 == "<all_urls>" }
            + ((manifest["host_permissions"] as? [String]) ?? [])

        if let scripts = manifest["content_scripts"] as? [[String: Any]] {
            ext.contentScripts = scripts.compactMap { s in
                guard let matches = s["matches"] as? [String] else { return nil }
                return WebExtension.ContentScript(
                    matches: matches,
                    excludeMatches: (s["exclude_matches"] as? [String]) ?? [],
                    includeGlobs: [],
                    excludeGlobs: (s["exclude_globs"] as? [String]) ?? [],
                    js: (s["js"] as? [String]) ?? [],
                    css: (s["css"] as? [String]) ?? [],
                    runAt: (s["run_at"] as? String) ?? "document_idle",
                    allFrames: (s["all_frames"] as? Bool) ?? false,
                    world: (s["world"] as? String) ?? "ISOLATED")
            }
        }

        if let bg = manifest["background"] as? [String: Any] {
            if let scripts = bg["scripts"] as? [String] { ext.backgroundScripts = scripts }
            if let worker = bg["service_worker"] as? String, ext.backgroundScripts.isEmpty { ext.backgroundScripts = [worker] }
            if let page = bg["page"] as? String { ext.backgroundPage = page }
            ext.backgroundIsModule = (bg["type"] as? String) == "module"
        }

        let action = (manifest["action"] ?? manifest["browser_action"] ?? manifest["page_action"]) as? [String: Any]
        if let popup = action?["default_popup"] as? String, !popup.isEmpty { ext.popupPath = popup }
        if let title = action?["default_title"] as? String { ext.actionTitle = Self.localize(title, messages: messages) }
        if let options = manifest["options_ui"] as? [String: Any], let page = options["page"] as? String {
            ext.optionsPath = page
        } else if let page = manifest["options_page"] as? String {
            ext.optionsPath = page
        }

        ext.iconPath = Self.bestIcon(manifest["icons"]) ?? Self.bestIcon(action?["default_icon"])

        if let dnr = manifest["declarative_net_request"] as? [String: Any],
           let resources = dnr["rule_resources"] as? [[String: Any]] {
            ext.dnrRulesets = resources.compactMap { r in
                (r["enabled"] as? Bool ?? true) ? r["path"] as? String : nil
            }
        }
        return ext
    }

    static func bestIcon(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        guard let dict = value as? [String: Any] else { return nil }
        let sized = dict.compactMap { k, v -> (Int, String)? in
            guard let size = Int(k), let path = v as? String, !path.lowercased().hasSuffix(".svg") else { return nil }
            return (size, path)
        }.sorted { $0.0 < $1.0 }
        return (sized.last(where: { $0.0 <= 128 }) ?? sized.last)?.1
    }

    // MARK: Commit

    func commit(_ pending: PendingInstall) throws {
        var ext = pending.ext
        if let old = pending.replacing {
            ext.id = old.id
            ext.enabled = old.enabled
            ext.allowPrivate = old.allowPrivate
            try? FileManager.default.removeItem(at: directory(for: old))
        }
        let target = directory(for: ext)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: pending.stagingDir, to: target)
        if let i = extensions.firstIndex(where: { $0.id == ext.id }) {
            extensions[i] = ext
        } else {
            extensions.append(ext)
            pendingInstallEvents.insert(ext.id)
        }
        save()
        changed(ext.id)
    }

    func discard(_ pending: PendingInstall) {
        try? FileManager.default.removeItem(at: pending.stagingDir)
    }

    /// Installs (or updates) a userscript/userstyle from editor source without a confirmation step.
    func saveSource(_ source: String, kind: WebExtension.Kind, existingID: String?) throws {
        let pending = kind == .userStyle
            ? try stageUserStyle(source: source, sourceURL: nil, existingID: existingID)
            : try stageUserScript(source: source, sourceURL: nil, existingID: existingID)
        try commit(pending)
    }

    func source(of ext: WebExtension) -> String? {
        switch ext.kind {
        case .userScript: return readText(extID: ext.id, path: "script.user.js")
        case .userStyle: return readText(extID: ext.id, path: "source.user.css")
        case .webExtension: return nil
        }
    }

    // MARK: Runtime data

    func manifest(for ext: WebExtension) -> [String: Any] {
        if let m = manifestCache[ext.id] { return m }
        var m: [String: Any] = ["name": ext.name, "version": ext.version, "description": ext.summary,
                                "manifest_version": ext.manifestVersion]
        if ext.kind == .webExtension, let url = fileURL(extID: ext.id, path: "manifest.json"),
           let parsed = Self.loadJSON(url) as? [String: Any] {
            m = parsed
        }
        manifestCache[ext.id] = m
        return m
    }

    func messages(for ext: WebExtension) -> [String: Any] {
        if let m = messagesCache[ext.id] { return m }
        let m = ext.kind == .webExtension ? Self.loadMessages(root: directory(for: ext), defaultLocale: ext.defaultLocale) : [:]
        messagesCache[ext.id] = m
        return m
    }

    func runtimeConfig(for ext: WebExtension, context: String, incognito: Bool) -> [String: Any] {
        [
            "id": ext.id,
            "name": ext.name,
            "version": ext.version,
            "description": ext.summary,
            "kind": ext.kind.rawValue,
            "context": context,
            "baseURL": ext.baseURL,
            "manifest": manifest(for: ext),
            "messages": messages(for: ext),
            "permissions": ext.permissions,
            "hostPermissions": ext.hostPermissions,
            "rulesets": ext.dnrRulesets,
            "popup": ext.popupPath ?? "",
            "actionTitle": ext.actionTitle ?? ext.name,
            "incognito": incognito,
            "allowPrivate": ext.allowPrivate,
            "browserVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        ]
    }

    /// Builds (and caches) the user scripts for one extension's content scripts.
    func contentScripts(for ext: WebExtension) -> [CachedScript] {
        if let cached = scriptCache[ext.id] { return cached }
        var result: [CachedScript] = []
        for cs in ext.contentScripts {
            let include = cs.matches.compactMap(MatchPattern.regex(fromMatch:)) + cs.includeGlobs.map(MatchPattern.regex(fromGlob:))
            let exclude = cs.excludeMatches.compactMap(MatchPattern.regex(fromMatch:)) + cs.excludeGlobs.map(MatchPattern.regex(fromGlob:))
            let css = cs.css.compactMap { readText(extID: ext.id, path: $0) }.joined(separator: "\n")
            let js = cs.js.compactMap { path in readText(extID: ext.id, path: path).map { $0 + "\n//# sourceURL=\(ext.baseURL)\(path)\n" } }
                .joined(separator: ";\n")
            guard !css.isEmpty || !js.isEmpty else { continue }
            let pageWorld = cs.world.uppercased() == "MAIN"
            let source = ExtensionRuntimeJS.contentScript(
                extID: ext.id, include: include, exclude: exclude, css: css, js: js,
                waitForGM: ext.kind == .userScript && !pageWorld)
            let time: WKUserScriptInjectionTime = (cs.runAt == "document_start" || !css.isEmpty && js.isEmpty) ? .atDocumentStart : .atDocumentEnd
            result.append(CachedScript(source: source, time: time, mainFrameOnly: !cs.allFrames, pageWorld: pageWorld))
        }
        scriptCache[ext.id] = result
        return result
    }

    var activeExtensions: [WebExtension] {
        guard BrowserSettings.shared.data.extensionsEnabled else { return [] }
        return extensions.filter(\.enabled)
    }

    // MARK: declarativeNetRequest

    func compileRulesets() {
        for ext in extensions where !ext.dnrRulesets.isEmpty {
            let identifier = "dnr.\(ext.id)"
            guard ext.enabled, BrowserSettings.shared.data.extensionsEnabled else {
                ContentBlocker.shared.remove(identifier: identifier)
                continue
            }
            if ContentBlocker.shared.lists[identifier] != nil { continue }
            let id = ext.id
            let paths = ext.dnrRulesets
            DispatchQueue.global(qos: .utility).async {
                var rules: [[String: Any]] = []
                for path in paths {
                    if let url = self.fileURL(extID: id, path: path),
                       let list = Self.loadJSON(url) as? [[String: Any]] {
                        rules.append(contentsOf: list)
                    }
                }
                let converted = DNRConverter.convert(rules)
                DispatchQueue.main.async {
                    ContentBlocker.shared.compile(identifier: identifier, rules: converted) {
                        TabManager.shared.refreshUserContent()
                    }
                }
            }
        }
    }
}
