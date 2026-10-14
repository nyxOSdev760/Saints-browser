import Foundation

/// An installed extension. Saints supports three flavours that all share one runtime:
/// WebExtensions (Firefox .xpi / Chrome .crx / unpacked .zip), userscripts (.user.js) and userstyles (CSS).
struct WebExtension: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case webExtension, userScript, userStyle
        var label: String {
            switch self {
            case .webExtension: return "WebExtension"
            case .userScript: return "Userscript"
            case .userStyle: return "Userstyle"
            }
        }
    }

    struct ContentScript: Codable, Equatable {
        var matches: [String]
        var excludeMatches: [String] = []
        var includeGlobs: [String] = []
        var excludeGlobs: [String] = []
        var js: [String] = []
        var css: [String] = []
        var runAt: String = "document_idle"
        var allFrames: Bool = false
        /// "ISOLATED" (own content world) or "MAIN" (page world).
        var world: String = "ISOLATED"
    }

    /// Internal id; lowercase hex so it is a valid URL host for `saints-ext://<id>/`.
    var id: String
    var kind: Kind
    var name: String
    var version: String
    var summary: String
    var author: String = ""
    var homepage: String = ""
    var enabled: Bool = true
    var allowPrivate: Bool = false
    var installDate: Date = Date()
    var sourceURL: String?
    var manifestVersion: Int = 2
    var permissions: [String] = []
    var hostPermissions: [String] = []
    var contentScripts: [ContentScript] = []
    var backgroundScripts: [String] = []
    var backgroundPage: String?
    var backgroundIsModule: Bool = false
    var popupPath: String?
    var optionsPath: String?
    var iconPath: String?
    var actionTitle: String?
    var dnrRulesets: [String] = []
    /// Userscript @grant values (empty / "none" means page-world execution).
    var grants: [String] = []
    var defaultLocale: String?

    var hasBackground: Bool { !backgroundScripts.isEmpty || backgroundPage != nil }
    var displayPermissions: [String] { Array(Set(permissions + hostPermissions)).sorted() }
    var baseURL: String { "\(ExtensionSchemeHandler.scheme)://\(id)/" }
}

/// Converts WebExtension match patterns and userscript globs into JavaScript regular expressions.
enum MatchPattern {
    static func regex(fromMatch pattern: String) -> String? {
        if pattern == "<all_urls>" {
            return "^(https?|wss?|file|ftp)://.*"
        }
        guard let schemeEnd = pattern.range(of: "://") else { return nil }
        let scheme = String(pattern[..<schemeEnd.lowerBound])
        let rest = String(pattern[schemeEnd.upperBound...])
        let schemeRegex: String
        switch scheme {
        case "*": schemeRegex = "https?"
        case "http", "https", "file", "ftp", "ws", "wss": schemeRegex = scheme
        default: return nil
        }
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        let host = String(rest[..<slash])
        let path = slash < rest.endIndex ? String(rest[slash...]) : "/*"

        var hostRegex: String
        if host == "*" {
            hostRegex = "[^/]*"
        } else if host.hasPrefix("*.") {
            hostRegex = "([^/]*\\.)?" + escape(String(host.dropFirst(2)))
        } else {
            hostRegex = escape(host)
        }
        if scheme == "file" { hostRegex = "[^/]*" }
        let pathRegex = path.split(separator: "*", omittingEmptySubsequences: false)
            .map { escape(String($0)) }
            .joined(separator: ".*")
        return "^\(schemeRegex)://\(hostRegex)(:\\d+)?\(pathRegex)$"
    }

    /// Userscript @include / glob → regex. `/regex/` forms are passed through.
    static func regex(fromGlob glob: String) -> String {
        if glob.count > 2, glob.hasPrefix("/"), glob.hasSuffix("/") {
            return String(glob.dropFirst().dropLast())
        }
        if glob == "*" { return ".*" }
        var g = glob
        if g.hasPrefix("*://") { g = "http*://" + g.dropFirst(4) }
        let body = g.split(separator: "*", omittingEmptySubsequences: false)
            .map { escape(String($0)).replacingOccurrences(of: "\\.tld", with: "\\.[a-z.]{2,8}") }
            .joined(separator: ".*")
        return "^\(body)$"
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\^$.|?+()[]{}/".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}

/// Parses `// ==UserScript==` metadata blocks.
enum UserScriptParser {
    struct Metadata {
        var name = "Untitled Userscript"
        var version = "1.0"
        var description = ""
        var author = ""
        var homepage = ""
        var matches: [String] = []
        var includes: [String] = []
        var excludes: [String] = []
        var grants: [String] = []
        var requires: [String] = []
        var runAt = "document_idle"
        var noFrames = false
        var injectInto = ""
    }

    static func parse(_ source: String) -> Metadata {
        var meta = Metadata()
        guard let start = source.range(of: "==UserScript=="),
              let end = source.range(of: "==/UserScript==", range: start.upperBound..<source.endIndex) else {
            return meta
        }
        let block = source[start.upperBound..<end.lowerBound]
        for rawLine in block.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("//") else { continue }
            line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("@") else { continue }
            let parts = line.dropFirst().split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyPart = parts.first else { continue }
            let key = String(keyPart).lowercased()
            let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            switch key {
            case "name": if meta.name == "Untitled Userscript" { meta.name = value }
            case "version": meta.version = value
            case "description": if meta.description.isEmpty { meta.description = value }
            case "author": meta.author = value
            case "homepage", "homepageurl", "website", "namespace":
                if meta.homepage.isEmpty, value.hasPrefix("http") { meta.homepage = value }
            case "match": meta.matches.append(value)
            case "include": meta.includes.append(value)
            case "exclude", "exclude-match": meta.excludes.append(value)
            case "grant": meta.grants.append(value)
            case "require": meta.requires.append(value)
            case "run-at": meta.runAt = value.replacingOccurrences(of: "-", with: "_")
            case "noframes": meta.noFrames = true
            case "inject-into": meta.injectInto = value
            default: break
            }
        }
        return meta
    }
}
