import Foundation
import WebKit

/// Compiles and hands out WebKit content rule lists: Saints' built-in tracker / ad / cookie-banner
/// lists plus any `declarative_net_request` rulesets shipped by installed extensions.
final class ContentBlocker: ObservableObject {
    static let shared = ContentBlocker()

    @Published private(set) var lists: [String: WKContentRuleList] = [:]
    @Published private(set) var lastError: String?

    private let store: WKContentRuleListStore? = WKContentRuleListStore.default()

    // MARK: Built-in lists

    static let trackerDomains: [String] = [
        "google-analytics.com", "googletagmanager.com", "googletagservices.com", "analytics.google.com",
        "doubleclick.net", "stats.g.doubleclick.net", "connect.facebook.net", "pixel.facebook.com",
        "graph.facebook.com/tr", "analytics.twitter.com", "static.ads-twitter.com", "ads.linkedin.com",
        "px.ads.linkedin.com", "snap.licdn.com", "bat.bing.com", "clarity.ms", "hotjar.com", "hotjar.io",
        "mouseflow.com", "fullstory.com", "logrocket.io", "lr-ingest.io", "segment.io", "segment.com/analytics",
        "cdn.segment.com", "api.segment.io", "mixpanel.com", "mxpnl.com", "amplitude.com", "heap.io",
        "heapanalytics.com", "kissmetrics.com", "quantserve.com", "quantcount.com", "scorecardresearch.com",
        "comscore.com", "chartbeat.com", "chartbeat.net", "newrelic.com", "nr-data.net", "optimizely.com",
        "crazyegg.com", "inspectlet.com", "luckyorange.com", "luckyorange.net", "smartlook.com",
        "statcounter.com", "tiqcdn.com", "tealiumiq.com", "omtrdc.net", "demdex.net", "everesttech.net",
        "2o7.net", "krxd.net", "bluekai.com", "exelator.com", "agkn.com", "rlcdn.com", "adsrvr.org",
        "bounceexchange.com", "bouncex.net", "branch.io", "app.link", "appsflyer.com", "adjust.com",
        "kochava.com", "braze.com", "sentry-cdn.com", "bugsnag.com", "matomo.cloud", "tiktok.com/i18n/pixel",
        "analytics.tiktok.com", "ct.pinterest.com", "sc-static.net", "tr.snapchat.com", "pippio.com",
        "addthis.com", "sharethis.com", "zemanta.com", "dotomi.com", "yieldify.com", "piano.io",
        "cxense.com", "permutive.com", "permutive.app", "id5-sync.com", "liadm.com", "tapad.com",
        "trustarc.com/analytics", "mookie1.com", "parsely.com", "parse.ly", "webtrends.com",
        "yandex.ru/metrika", "mc.yandex.ru", "top-fwz1.mail.ru", "hm.baidu.com", "cnzz.com"
    ]

    static let adDomains: [String] = [
        "adservice.google.com", "pagead2.googlesyndication.com", "googlesyndication.com", "googleadservices.com",
        "adnxs.com", "adsafeprotected.com", "advertising.com", "amazon-adsystem.com", "taboola.com",
        "outbrain.com", "criteo.com", "criteo.net", "pubmatic.com", "rubiconproject.com", "openx.net",
        "casalemedia.com", "contextweb.com", "sovrn.com", "lijit.com", "33across.com", "media.net",
        "moatads.com", "serving-sys.com", "smartadserver.com", "teads.tv", "yieldmo.com", "sharethrough.com",
        "triplelift.com", "indexww.com", "adform.net", "adroll.com", "revcontent.com", "mgid.com",
        "propellerads.com", "popads.net", "popcash.net", "adcash.com", "exoclick.com", "juicyads.com",
        "trafficjunky.net", "zedo.com", "undertone.com", "spotxchange.com", "springserve.com",
        "doubleverify.com", "admob.com", "unityads.unity3d.com", "applovin.com", "inmobi.com",
        "vungle.com", "chartboost.com", "ads.yahoo.com", "gemini.yahoo.com", "adtechus.com",
        "bidswitch.net", "gumgum.com", "kargo.com", "nativo.com", "adskeeper.com", "ad.doubleclick.net"
    ]

    static let cookieBannerSelectors: [String] = [
        "#onetrust-banner-sdk", "#onetrust-consent-sdk", "#CybotCookiebotDialog", "#CybotCookiebotDialogBodyUnderlay",
        ".fc-consent-root", "#usercentrics-root", "#didomi-host", ".didomi-popup-open", ".qc-cmp2-container",
        "#qc-cmp2-container", ".osano-cm-window", "#truste-consent-track", "#truste-consent-content",
        ".truste_box_overlay", "#cookie-law-info-bar", ".cookie-notice-container", "#cookie-notice",
        "#cookieConsent", ".cookieConsent", "#cookie-banner", ".cookie-banner", "#cookiebanner",
        ".cc-window", ".cc-banner", "#gdpr-cookie-message", ".gdpr-banner", "#cmpbox", "#cmpbox2",
        ".cmp-container", "#sp_message_container_*", "div[id^='sp_message_container']",
        ".evidon-banner", "#_evidon_banner", ".cky-consent-container", ".cky-overlay", "#moove_gdpr_cookie_info_bar",
        ".termly-styles-root", "#termly-code-snippet-support", ".iubenda-cs-container", "#iubenda-cs-banner",
        ".klaro", "#BorlabsCookieBox", ".borlabs-cookie", "#cookie-consent-banner", ".js-cookie-consent"
    ]

    static func domainFilter(_ entry: String) -> String {
        // "example.com/path" → host match + path prefix.
        let parts = entry.split(separator: "/", maxSplits: 1).map(String.init)
        let host = NSRegularExpression.escapedPattern(for: parts[0])
        if parts.count > 1 {
            return "^[^:]+://+([^:/]+\\.)?\(host)[:/].*\(NSRegularExpression.escapedPattern(for: parts[1]))"
        }
        return "^[^:]+://+([^:/]+\\.)?\(host)[:/]"
    }

    static func blockRules(for domains: [String]) -> [[String: Any]] {
        domains.map { domain in
            [
                "trigger": ["url-filter": domainFilter(domain), "load-type": ["third-party"]],
                "action": ["type": "block"]
            ]
        }
    }

    static func cookieRules() -> [[String: Any]] {
        let valid = cookieBannerSelectors.filter { !$0.contains("*") }
        return stride(from: 0, to: valid.count, by: 20).map { start in
            let chunk = valid[start..<min(start + 20, valid.count)]
            return [
                "trigger": ["url-filter": ".*"],
                "action": ["type": "css-display-none", "selector": chunk.joined(separator: ", ")]
            ]
        }
    }

    // MARK: Compilation

    func compileBuiltIns(settings: SettingsData, completion: (() -> Void)? = nil) {
        let group = DispatchGroup()
        let specs: [(String, Bool, () -> [[String: Any]])] = [
            ("saints.trackers.v1", settings.blockTrackers, { Self.blockRules(for: Self.trackerDomains) }),
            ("saints.ads.v1", settings.blockAds, { Self.blockRules(for: Self.adDomains) }),
            ("saints.cookies.v1", settings.blockCookieBanners, { Self.cookieRules() })
        ]
        for (identifier, enabled, build) in specs {
            if !enabled {
                lists.removeValue(forKey: identifier)
                continue
            }
            if lists[identifier] != nil { continue }
            group.enter()
            compile(identifier: identifier, rules: build()) { group.leave() }
        }
        group.notify(queue: .main) { completion?() }
    }

    func compile(identifier: String, rules: [[String: Any]], completion: (() -> Void)? = nil) {
        guard !rules.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.lists.removeValue(forKey: identifier)
                completion?()
            }
            return
        }
        store?.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { [weak self] list, error in
            DispatchQueue.main.async {
                if let list {
                    self?.lists[identifier] = list
                } else if let error {
                    self?.lastError = "\(identifier): \(error.localizedDescription)"
                }
                completion?()
            }
        }
    }

    func remove(identifier: String) {
        lists.removeValue(forKey: identifier)
        store?.removeContentRuleList(forIdentifier: identifier) { _ in }
    }

    /// Replaces every list whose identifier starts with `prefix` (used by the uBlock Origin engine).
    func replaceLists(prefix: String, with newLists: [String: WKContentRuleList]) {
        for key in lists.keys where key.hasPrefix(prefix) && newLists[key] == nil {
            lists.removeValue(forKey: key)
        }
        for (key, list) in newLists { lists[key] = list }
    }

    func apply(to controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
        for list in lists.values {
            controller.add(list)
        }
    }
}
