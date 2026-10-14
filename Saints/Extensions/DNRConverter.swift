import Foundation

/// Translates Manifest V3 `declarativeNetRequest` static rules into WebKit content-blocker rules,
/// so MV3 ad/tracker blockers work natively on iOS.
enum DNRConverter {
    static let maxRules = 100_000

    private static let typeMap: [String: String] = [
        "main_frame": "document", "sub_frame": "document", "stylesheet": "style-sheet", "script": "script",
        "image": "image", "font": "font", "object": "media", "xmlhttprequest": "fetch", "ping": "ping",
        "csp_report": "ping", "media": "media", "websocket": "websocket", "webtransport": "other",
        "webbundle": "other", "other": "other"
    ]
    private static let allTypes = ["document", "style-sheet", "script", "image", "font", "media", "fetch", "ping", "websocket", "other"]

    static func convert(_ rules: [[String: Any]]) -> [[String: Any]] {
        struct Item { let priority: Int; let isAllow: Bool; let index: Int; let rule: [String: Any] }
        var items: [Item] = []
        for (index, rule) in rules.enumerated() {
            guard let action = rule["action"] as? [String: Any], let type = action["type"] as? String else { continue }
            let condition = (rule["condition"] as? [String: Any]) ?? [:]
            let webkitAction: [String: Any]
            switch type {
            case "block": webkitAction = ["type": "block"]
            case "allow", "allowAllRequests": webkitAction = ["type": "ignore-previous-rules"]
            case "upgradeScheme": webkitAction = ["type": "make-https"]
            default: continue
            }
            for trigger in triggers(for: condition) {
                items.append(Item(priority: (rule["priority"] as? Int) ?? 1, isAllow: type.hasPrefix("allow"),
                                  index: index, rule: ["trigger": trigger, "action": webkitAction]))
            }
            if items.count >= maxRules { break }
        }
        // WebKit applies rules in order; allow rules must come after the blocks they override.
        items.sort { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            if a.isAllow != b.isAllow { return !a.isAllow }
            return a.index < b.index
        }
        return items.prefix(maxRules).map(\.rule)
    }

    private static func triggers(for c: [String: Any]) -> [[String: Any]] {
        var base: [String: Any] = [:]

        if let types = c["resourceTypes"] as? [String] {
            let mapped = Array(Set(types.compactMap { typeMap[$0] })).sorted()
            if mapped.isEmpty { return [] }
            base["resource-type"] = mapped
        } else if let excluded = c["excludedResourceTypes"] as? [String] {
            let ex = Set(excluded.compactMap { typeMap[$0] })
            let remaining = allTypes.filter { !ex.contains($0) }
            if remaining.isEmpty { return [] }
            base["resource-type"] = remaining
        }

        switch c["domainType"] as? String {
        case "firstParty": base["load-type"] = ["first-party"]
        case "thirdParty": base["load-type"] = ["third-party"]
        default: break
        }

        let initiators = ((c["initiatorDomains"] ?? c["domains"]) as? [String]) ?? []
        let excludedInitiators = ((c["excludedInitiatorDomains"] ?? c["excludedDomains"]) as? [String]) ?? []
        if !initiators.isEmpty {
            let list = initiators.compactMap(domain(_:))
            if list.isEmpty { return [] }
            base["if-domain"] = list
        } else if !excludedInitiators.isEmpty {
            let list = excludedInitiators.compactMap(domain(_:))
            if !list.isEmpty { base["unless-domain"] = list }
        }

        if let requestDomains = c["requestDomains"] as? [String], !requestDomains.isEmpty {
            return requestDomains.compactMap { d -> [String: Any]? in
                guard isASCII(d) else { return nil }
                var t = base
                t["url-filter"] = "^[^:]+://+([^:/]+\\.)?" + escape(d.lowercased()) + "[:/]"
                return t
            }
        }

        var t = base
        if let regex = c["regexFilter"] as? String {
            guard isASCII(regex), !regex.contains("|"), !regex.contains("{"), !regex.contains("\\d"),
                  !regex.contains("\\w"), !regex.contains("\\s"), !regex.contains("(?") else { return [] }
            t["url-filter"] = regex
        } else if let filter = c["urlFilter"] as? String {
            guard let regex = regex(fromURLFilter: filter) else { return [] }
            t["url-filter"] = regex
        } else {
            t["url-filter"] = ".*"
        }
        if let caseSensitive = c["isUrlFilterCaseSensitive"] as? Bool, caseSensitive {
            t["url-filter-is-case-sensitive"] = true
        }
        return [t]
    }

    private static func domain(_ d: String) -> String? {
        guard isASCII(d), !d.isEmpty else { return nil }
        return "*" + d.lowercased()
    }

    private static func isASCII(_ s: String) -> Bool { s.unicodeScalars.allSatisfy { $0.isASCII } }

    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ".?+()[]{}\\$^*".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Converts Adblock-style `urlFilter` syntax (`||`, `|`, `^`, `*`) to a WebKit-compatible regex.
    static func regex(fromURLFilter filter: String) -> String? {
        guard isASCII(filter) else { return nil }
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
}
