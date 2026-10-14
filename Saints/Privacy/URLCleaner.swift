import Foundation

/// Removes well-known cross-site tracking parameters from URLs before they load.
enum URLCleaner {
    static let exactParams: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "igshid", "igsh", "mc_cid", "mc_eid", "mkt_tok", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp",
        "hsctatracking", "oly_anon_id", "oly_enc_id", "rb_clickid", "s_cid", "vero_conv", "vero_id",
        "wickedid", "_openstat", "ref_src", "ref_url", "spm", "scm", "srsltid", "epik",
        "trk", "trkCampaign", "sc_campaign", "sc_channel", "sc_content", "sc_medium", "sc_outcome",
        "sc_geo", "sc_country", "cvid", "ocid", "irclickid", "zanpid", "ga_source", "ga_medium",
        "ga_term", "ga_content", "ga_campaign", "ga_place", "_ga", "_gl", "pk_campaign", "pk_kwd",
        "piwik_campaign", "piwik_kwd", "mtm_campaign", "mtm_source", "mtm_medium", "utm_id"
    ]
    static let prefixes: [String] = ["utm_", "pf_rd_", "pd_rd_", "hmb_", "itm_"]

    /// Returns a cleaned URL, or nil if nothing was removed.
    static func clean(_ url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, !items.isEmpty else { return nil }
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if exactParams.contains(name) || exactParams.contains(item.name) { return false }
            return !prefixes.contains(where: { name.hasPrefix($0) })
        }
        guard kept.count != items.count else { return nil }
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.url
    }
}

/// Local-only counters shown on the home page. Never leave the device.
final class PrivacyStats: ObservableObject {
    static let shared = PrivacyStats()
    @Published private(set) var linksCleaned: Int
    @Published private(set) var httpsUpgrades: Int
    @Published private(set) var popupsBlocked: Int

    private init() {
        let d = UserDefaults.standard
        linksCleaned = d.integer(forKey: "stats.cleaned")
        httpsUpgrades = d.integer(forKey: "stats.https")
        popupsBlocked = d.integer(forKey: "stats.popups")
    }

    func addCleaned() { linksCleaned += 1; UserDefaults.standard.set(linksCleaned, forKey: "stats.cleaned") }
    func addUpgrade() { httpsUpgrades += 1; UserDefaults.standard.set(httpsUpgrades, forKey: "stats.https") }
    func addPopup() { popupsBlocked += 1; UserDefaults.standard.set(popupsBlocked, forKey: "stats.popups") }

    func reset() {
        linksCleaned = 0; httpsUpgrades = 0; popupsBlocked = 0
        ["stats.cleaned", "stats.https", "stats.popups"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}
