import Foundation

/// Converts uBlock Origin Lite's prebuilt filter data into WebKit content-blocker rules.
///
/// uBO Lite (https://github.com/uBlockOrigin/uBOL-home) compiles uBlock Origin's filter lists into
/// `declarativeNetRequest` rules plus cosmetic (element hiding) and scriptlet data. Saints downloads
/// that data and turns it into native WebKit rules, so filtering runs inside WebKit with no extension
/// process at all. Foundation-only so it can also be exercised by the macOS CI check.
enum UBlockConverter {
    typealias Rule = [String: Any]

    /// Rules per compiled WKContentRuleList (WebKit's hard limit is 150k).
    static let defaultChunkSize = 50_000

    // MARK: - Network (declarativeNetRequest → WebKit)

    struct NetworkResult {
        /// Ordinary block rules, safe to split across lists.
        var normal: [Rule] = []
        /// Allow + important rules; appended to every list so overrides keep working.
        var tail: [Rule] = []
        var converted = 0
        var skipped = 0

        func chunks(size: Int = UBlockConverter.defaultChunkSize) -> [[Rule]] {
            if normal.isEmpty {
                let hasBlocks = tail.contains { ($0["action"] as? Rule)?["type"] as? String != "ignore-previous-rules" }
                return hasBlocks ? [tail] : []
            }
            return UBlockConverter.chunked(normal, max(1_000, size - tail.count - 1)).map { $0 + tail }
        }
    }

    private static let unsupportedConditions = [
        "requestMethods", "excludedRequestMethods", "excludedRequestDomains", "responseHeaders",
        "excludedResponseHeaders", "tabIds", "excludedTabIds"
    ]

    private static let typeMap: [String: String] = [
        "main_frame": "document", "sub_frame": "document", "stylesheet": "style-sheet", "script": "script",
        "image": "image", "font": "font", "media": "media", "object": "raw", "xmlhttprequest": "raw",
        "ping": "raw", "csp_report": "raw", "websocket": "raw", "webtransport": "raw", "webbundle": "raw",
        "other": "raw"
    ]
    private static let allTypes = ["document", "style-sheet", "script", "image", "font", "media", "raw"]

    /// Converts DNR rules. Each chunk carries a copy of every allow / high-priority rule at its end so
    /// exceptions keep working across chunk boundaries (WebKit only honours `ignore-previous-rules`
    /// within a single list).
    static func network(_ dnr: [Rule]) -> NetworkResult {
        struct Tail { let priority: Int; let isAllow: Bool; let rule: Rule }
        var result = NetworkResult()
        var normal: [Rule] = []
        var tail: [Tail] = []

        for rule in dnr {
            guard let action = rule["action"] as? Rule, let type = action["type"] as? String else { result.skipped += 1; continue }
            let condition = (rule["condition"] as? Rule) ?? [:]
            if unsupportedConditions.contains(where: { condition[$0] != nil }) { result.skipped += 1; continue }
            let priority = (rule["priority"] as? Int) ?? 1

            let triggers: [Rule]
            let webkitAction: Rule
            switch type {
            case "block":
                triggers = self.triggers(condition)
                webkitAction = ["type": "block"]
            case "allow":
                triggers = self.triggers(condition)
                webkitAction = ["type": "ignore-previous-rules"]
            case "allowAllRequests":
                triggers = allowAllTriggers(condition)
                webkitAction = ["type": "ignore-previous-rules"]
            case "upgradeScheme":
                triggers = self.triggers(condition)
                webkitAction = ["type": "make-https"]
            default:
                // redirect / modifyHeaders have no WebKit equivalent. Skipping them never breaks pages.
                result.skipped += 1
                continue
            }
            if triggers.isEmpty { result.skipped += 1; continue }

            let isAllow = type.hasPrefix("allow")
            for trigger in triggers {
                let converted: Rule = ["trigger": trigger, "action": webkitAction]
                if isAllow || priority > 30 {
                    tail.append(Tail(priority: priority, isAllow: isAllow, rule: converted))
                } else {
                    normal.append(converted)
                }
            }
            result.converted += 1
        }

        // DNR: higher priority wins; at equal priority allow beats block. WebKit: later rules win.
        result.tail = tail.sorted { a, b in
            a.priority != b.priority ? a.priority < b.priority : (!a.isAllow && b.isAllow)
        }.map(\.rule)
        result.normal = normal
        return result
    }

    private static func baseTrigger(_ c: Rule) -> Rule? {
        var base: Rule = [:]
        if let types = c["resourceTypes"] as? [String] {
            let mapped = Array(Set(types.compactMap { typeMap[$0] })).sorted()
            if mapped.isEmpty { return nil }
            if mapped.count < allTypes.count { base["resource-type"] = mapped }
        } else if let excluded = c["excludedResourceTypes"] as? [String] {
            // Only exclude a WebKit type when every DNR type mapping to it is excluded.
            let excludedSet = Set(excluded)
            let remaining = allTypes.filter { wk in
                !typeMap.filter { $0.value == wk }.keys.allSatisfy { excludedSet.contains($0) }
            }
            if remaining.isEmpty { return nil }
            if remaining.count < allTypes.count { base["resource-type"] = remaining }
        }
        switch c["domainType"] as? String {
        case "firstParty": base["load-type"] = ["first-party"]
        case "thirdParty": base["load-type"] = ["third-party"]
        default: break
        }
        let initiators = ((c["initiatorDomains"] ?? c["domains"]) as? [String]) ?? []
        let excluded = ((c["excludedInitiatorDomains"] ?? c["excludedDomains"]) as? [String]) ?? []
        if !initiators.isEmpty {
            let list = webkitDomains(initiators)
            if list.isEmpty { return nil }
            base["if-domain"] = list
        } else if !excluded.isEmpty {
            let list = webkitDomains(excluded)
            if !list.isEmpty { base["unless-domain"] = list }
        }
        return base
    }

    private static func triggers(_ c: Rule) -> [Rule] {
        guard let base = baseTrigger(c) else { return [] }
        var filter: String
        if let regex = c["regexFilter"] as? String {
            guard let r = webkitRegex(regex) else { return [] }
            filter = r
        } else if let urlFilter = c["urlFilter"] as? String {
            guard let r = regex(fromURLFilter: urlFilter) else { return [] }
            filter = r
        } else {
            filter = ".*"
        }

        if let requestDomains = c["requestDomains"] as? [String], !requestDomains.isEmpty {
            // A url filter alongside requestDomains narrows the match; keep it as an unanchored suffix.
            let suffix = filter == ".*" ? "" : ".*" + filter.replacingOccurrences(of: "^", with: "", options: .anchored)
            return requestDomains.compactMap { domain -> Rule? in
                guard let d = cleanDomain(domain) else { return nil }
                var t = base
                t["url-filter"] = "^[^:]+://+([^:/]+\\.)?" + escape(d) + "[:/]" + suffix
                return t
            }
        }
        var t = base
        t["url-filter"] = filter
        if c["isUrlFilterCaseSensitive"] as? Bool == true { t["url-filter-is-case-sensitive"] = true }
        return [t]
    }

    /// `allowAllRequests` exempts every request made by matching documents → WebKit `if-domain`.
    private static func allowAllTriggers(_ c: Rule) -> [Rule] {
        var domains: [String] = (c["requestDomains"] as? [String]) ?? []
        if domains.isEmpty, let f = c["urlFilter"] as? String, f.hasPrefix("||") {
            var d = String(f.dropFirst(2))
            while let last = d.last, last == "^" || last == "/" || last == "|" { d.removeLast() }
            if !d.contains("/") && !d.contains("*") { domains = [d] }
        }
        let list = webkitDomains(domains + (((c["initiatorDomains"] ?? c["domains"]) as? [String]) ?? []))
        guard !list.isEmpty else { return [] }
        return [["url-filter": ".*", "if-domain": list]]
    }

    // MARK: - Cosmetic (element hiding)

    struct GenericData {
        var selectors: [String] = []
        /// Selectors excepted on specific hostnames (`example.com#@#.ad`).
        var exceptions: [(selectors: [String], hostname: String)] = []
    }

    struct CosmeticResult {
        var rules: [Rule] = []
        var hidden = 0
    }

    private static let proceduralMarkers = [
        ":has-text(", ":matches-css", ":xpath(", ":-abp-", ":upward(", ":remove(", ":style(", ":watch-attr(",
        ":min-text-length(", ":others(", ":matches-path(", ":matches-attr(", ":matches-media(", ":matches-prop(",
        ":remove-attr(", ":remove-class(", ":shadow(", ":nth-ancestor(", ":spath(", ":if(", ":if-not("
    ]

    static func isUsableSelector(_ s: String) -> Bool {
        guard !s.isEmpty, s.count < 1_000, !s.hasPrefix("{"), !s.contains("{"), !s.contains("}") else { return false }
        return !proceduralMarkers.contains { s.contains($0) }
    }

    /// Parses `rulesets/scripting/generic/<id>.js`.
    static func parseGeneric(_ js: String) -> GenericData {
        var data = GenericData()
        var exceptionLists: [String] = []
        var hostnames: [String] = []
        for line in js.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("const lowlyGeneric = new Map(") {
                if let pairs = jsonValue(in: line, terminator: ");") as? [[Any]] {
                    for pair in pairs where pair.count > 1 {
                        if let s = pair[1] as? String { data.selectors += s.components(separatedBy: ",\n") }
                    }
                }
            } else if line.hasPrefix("const highlyGeneric = ") {
                if let s = jsonValue(in: line, terminator: ";") as? String, !s.isEmpty {
                    data.selectors += s.components(separatedBy: ",\n")
                }
            } else if line.hasPrefix("const exceptions = ") {
                exceptionLists = (jsonValue(in: line, terminator: ";") as? [String]) ?? []
            } else if line.hasPrefix("const hostnames = ") {
                hostnames = (jsonValue(in: line, terminator: ";") as? [String]) ?? []
            }
        }
        for (i, list) in exceptionLists.enumerated() where i < hostnames.count {
            data.exceptions.append((list.components(separatedBy: "\n"), hostnames[i]))
        }
        return data
    }

    /// Extracts the JSON literal that follows the `= ` (and an optional `/* n */` comment) on a line.
    private static func jsonValue(in line: Substring, terminator: String) -> Any? {
        var s = String(line)
        guard let eq = s.range(of: "= ") else { return nil }
        s = String(s[eq.upperBound...])
        if s.hasPrefix("new Map(") { s.removeFirst("new Map(".count) }
        if s.hasPrefix("/*"), let close = s.range(of: "*/") { s = String(s[close.upperBound...]) }
        if s.hasSuffix(terminator) { s.removeLast(terminator.count) }
        return try? JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed])
    }

    /// Builds element-hiding rules from the specific (per-site) and generic data of all enabled rulesets.
    static func cosmetic(specific: [Rule], generic: [GenericData], genericHideHosts: [String]) -> CosmeticResult {
        var result = CosmeticResult()
        var exceptionHosts: [String: Set<String>] = [:]

        // Specific: hostnames → selector list refs.
        for data in specific {
            guard let selectors = data["selectors"] as? [String],
                  let lists = data["selectorLists"] as? [String],
                  let refs = data["selectorListRefs"] as? [Int],
                  let hostnames = data["hostnames"] as? [String] else { continue }
            var hostsByRef: [Int: [String]] = [:]
            for (i, host) in hostnames.enumerated() where i < refs.count {
                if let d = cleanDomain(host) { hostsByRef[refs[i], default: []].append(d) }
            }
            for (ref, hosts) in hostsByRef where ref >= 0 && ref < lists.count {
                var hide: [String] = []
                for token in lists[ref].split(separator: ",") {
                    guard let n = Int(token) else { continue }
                    if n >= 0 {
                        if n < selectors.count, isUsableSelector(selectors[n]) { hide.append(selectors[n]) }
                    } else if ~n < selectors.count {
                        exceptionHosts[selectors[~n], default: []].formUnion(hosts)
                    }
                }
                guard !hide.isEmpty else { continue }
                let domains = hosts.map { "*" + $0 }
                for group in chunked(hide, 60) {
                    result.rules.append([
                        "trigger": ["url-filter": ".*", "if-domain": domains],
                        "action": ["type": "css-display-none", "selector": group.joined(separator: ", ")]
                    ])
                }
                result.hidden += hide.count
            }
        }

        // Generic: applied everywhere except generichide sites and per-selector exceptions.
        for data in generic {
            for (selectors, host) in data.exceptions {
                guard let d = cleanDomain(host) else { continue }
                for s in selectors where !s.isEmpty { exceptionHosts[s, default: []].insert(d) }
            }
        }
        let hideEverywhereExcept = Set(genericHideHosts.compactMap(cleanDomain))
        var seen = Set<String>()
        var groups: [String: (hosts: Set<String>, selectors: [String])] = [:]
        for data in generic {
            for s in data.selectors where isUsableSelector(s) && seen.insert(s).inserted {
                let hosts = hideEverywhereExcept.union(exceptionHosts[s] ?? [])
                let key = hosts.sorted().joined(separator: ",")
                groups[key, default: (hosts, [])].selectors.append(s)
            }
        }
        for (_, group) in groups.sorted(by: { $0.key < $1.key }) {
            var trigger: Rule = ["url-filter": ".*"]
            if !group.hosts.isEmpty { trigger["unless-domain"] = group.hosts.sorted().map { "*" + $0 } }
            for chunk in chunked(group.selectors, 100) {
                result.rules.append([
                    "trigger": trigger,
                    "action": ["type": "css-display-none", "selector": chunk.joined(separator: ", ")]
                ])
            }
            result.hidden += group.selectors.count
        }
        return result
    }

    // MARK: - Scriptlets

    /// Wraps uBO's scriptlet framework + per-ruleset scriptlets in a guard that skips allowlisted sites.
    static func scriptletBundle(_ body: String, allowlist: [String]) -> String {
        let list = (try? JSONSerialization.data(withJSONObject: allowlist)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        (function () {
          const h = location.hostname;
          if (\(list).some((d) => h === d || h.endsWith('.' + d))) return;
        \(body)
        })();
        """
    }

    // MARK: - Allowlist

    /// Appended to every list so uBO is fully off on allowlisted sites.
    static func allowlistRule(_ sites: [String]) -> Rule? {
        let domains = webkitDomains(sites)
        guard !domains.isEmpty else { return nil }
        return ["trigger": ["url-filter": ".*", "if-domain": domains], "action": ["type": "ignore-previous-rules"]]
    }

    // MARK: - Helpers

    static func chunked<T>(_ items: [T], _ size: Int) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    /// Lowercase ASCII hostnames only; uBO "entity" patterns (`example.*`) cannot be expressed in WebKit.
    static func cleanDomain(_ raw: String) -> String? {
        let d = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty, !d.contains("*"), d.unicodeScalars.allSatisfy({ $0.isASCII }),
              d.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) else { return nil }
        return d
    }

    static func webkitDomains(_ list: [String]) -> [String] {
        Array(Set(list.compactMap(cleanDomain))).sorted().map { "*" + $0 }
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ".?+()[]{}\\$^*|".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Adblock-style `urlFilter` (`||`, `|`, `^`, `*`) → WebKit regex.
    static func regex(fromURLFilter filter: String) -> String? {
        guard filter.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        var s = Substring(filter)
        var prefix = ""
        var suffix = ""
        if s.hasPrefix("||") {
            s = s.dropFirst(2)
            prefix = "^[^:]+://+([^:/]+\\.)?"
        } else if s.hasPrefix("|") {
            s = s.dropFirst()
            prefix = "^"
        }
        if s.hasSuffix("|") {
            s = s.dropLast()
            suffix = "$"
        }
        if s.contains("|") { return nil }
        var body = ""
        for ch in s {
            switch ch {
            case "*": body += ".*"
            case "^": body += "[^a-zA-Z0-9_.%-]"
            default:
                if ".?+()[]{}\\$".contains(ch) { body.append("\\") }
                body.append(ch)
            }
        }
        if body.isEmpty && prefix.isEmpty { return ".*" }
        return prefix + body + suffix
    }

    /// Rewrites a DNR `regexFilter` into WebKit's regex subset, or returns nil if it cannot.
    static func webkitRegex(_ re: String) -> String? {
        guard re.unicodeScalars.allSatisfy({ $0.isASCII }), !re.contains("|"), !re.contains("{"),
              !re.contains("(?"), !re.contains("*?"), !re.contains("+?"), !re.contains("??") else { return nil }
        var out = ""
        var inClass = false
        var chars = Array(re)[...]
        while let ch = chars.popFirst() {
            if ch == "\\" {
                guard let next = chars.popFirst() else { return nil }
                switch next {
                case "d": out += inClass ? "0-9" : "[0-9]"
                case "w": out += inClass ? "A-Za-z0-9_" : "[A-Za-z0-9_]"
                default:
                    if next.isLetter || next.isNumber { return nil }   // \s, \b, \1, \u… unsupported
                    if ".?+*()[]\\$^".contains(next) {
                        out.append("\\"); out.append(next)
                    } else {
                        out.append(next)                               // `\/` → `/`
                    }
                }
                continue
            }
            if ch == "[" { inClass = true } else if ch == "]" { inClass = false }
            out.append(ch)
        }
        return out
    }

    static func encode(_ rules: [Rule]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: rules) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
