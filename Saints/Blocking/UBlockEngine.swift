import Foundation
import WebKit

/// One filter list from uBO Lite's catalog (`ruleset-details.json`).
struct UBORuleset: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let group: String
    let enabledByDefault: Bool
    let lang: String?
    let filterCount: Int
    let hasNetwork: Bool
    let hasRegex: Bool
    let hasSpecific: Bool
    let hasGeneric: Bool
}

/// Built-in uBlock Origin. Downloads uBO Lite's precompiled filter data from GitHub, converts it to
/// WebKit content-blocker lists (network + element hiding) and injects uBO's scriptlets.
/// The only network traffic is fetching the lists themselves from raw.githubusercontent.com.
final class UBlockEngine: ObservableObject {
    static let shared = UBlockEngine()
    static let source = URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uBOL-home/main/chromium/rulesets/")!
    static let defaultRulesets = ["ublock-filters", "easylist", "easyprivacy", "pgl", "ublock-badware", "urlhaus-full"]
    static let world = WKContentWorld.world(name: "saints-ubo")
    static let updateInterval: TimeInterval = 7 * 24 * 3600

    enum Status: Equatable {
        case off, idle, ready
        case working(String)
        case failed(String)

        var text: String {
            switch self {
            case .off: return "Off"
            case .idle: return "Not downloaded yet"
            case .ready: return "Active"
            case .working(let s): return s
            case .failed(let s): return "Failed: \(s)"
            }
        }
    }

    struct State: Codable, Equatable {
        var enabled = true
        var scriptlets = true
        var autoUpdate = true
        var selected: [String]?
        var allowlist: [String] = []
        var lastUpdated: Date?
        var activeRulesets: [String] = []
        var networkRules = 0
        var cosmeticRules = 0
        var netChunks = 0
        var cssChunks = 0
        var compiledIDs: [String] = []
    }

    @Published private(set) var state: State { didSet { if state != oldValue { saveState() } } }
    @Published private(set) var status: Status = .idle
    @Published private(set) var catalog: [UBORuleset] = []

    let baseDir: URL
    private var rawDir: URL { baseDir.appendingPathComponent("raw", isDirectory: true) }
    private var buildDir: URL { baseDir.appendingPathComponent("build", isDirectory: true) }
    private var stateURL: URL { baseDir.appendingPathComponent("state.json") }
    private let work = DispatchQueue(label: "saints.ubo", qos: .utility)
    private var busy = false
    private var started = false
    private var mainBundle: String?
    private var isolatedBundle: String?
    private var guardedCache: (allowlist: [String], main: String?, isolated: String?)?
    private var afterInstall: (() -> Void)?
    private var recompileQueued = false

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.timeoutIntervalForRequest = 60
        return URLSession(configuration: c)
    }()

    private init() {
        baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saints/uBlockOrigin", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let url = baseDir.appendingPathComponent("state.json")
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
        }
        loadCatalog()
    }

    private func saveState() {
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }

    // MARK: Public API

    var selection: Set<String> {
        if let s = state.selected { return Set(s) }
        let defaults = catalog.filter(\.enabledByDefault).map(\.id)
        return Set(defaults.isEmpty ? Self.defaultRulesets : defaults)
    }

    var selectionChanged: Bool { selection != Set(state.activeRulesets) && state.lastUpdated != nil }

    /// Restores compiled lists on launch, downloading them the first time.
    func start(completion: (() -> Void)? = nil) {
        guard state.enabled else { status = .off; completion?(); return }
        started = true
        loadScriptlets()
        let ids = state.compiledIDs
        guard !ids.isEmpty else {
            completion?()
            update()
            return
        }
        lookUp(ids) { [weak self] lists in
            guard let self else { return }
            if lists.count == ids.count {
                self.install(lists)
                self.status = .ready
                completion?()
                if self.state.autoUpdate, let last = self.state.lastUpdated,
                   Date().timeIntervalSince(last) > Self.updateInterval {
                    self.update()
                }
            } else {
                completion?()
                if self.state.netChunks > 0 || self.state.cssChunks > 0 {
                    self.compileAll()
                } else {
                    self.update()
                }
            }
        }
    }

    func setEnabled(_ on: Bool) {
        state.enabled = on
        if on {
            start()
        } else {
            ContentBlocker.shared.replaceLists(prefix: "ubo.", with: [:])
            status = .off
            TabManager.shared.refreshUserContent()
        }
    }

    func setScriptlets(_ on: Bool) {
        state.scriptlets = on
        TabManager.shared.refreshUserContent()
    }

    func setAutoUpdate(_ on: Bool) { state.autoUpdate = on }

    func setSelected(_ id: String, _ on: Bool) {
        var s = selection
        if on { s.insert(id) } else { s.remove(id) }
        state.selected = Array(s).sorted()
    }

    func resetSelection() { state.selected = nil }

    func isAllowlisted(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return state.allowlist.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The uBO "power button": turn filtering off or on for a site. `then` runs once the new lists are live.
    func toggleAllowlist(_ host: String, then: (() -> Void)? = nil) {
        var h = host.lowercased()
        if h.hasPrefix("www.") { h.removeFirst(4) }
        if isAllowlisted(h) {
            state.allowlist.removeAll { h == $0 || h.hasSuffix("." + $0) || $0.hasSuffix("." + h) }
        } else {
            state.allowlist.append(h)
        }
        guardedCache = nil
        afterInstall = then
        if state.enabled { compileAll() } else { then?() }
    }

    func removeFromAllowlist(_ host: String) {
        state.allowlist.removeAll { $0 == host }
        guardedCache = nil
        if state.enabled { compileAll() }
    }

    // MARK: Scriptlets

    func install(into controller: WKUserContentController) {
        guard state.enabled, state.scriptlets, status == .ready || started else { return }
        let bundles = guardedBundles()
        if let main = bundles.main {
            controller.addUserScript(WKUserScript(source: main, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: .page))
        }
        if let isolated = bundles.isolated {
            controller.addUserScript(WKUserScript(source: isolated, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: Self.world))
        }
    }

    private func guardedBundles() -> (main: String?, isolated: String?) {
        if let cache = guardedCache, cache.allowlist == state.allowlist { return (cache.main, cache.isolated) }
        let main = mainBundle.map { UBlockConverter.scriptletBundle($0, allowlist: state.allowlist) }
        let isolated = isolatedBundle.map { UBlockConverter.scriptletBundle($0, allowlist: state.allowlist) }
        guardedCache = (state.allowlist, main, isolated)
        return (main, isolated)
    }

    private func loadScriptlets() {
        mainBundle = try? String(contentsOf: buildDir.appendingPathComponent("scriptlets-main.js"), encoding: .utf8)
        isolatedBundle = try? String(contentsOf: buildDir.appendingPathComponent("scriptlets-isolated.js"), encoding: .utf8)
        guardedCache = nil
    }

    // MARK: Catalog

    private func loadCatalog() {
        guard let data = try? Data(contentsOf: rawDir.appendingPathComponent("ruleset-details.json")) else { return }
        catalog = Self.parseCatalog(data)
    }

    static func parseCatalog(_ data: Data) -> [UBORuleset] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String, let group = d["group"] as? String else { return nil }
            let rules = d["rules"] as? [String: Any] ?? [:]
            let css = d["css"] as? [String: Any] ?? [:]
            let filters = d["filters"] as? [String: Any] ?? [:]
            return UBORuleset(id: id, name: name, group: group, enabledByDefault: d["enabled"] as? Bool ?? false,
                              lang: d["lang"] as? String, filterCount: filters["accepted"] as? Int ?? 0,
                              hasNetwork: (rules["plain"] as? Int ?? 0) > 0, hasRegex: (rules["regex"] as? Int ?? 0) > 0,
                              hasSpecific: (css["specific"] as? Int ?? 0) > 0, hasGeneric: (css["generic"] as? Int ?? 0) > 0)
        }
    }

    // MARK: Update pipeline

    func update() {
        guard !busy else { return }
        busy = true
        status = .working("Downloading filter lists…")
        let wanted = selection
        Task {
            do {
                let staged = try await self.download(selection: wanted)
                DispatchQueue.main.async { self.status = .working("Converting filters…") }
                self.work.async {
                    do {
                        let summary = try self.build(from: staged)
                        DispatchQueue.main.async {
                            self.catalog = summary.catalog
                            self.state.activeRulesets = summary.rulesets
                            self.state.networkRules = summary.networkRules
                            self.state.cosmeticRules = summary.cosmeticRules
                            self.state.netChunks = summary.netChunks
                            self.state.cssChunks = summary.cssChunks
                            self.state.lastUpdated = Date()
                            self.loadScriptlets()
                            self.busy = false
                            self.compileAll()
                        }
                    } catch {
                        self.fail(error)
                    }
                }
            } catch {
                self.fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        DispatchQueue.main.async {
            self.busy = false
            self.status = .failed(error.localizedDescription)
        }
    }

    private func fetch(_ path: String) async throws -> Data {
        let (data, response) = try await session.data(from: Self.source.appendingPathComponent(path))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Could not download \(path)"])
        }
        return data
    }

    /// Downloads everything into a fresh staging directory and swaps it in on success.
    private func download(selection: Set<String>) async throws -> URL {
        let staging = baseDir.appendingPathComponent("raw-staging", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let detailsData = try await fetch("ruleset-details.json")
        let scriptletData = try await fetch("scriptlet-details.json")
        let genericData = try await fetch("generic-details.json")
        let catalog = Self.parseCatalog(detailsData)
        guard !catalog.isEmpty else { throw URLError(.cannotParseResponse) }

        var paths: [String] = []
        let scriptlets = Self.pairs(scriptletData)
        var worlds = Set<String>()
        for r in catalog where selection.contains(r.id) {
            if r.hasNetwork { paths.append("main/\(r.id).json") }
            if r.hasRegex { paths.append("regex/\(r.id).json") }
            if r.hasSpecific { paths.append("scripting/specific/\(r.id).json") }
            if r.hasGeneric { paths.append("scripting/generic/\(r.id).js") }
            for world in ["MAIN", "ISOLATED"] where scriptlets[r.id]?[world] != nil {
                paths.append("scripting/scriptlet/\(world.lowercased())/\(r.id).js")
                worlds.insert(world.lowercased())
            }
        }
        for w in worlds {
            paths.append("scripting/scriptlet/\(w)/scriptlet-begin.js")
            paths.append("scripting/scriptlet/\(w)/scriptlet-end.js")
        }

        let total = paths.count
        var done = 0
        try await withThrowingTaskGroup(of: (String, Data).self) { group in
            for path in paths {
                group.addTask {
                    let data = try await self.fetch(path)
                    return (path, data)
                }
            }
            for try await (path, data) in group {
                let target = staging.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target)
                done += 1
                let progress = "Downloading filter lists… \(done)/\(total)"
                DispatchQueue.main.async { self.status = .working(progress) }
            }
        }
        try detailsData.write(to: staging.appendingPathComponent("ruleset-details.json"))
        try scriptletData.write(to: staging.appendingPathComponent("scriptlet-details.json"))
        try genericData.write(to: staging.appendingPathComponent("generic-details.json"))

        try? FileManager.default.removeItem(at: rawDir)
        try FileManager.default.moveItem(at: staging, to: rawDir)
        return rawDir
    }

    /// `[[id, {...}], ...]` → `[id: {...}]`
    static func pairs(_ data: Data) -> [String: [String: Any]] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [:] }
        var out: [String: [String: Any]] = [:]
        for pair in list where pair.count == 2 {
            if let id = pair[0] as? String, let value = pair[1] as? [String: Any] { out[id] = value }
        }
        return out
    }

    private struct BuildSummary {
        var catalog: [UBORuleset]
        var rulesets: [String]
        var networkRules: Int
        var cosmeticRules: Int
        var netChunks: Int
        var cssChunks: Int
    }

    private func build(from raw: URL) throws -> BuildSummary {
        func json(_ path: String) -> Any? {
            guard let data = try? Data(contentsOf: raw.appendingPathComponent(path)) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        func text(_ path: String) -> String? { try? String(contentsOf: raw.appendingPathComponent(path), encoding: .utf8) }

        let catalog = (try? Data(contentsOf: raw.appendingPathComponent("ruleset-details.json"))).map(Self.parseCatalog) ?? []
        let scriptletDetails = (try? Data(contentsOf: raw.appendingPathComponent("scriptlet-details.json"))).map(Self.pairs) ?? [:]
        let genericDetails = (try? Data(contentsOf: raw.appendingPathComponent("generic-details.json"))).map(Self.pairs) ?? [:]
        let active = catalog.filter { FileManager.default.fileExists(atPath: raw.appendingPathComponent("main/\($0.id).json").path)
            || FileManager.default.fileExists(atPath: raw.appendingPathComponent("scripting/specific/\($0.id).json").path) }

        var dnr: [[String: Any]] = []
        var specific: [[String: Any]] = []
        var generic: [UBlockConverter.GenericData] = []
        var genericHide: [String] = []
        var mainBodies: [String] = []
        var isolatedBodies: [String] = []
        for r in active {
            dnr += (json("main/\(r.id).json") as? [[String: Any]]) ?? []
            dnr += (json("regex/\(r.id).json") as? [[String: Any]]) ?? []
            if let s = json("scripting/specific/\(r.id).json") as? [String: Any] { specific.append(s) }
            if let g = text("scripting/generic/\(r.id).js") { generic.append(UBlockConverter.parseGeneric(g)) }
            genericHide += (genericDetails[r.id]?["unhide"] as? [String]) ?? []
            if scriptletDetails[r.id]?["MAIN"] != nil, let s = text("scripting/scriptlet/main/\(r.id).js") { mainBodies.append(s) }
            if scriptletDetails[r.id]?["ISOLATED"] != nil, let s = text("scripting/scriptlet/isolated/\(r.id).js") { isolatedBodies.append(s) }
        }

        let net = UBlockConverter.network(dnr)
        let cosmetic = UBlockConverter.cosmetic(specific: specific, generic: generic, genericHideHosts: genericHide)

        let fm = FileManager.default
        let staging = baseDir.appendingPathComponent("build-staging", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let netParts = UBlockConverter.chunked(net.normal, max(1_000, UBlockConverter.defaultChunkSize - net.tail.count - 1))
        for (i, part) in netParts.enumerated() {
            try Data((UBlockConverter.encode(part) ?? "[]").utf8).write(to: staging.appendingPathComponent("net.\(i).json"))
        }
        try Data((UBlockConverter.encode(net.tail) ?? "[]").utf8).write(to: staging.appendingPathComponent("net.tail.json"))
        let cssParts = UBlockConverter.chunked(cosmetic.rules, UBlockConverter.defaultChunkSize - 1)
        for (i, part) in cssParts.enumerated() {
            try Data((UBlockConverter.encode(part) ?? "[]").utf8).write(to: staging.appendingPathComponent("css.\(i).json"))
        }

        func bundle(_ world: String, _ bodies: [String]) throws {
            guard !bodies.isEmpty,
                  let begin = text("scripting/scriptlet/\(world)/scriptlet-begin.js"),
                  let end = text("scripting/scriptlet/\(world)/scriptlet-end.js") else { return }
            let js = ([begin] + bodies + [end]).joined(separator: "\n;\n")
            try Data(js.utf8).write(to: staging.appendingPathComponent("scriptlets-\(world).js"))
        }
        try bundle("main", mainBodies)
        try bundle("isolated", isolatedBodies)

        try? fm.removeItem(at: buildDir)
        try fm.moveItem(at: staging, to: buildDir)

        return BuildSummary(catalog: catalog, rulesets: active.map(\.id),
                            networkRules: net.normal.count + net.tail.count, cosmeticRules: cosmetic.hidden,
                            netChunks: netParts.count, cssChunks: cssParts.count)
    }

    // MARK: Compilation

    private var store: WKContentRuleListStore? { WKContentRuleListStore.default() }

    /// (Re)compiles every chunk with the current allowlist, then swaps the lists in.
    func compileAll() {
        guard !busy else { recompileQueued = true; return }
        busy = true
        status = .working("Compiling filters…")
        struct Job { let id: String; let file: String; let useTail: Bool }
        let jobs: [Job] =
            (0..<state.netChunks).map { Job(id: "ubo.net.\($0)", file: "net.\($0).json", useTail: true) }
            + (0..<state.cssChunks).map { Job(id: "ubo.css.\($0)", file: "css.\($0).json", useTail: false) }
        let allowRule = UBlockConverter.allowlistRule(state.allowlist)
        let dir = buildDir

        work.async {
            let tail = (try? Data(contentsOf: dir.appendingPathComponent("net.tail.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
            var compiled: [String: WKContentRuleList] = [:]
            var dropped = 0
            let semaphore = DispatchSemaphore(value: 0)
            for (index, job) in jobs.enumerated() {
                let rules = (try? Data(contentsOf: dir.appendingPathComponent(job.file)))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
                let suffix = (job.useTail ? tail : []) + (allowRule.map { [$0] } ?? [])
                DispatchQueue.main.async { self.status = .working("Compiling filters… \(index + 1)/\(jobs.count)") }
                self.compileRecovering(id: job.id, rules: rules, suffix: suffix) { lists, lost in
                    compiled.merge(lists) { a, _ in a }
                    dropped += lost
                    semaphore.signal()
                }
                semaphore.wait()
            }
            DispatchQueue.main.async {
                let stale = Set(self.state.compiledIDs).subtracting(compiled.keys)
                for id in stale { self.store?.removeContentRuleList(forIdentifier: id) { _ in } }
                self.state.compiledIDs = compiled.keys.sorted()
                self.busy = false
                if compiled.isEmpty && !jobs.isEmpty {
                    self.status = .failed("WebKit rejected the filter lists")
                } else {
                    if dropped > 0 { self.state.networkRules = max(0, self.state.networkRules - dropped) }
                    self.install(compiled)
                    self.status = .ready
                }
                if self.recompileQueued {
                    // The allowlist changed while compiling; build again with the latest one.
                    self.recompileQueued = false
                    self.compileAll()
                } else {
                    self.afterInstall?()
                    self.afterInstall = nil
                }
            }
        }
    }

    /// Compiles a chunk; if WebKit rejects it, bisects to isolate and drop the offending rules.
    private func compileRecovering(id: String, rules: [[String: Any]], suffix: [[String: Any]],
                                   completion: @escaping ([String: WKContentRuleList], Int) -> Void) {
        guard let json = UBlockConverter.encode(rules + suffix) else { completion([:], rules.count); return }
        DispatchQueue.main.async {
            guard let store = self.store else { completion([:], rules.count); return }
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { list, _ in
                if let list {
                    completion([id: list], 0)
                    return
                }
                guard rules.count > 32 else { completion([:], rules.count); return }
                let mid = rules.count / 2
                // Not `work`: that queue is blocked waiting for this chunk.
                DispatchQueue.global(qos: .utility).async {
                    self.compileRecovering(id: id + "a", rules: Array(rules[..<mid]), suffix: suffix) { left, lostLeft in
                        self.compileRecovering(id: id + "b", rules: Array(rules[mid...]), suffix: suffix) { right, lostRight in
                            completion(left.merging(right) { a, _ in a }, lostLeft + lostRight)
                        }
                    }
                }
            }
        }
    }

    private func lookUp(_ ids: [String], completion: @escaping ([String: WKContentRuleList]) -> Void) {
        var found: [String: WKContentRuleList] = [:]
        let group = DispatchGroup()
        for id in ids {
            group.enter()
            store?.lookUpContentRuleList(forIdentifier: id) { list, _ in
                if let list { found[id] = list }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(found) }
    }

    private func install(_ lists: [String: WKContentRuleList]) {
        guard state.enabled else { return }
        ContentBlocker.shared.replaceLists(prefix: "ubo.", with: lists)
        TabManager.shared.refreshUserContent()
    }
}
