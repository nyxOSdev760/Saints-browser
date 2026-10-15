import Foundation

/// Per-site overrides: which browser to identify as, and whether protections are off.
/// "Protections off" shares uBlock Origin's allowlist so there is one list of exempt sites.
final class SiteSettings: ObservableObject {
    static let shared = SiteSettings()
    private static let identitiesKey = "saints.siteIdentities"

    @Published private(set) var identities: [String: BrowserIdentity] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.identitiesKey),
           let decoded = try? JSONDecoder().decode([String: BrowserIdentity].self, from: data) {
            identities = decoded
        }
    }

    /// `www.example.com` → `example.com`
    static func key(_ host: String) -> String {
        var h = host.lowercased()
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// The identity chosen for this host or any parent domain.
    func identity(for host: String?) -> BrowserIdentity? {
        guard let host else { return nil }
        let h = Self.key(host)
        if let exact = identities[h] { return exact }
        return identities.first { h.hasSuffix("." + $0.key) }?.value
    }

    func setIdentity(_ identity: BrowserIdentity?, for host: String) {
        identities[Self.key(host)] = identity
        if let data = try? JSONEncoder().encode(identities) {
            UserDefaults.standard.set(data, forKey: Self.identitiesKey)
        }
    }

    // MARK: Protections

    var protectionsOffHosts: [String] { UBlockEngine.shared.state.allowlist }

    func protectionsOff(_ host: String?) -> Bool { UBlockEngine.shared.isAllowlisted(host) }

    /// JS expression that is true on sites with protections off.
    static var offGuardJS: String {
        let list = UBlockEngine.shared.state.allowlist.map { "'\($0)'" }.joined(separator: ",")
        return "[\(list)].some((d) => location.hostname === d || location.hostname.endsWith('.' + d))"
    }
}
