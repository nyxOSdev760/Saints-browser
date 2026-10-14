// CI check for the built-in uBlock Origin engine (macOS).
// Downloads uBO Lite's rulesets, converts them with Saints' UBlockConverter, compiles every list with
// WebKit's real content-blocker compiler and syntax-checks the scriptlet bundles with JavaScriptCore.
//
//   swiftc -O Saints/Blocking/UBlockConverter.swift Tools/UBOCheck/main.swift -o ubocheck && ./ubocheck [extra-ruleset-ids…]

import Foundation
import WebKit
import JavaScriptCore

let base = URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uBOL-home/main/chromium/rulesets/")!
var failures = 0

func fetch(_ path: String) -> Data? { try? Data(contentsOf: base.appendingPathComponent(path)) }
func json(_ path: String) -> Any? { fetch(path).flatMap { try? JSONSerialization.jsonObject(with: $0) } }
func text(_ path: String) -> String? { fetch(path).flatMap { String(data: $0, encoding: .utf8) } }
func log(_ s: String) { print(s); fflush(stdout) }

func pairs(_ value: Any?) -> [String: [String: Any]] {
    var out: [String: [String: Any]] = [:]
    for pair in (value as? [[Any]]) ?? [] where pair.count == 2 {
        if let id = pair[0] as? String, let v = pair[1] as? [String: Any] { out[id] = v }
    }
    return out
}

guard let catalog = json("ruleset-details.json") as? [[String: Any]] else {
    log("::error::could not download ruleset-details.json"); exit(1)
}
let defaults = catalog.filter { $0["enabled"] as? Bool == true }.compactMap { $0["id"] as? String }
let ids = defaults + CommandLine.arguments.dropFirst()
log("Rulesets: \(ids.joined(separator: ", "))")

let scriptletDetails = pairs(json("scriptlet-details.json"))
let genericDetails = pairs(json("generic-details.json"))

var dnr: [[String: Any]] = []
var specific: [[String: Any]] = []
var generic: [UBlockConverter.GenericData] = []
var genericHide: [String] = []
var bodies: [String: [String]] = ["main": [], "isolated": []]
for id in ids {
    guard let details = catalog.first(where: { $0["id"] as? String == id }) else { log("unknown ruleset \(id)"); continue }
    let rules = details["rules"] as? [String: Any] ?? [:]
    let css = details["css"] as? [String: Any] ?? [:]
    if (rules["plain"] as? Int ?? 0) > 0 { dnr += (json("main/\(id).json") as? [[String: Any]]) ?? [] }
    if (rules["regex"] as? Int ?? 0) > 0 { dnr += (json("regex/\(id).json") as? [[String: Any]]) ?? [] }
    if (css["specific"] as? Int ?? 0) > 0, let s = json("scripting/specific/\(id).json") as? [String: Any] { specific.append(s) }
    if (css["generic"] as? Int ?? 0) > 0, let g = text("scripting/generic/\(id).js") { generic.append(UBlockConverter.parseGeneric(g)) }
    genericHide += (genericDetails[id]?["unhide"] as? [String]) ?? []
    for world in ["MAIN", "ISOLATED"] where scriptletDetails[id]?[world] != nil {
        if let s = text("scripting/scriptlet/\(world.lowercased())/\(id).js") { bodies[world.lowercased()]?.append(s) }
    }
}

let net = UBlockConverter.network(dnr)
log("Network: \(dnr.count) DNR rules → \(net.normal.count) block + \(net.tail.count) tail WebKit rules (\(net.skipped) skipped)")
let cosmetic = UBlockConverter.cosmetic(specific: specific, generic: generic, genericHideHosts: genericHide)
log("Cosmetic: \(cosmetic.hidden) selectors in \(cosmetic.rules.count) rules")
if net.normal.count < 50_000 { log("::error::suspiciously few network rules"); failures += 1 }
if cosmetic.hidden < 10_000 { log("::error::suspiciously few cosmetic filters"); failures += 1 }

// MARK: Compile with WebKit

let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("ubocheck-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
guard let store = WKContentRuleListStore(url: storeURL) else { log("::error::no rule list store"); exit(1) }

func compile(_ id: String, _ rules: [[String: Any]]) -> Error? {
    guard let encoded = UBlockConverter.encode(rules) else { return NSError(domain: "encode", code: 1) }
    var done = false
    var result: Error?
    store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: encoded) { _, error in
        result = error
        done = true
    }
    while !done { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    return result
}

/// Finds individual rules WebKit rejects.
func bisect(_ id: String, _ rules: [[String: Any]], suffix: [[String: Any]], found: inout [[String: Any]]) {
    guard found.count < 15 else { return }
    if compile(id, rules + suffix) == nil { return }
    if rules.count == 1 { found.append(rules[0]); return }
    let mid = rules.count / 2
    bisect(id, Array(rules[..<mid]), suffix: suffix, found: &found)
    bisect(id, Array(rules[mid...]), suffix: suffix, found: &found)
}

func check(_ name: String, _ rules: [[String: Any]], suffix: [[String: Any]]) {
    let start = Date()
    if let error = compile(name, rules + suffix) {
        log("::error::\(name) (\(rules.count + suffix.count) rules) rejected: \(error)")
        failures += 1
        if compile(name + ".suffix", suffix) != nil, !suffix.isEmpty { log("  the shared tail itself is rejected") }
        var bad: [[String: Any]] = []
        bisect(name + ".bisect", rules, suffix: suffix, found: &bad)
        for rule in bad {
            let data = (try? JSONSerialization.data(withJSONObject: rule)) ?? Data()
            log("  bad rule: \(String(data: data, encoding: .utf8) ?? "?")")
        }
    } else {
        log("\(name): \(rules.count + suffix.count) rules compiled in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
    }
}

let allow = UBlockConverter.allowlistRule(["example.com", "news.ycombinator.com"]).map { [$0] } ?? []
let netParts = UBlockConverter.chunked(net.normal, max(1_000, UBlockConverter.defaultChunkSize - net.tail.count - 1))
for (i, part) in netParts.enumerated() { check("ubo.net.\(i)", part, suffix: net.tail + allow) }
for (i, part) in UBlockConverter.chunked(cosmetic.rules, UBlockConverter.defaultChunkSize - 1).enumerated() {
    check("ubo.css.\(i)", part, suffix: allow)
}

// MARK: Scriptlets

for world in ["main", "isolated"] {
    guard let list = bodies[world], !list.isEmpty else { continue }
    guard let begin = text("scripting/scriptlet/\(world)/scriptlet-begin.js"),
          let end = text("scripting/scriptlet/\(world)/scriptlet-end.js") else {
        log("::error::missing scriptlet framework for \(world)"); failures += 1; continue
    }
    let bundle = UBlockConverter.scriptletBundle(([begin] + list + [end]).joined(separator: "\n;\n"), allowlist: ["example.com"])
    let context = JSContext()!
    context.setObject(bundle, forKeyedSubscript: "src" as NSString)
    let verdict = context.evaluateScript("(function () { try { new Function(src); return 'ok'; } catch (e) { return String(e); } })()")?.toString() ?? "?"
    log("Scriptlets (\(world)): \(list.count) rulesets, \(bundle.utf8.count / 1024) KB, syntax \(verdict)")
    if verdict != "ok" { failures += 1; log("::error::scriptlet bundle (\(world)) has a syntax error") }
}

log(failures == 0 ? "uBO check passed" : "uBO check found \(failures) problem(s)")
exit(failures == 0 ? 0 : 1)
